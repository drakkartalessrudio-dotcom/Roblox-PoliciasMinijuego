--[[
	Wanted · módulo core: el calor y las estrellas de búsqueda (1 a 6) de cada jugador.
	Todo es estado de sesión (no se guarda).

	El calor sube cuando hay un testigo (Game decide cuándo) y las estrellas son sus
	umbrales (Heat.StarThresholds), con un techo que depende del nivel del jugador
	(`capFor`). Estados:
	  · clear      sin estrellas
	  · seen       algún policía lo ve: el calor no baja y sube lento (presión de persecución)
	  · searching  sin ser visto desde hace LoseSightSeconds: el calor baja y las
	               estrellas parpadean hasta desaparecer
	Esconderse (Wanted.setHidden) quita una estrella cada Hide.SecondsPerStar.

	No sabe quién ve al jugador ni qué es un policía: Cops_Wanted llama a setSeen.

	Publica atributos del jugador: Stars, Heat, WantedState y Spotted (true solo mientras un
	policía lo ve de verdad; `seen` en WantedState dura hasta LoseSightSeconds tras perder la vista).

	API:
	  Wanted.init(options)                  { capFor(player), decayBonus(player) }
	  Wanted.start()
	  Wanted.addHeat(player, cantidad, motivo?)   -> number estrellas tras sumar (motivo "contagio" no se contagia)
	  Wanted.setSeen(player, visto)         lo llama el puente con Cops
	  Wanted.raiseTo(player, estrellas, motivo?)  sube el calor hasta el umbral de esas estrellas (si no lo tenía ya)
	  Wanted.setHidden(player, escondido)   Game, según Areas y la distancia de los policías
	  Wanted.clear(player, motivo)          quita todas las estrellas ("escape", "spray", "arrest", "leave")
	  Wanted.stars(player)                  -> number
	  Wanted.state(player)                  -> "clear" | "seen" | "searching"
	  Wanted.heatAdded                      Signal (player, cantidad, motivo)
	  Wanted.starsChanged                   Signal (player, estrellas, anteriores)
	  Wanted.starReached                    Signal (player, estrellas) cada vez que alcanza una nueva por primera vez en su ciclo
	  Wanted.cleared                        Signal (player, estrellasQueTenía, motivo)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

export type Options = {
	capFor: (player: Player) -> number,
	decayBonus: (player: Player) -> number, -- 0 = sin bono; 0,24 = +24 % de bajada del calor
}

type State = {
	heat: number,
	stars: number,
	status: string,
	seen: boolean,
	lastSeenAt: number,
	hidden: boolean,
	hiddenFor: number,
	pressure: number,
	peak: number, -- estrellas máximas de este ciclo (para starReached)
}

local Wanted = {}

Wanted.heatAdded = Signal.new() :: Signal.Signal<Player, number, string>
Wanted.starsChanged = Signal.new() :: Signal.Signal<Player, number, number>
Wanted.starReached = Signal.new() :: Signal.Signal<Player, number>
Wanted.cleared = Signal.new() :: Signal.Signal<Player, number, string>

local options: Options? = nil
local states: { [Player]: State } = {}

local function newState(): State
	return { heat = 0, stars = 0, status = "clear", seen = false, lastSeenAt = 0, hidden = false, hiddenFor = 0, pressure = 0, peak = 0 }
end

local function starsForHeat(heat: number, cap: number): number
	local stars = 0
	for index, threshold in Tuning.get("Heat.StarThresholds") do
		if heat >= threshold and index <= cap then
			stars = index
		end
	end
	return stars
end

local function publish(player: Player, state: State)
	player:SetAttribute("Stars", state.stars)
	player:SetAttribute("Heat", math.floor(state.heat))
	player:SetAttribute("WantedState", state.status)
	player:SetAttribute("Spotted", state.seen)
end

local function refresh(player: Player, state: State)
	assert(options)
	local previous = state.stars
	local cap = options.capFor(player)
	state.stars = starsForHeat(state.heat, cap)
	if state.stars == 0 and state.heat <= 0 then
		state.status = "clear"
	elseif state.status == "clear" then
		state.status = "seen"
	end
	publish(player, state)
	if state.stars ~= previous then
		Wanted.starsChanged:Fire(player, state.stars, previous)
		if state.stars > state.peak then
			state.peak = state.stars
			Wanted.starReached:Fire(player, state.stars)
		end
	end
end

function Wanted.init(opts: Options)
	options = opts
end

function Wanted.start()
	local function onPlayerAdded(player: Player)
		states[player] = newState()
		player:SetAttribute("Stars", 0)
		player:SetAttribute("Heat", 0)
		player:SetAttribute("WantedState", "clear")
		player:SetAttribute("Spotted", false)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		local step = elapsed
		elapsed = 0
		local now = os.clock()
		for player, state in states do
			if state.status == "clear" then
				continue
			end
			if state.seen then
				state.lastSeenAt = now
				state.status = "seen"
				state.pressure += step
				if state.pressure >= 5 then
					state.pressure -= 5
					Wanted.addHeat(player, Tuning.get("Heat.ChasePressurePer5s"), "persecucion")
				end
			else
				state.pressure = 0
				if state.status == "seen" and now - state.lastSeenAt >= Tuning.get("Heat.LoseSightSeconds") then
					state.status = "searching"
				end
				if state.status == "searching" then
					assert(options)
					local decay = Tuning.get("Heat.DecayPerSecond") * (1 + options.decayBonus(player))
					state.heat = math.max(0, state.heat - decay * step)
					refresh(player, state)
					if state.heat <= 0 and state.stars == 0 then
						local had = state.peak
						state.status = "clear"
						state.peak = 0
						state.hiddenFor = 0
						publish(player, state)
						Wanted.cleared:Fire(player, had, "escape")
						continue
					end
				end
				if state.hidden and state.stars > 0 then
					state.hiddenFor += step
					if state.hiddenFor >= Tuning.get("Hide.SecondsPerStar") then
						state.hiddenFor = 0
						local thresholds = Tuning.get("Heat.StarThresholds")
						state.heat = if state.stars > 1 then thresholds[state.stars - 1] else 0
						state.status = "searching"
						refresh(player, state)
						if state.stars == 0 then
							local had = state.peak
							state.heat, state.status, state.peak = 0, "clear", 0
							publish(player, state)
							Wanted.cleared:Fire(player, had, "escape")
						end
					end
				else
					state.hiddenFor = 0
				end
			end
		end
	end)
end

function Wanted.stars(player: Player): number
	return if states[player] then states[player].stars else 0
end

function Wanted.state(player: Player): string
	return if states[player] then states[player].status else "clear"
end

function Wanted.addHeat(player: Player, amount: number, reason: string?): number
	local state = states[player]
	if not state or amount ~= amount or amount <= 0 then
		return 0
	end
	local why = reason or "travesura"
	state.heat = math.min(state.heat + amount, 9999)
	state.lastSeenAt = os.clock()
	if state.status ~= "seen" then
		state.status = "seen"
	end
	refresh(player, state)
	Wanted.heatAdded:Fire(player, amount, why)
	return state.stars
end

function Wanted.raiseTo(player: Player, stars: number, reason: string?)
	local state = states[player]
	local thresholds = Tuning.get("Heat.StarThresholds")
	local target = thresholds[math.clamp(stars, 1, #thresholds)]
	if state and state.heat < target then
		Wanted.addHeat(player, target - state.heat, reason)
	end
end

function Wanted.setSeen(player: Player, seen: boolean)
	local state = states[player]
	if not state then
		return
	end
	state.seen = seen
	player:SetAttribute("Spotted", seen)
	if seen then
		state.lastSeenAt = os.clock()
		if state.status == "clear" then
			-- Ser visto por un policía ya es una estrella aunque no haya calor: la primera.
			state.heat = math.max(state.heat, Tuning.get("Heat.StarThresholds")[1])
			state.status = "seen"
			refresh(player, state)
			Wanted.heatAdded:Fire(player, state.heat, "visto")
		elseif state.status == "searching" then
			state.status = "seen"
			publish(player, state)
		end
	end
end

function Wanted.setHidden(player: Player, hidden: boolean)
	local state = states[player]
	if state then
		state.hidden = hidden
	end
end

function Wanted.clear(player: Player, reason: string)
	local state = states[player]
	if not state then
		return
	end
	local had = state.peak
	local hadStars = state.stars
	state.heat, state.stars, state.status, state.seen, state.hidden, state.hiddenFor, state.peak = 0, 0, "clear", false, false, 0, 0
	publish(player, state)
	if hadStars > 0 then
		Wanted.starsChanged:Fire(player, 0, hadStars)
	end
	if had > 0 or hadStars > 0 then
		Wanted.cleared:Fire(player, math.max(had, hadStars), reason)
	end
end

return Wanted
