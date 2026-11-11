--[[
	Hiding · los escondites (zonas `hide` y `tutorial_hide` de Levels.json) y quién está oculto en ellos.
	Mezcla Areas, Cops y Wanted, así que es de Game.

	Un escondite no borra las estrellas: te saca de la vista si rompes el contacto antes de entrar y
	te quedas quieto. Reglas (GDD, «Perder las estrellas»; valores en Config.Hide):
	  · Al quedar buscado dentro de la zona (o entrar ya buscado) se decide una vez:
	      - un policía de tierra a WitnessRange o menos que te vea → el escondite se QUEMA para ti
	        durante BurnSeconds (no oculta), porque te vieron entrar;
	      - si ya hay Capacity jugadores a salvo ahí, no hay sitio ("full");
	      - si no, quedas a salvo ("safe").
	  · A salvo, Cops recorta tu visión a RevealDistance (×MovingRevealMult si te mueves más que
	    StillSpeed) y deja de reportarte como visto; Wanted baja una estrella cada SecondsPerStar y
	    enfría el calor DecayMult veces más rápido.
	  · Si un policía llena su barra de detección contra ti (Cops.discovered), te descubre y el
	    escondite se quema. Un contenedor además te expulsa a los ContainerSeconds.
	  · Cada tipo de escondite lo marca la zona (HideKind: "bush" por defecto, "container").

	Atributos del jugador (para el HUD y los efectos del cliente):
	  Hidden      bool    a salvo en un escondite
	  HideState   string  "none" | "safe" | "burned" | "full"
	  HideKind    string  tipo del escondite en el que está ("" fuera)
	  HideLeft    number  segundos que le quedan a un contenedor (0 si no aplica)

	API:
	  Hiding.start()
	  Hiding.stateOf(player)   -> { kind, moving }? oculto a salvo, o nil (lo lee Cops)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Telemetry = require(ServerScriptService.Server.Telemetry)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local Cops = require(ServerScriptService.Server.Modules.Cops)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)

type PlayerState = {
	spot: BasePart?,
	status: string, -- none | safe | burned | full
	decided: boolean, -- ya se evaluó «te vieron entrar» en este escondite
	hiddenFor: number, -- segundos a salvo en este escondite (para el contenedor)
	hide: Cops.Hiding?, -- lo que lee Cops; nil si no está a salvo
	stars: number, -- estrellas al ocultarse (telemetría)
}

local Hiding = {}

local TICK = 0.25

local states: { [Player]: PlayerState } = {}
-- Escondites quemados: por jugador, hasta cuándo (os.clock) no ocultan.
local burnedUntil: { [Player]: { [BasePart]: number } } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function kindOf(spot: BasePart): string
	local kind = spot:GetAttribute("HideKind")
	return if kind == "container" then "container" else "bush"
end

local function publish(player: Player, state: PlayerState)
	local spot = state.spot
	player:SetAttribute("Hidden", state.hide ~= nil)
	player:SetAttribute("HideState", state.status)
	player:SetAttribute("HideKind", if spot then kindOf(spot) else "")
	local left = 0
	if state.hide and state.hide.kind == "container" then
		left = math.max(0, math.ceil(Tuning.get("Hide.ContainerSeconds") - state.hiddenFor))
	end
	player:SetAttribute("HideLeft", left)
	player:SetAttribute("HideMoving", state.hide ~= nil and state.hide.moving)
	-- Escondites quemados para este jugador ahora mismo (ids «nivel/id» entre «;»): el cliente los pinta de rojo.
	local now = os.clock()
	local ids = ""
	for spotPart, untilAt in burnedUntil[player] or {} do
		if untilAt > now then
			ids ..= `;{spotPart:GetAttribute("LevelId")}/{spotPart:GetAttribute("PieceId")}`
		end
	end
	player:SetAttribute("HideBurned", if ids == "" then "" else ids .. ";")
end

local function setSafe(player: Player, state: PlayerState, kind: string?)
	if kind then
		local hide = state.hide
		if not hide then
			state.hide = { kind = kind, moving = false }
		end
	else
		state.hide = nil
	end
	Wanted.setHidden(player, state.hide ~= nil)
end

-- El escondite deja de ocultar a este jugador un rato (lo vieron entrar, lo descubrieron o se acabó el contenedor).
local function burn(player: Player, state: PlayerState, reason: string)
	local spot = state.spot
	if not spot then
		return
	end
	local burned = burnedUntil[player]
	if not burned then
		burned = {}
		burnedUntil[player] = burned
	end
	burned[spot] = os.clock() + Tuning.get("Hide.BurnSeconds")
	state.status = "burned"
	state.decided = true
	setSafe(player, state, nil)
	publish(player, state)
	Telemetry.custom(player, "hide_burned", nil, { item = reason, stars = tostring(Wanted.stars(player)) })
end

local function occupants(spot: BasePart, except: Player): number
	local count = 0
	for other, state in states do
		if other ~= except and state.spot == spot and state.hide then
			count += 1
		end
	end
	return count
end

-- Decide, una sola vez por visita, si el escondite oculta a este jugador.
local function decide(player: Player, state: PlayerState, spot: BasePart, now: number)
	state.decided = true
	local burned = burnedUntil[player]
	if burned and (burned[spot] or 0) > now then
		state.status = "burned"
		return
	end
	if occupants(spot, player) >= Tuning.get("Hide.Capacity") then
		state.status = "full"
		return
	end
	if Cops.watchedBy(player, Tuning.get("Hide.WitnessRange")) then
		burn(player, state, "seen")
		return
	end
	state.status = "safe"
	state.hiddenFor = 0
	state.stars = Wanted.stars(player)
	setSafe(player, state, kindOf(spot))
	Telemetry.custom(player, "hide_entered", state.stars, { item = kindOf(spot), stars = tostring(state.stars) })
end

local function step(dt: number)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local state = states[player]
		if not state then
			state = { spot = nil, status = "none", decided = false, hiddenFor = 0, hide = nil, stars = 0 }
			states[player] = state
		end
		local root = rootOf(player)
		local spot = nil
		if root then
			spot = Areas.inside(player, "hide") or Areas.inside(player, "tutorial_hide")
		end

		-- Cambió de escondite (o salió): se empieza de cero.
		if spot ~= state.spot then
			state.spot = spot
			state.status = "none"
			state.decided = false
			state.hiddenFor = 0
			setSafe(player, state, nil)
		end

		if spot and root then
			local burned = burnedUntil[player]
			if state.status == "burned" and burned and (burned[spot] or 0) <= now then
				state.decided = false -- se enfrió: vuelve a evaluarse si hay alguien mirando
			end
			if not state.decided and Wanted.stars(player) > 0 then
				decide(player, state, spot, now)
			end
			local hide = state.hide
			if hide then
				local velocity = root.AssemblyLinearVelocity
				hide.moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > Tuning.get("Hide.StillSpeed")
				state.hiddenFor += dt
				if hide.kind == "container" and state.hiddenFor >= Tuning.get("Hide.ContainerSeconds") then
					burn(player, state, "timeout")
				end
			end
		end
		Wanted.setHidden(player, state.hide ~= nil) -- Wanted.clear lo apaga; aquí se resincroniza
		publish(player, state)
	end
end

function Hiding.stateOf(player: Player): Cops.Hiding?
	local state = states[player]
	return if state then state.hide else nil
end

function Hiding.start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		burnedUntil[player] = nil
	end)

	-- Un policía llenó su barra contra alguien oculto: lo descubrió.
	Cops.discovered:Connect(function(player)
		local state = states[player]
		if state and state.hide then
			burn(player, state, "discovered")
		end
	end)

	-- Escapó estando oculto: es el escape que cuenta como «escondido».
	Wanted.cleared:Connect(function(player, stars, reason)
		local state = states[player]
		if state and state.hide and reason == "escape" then
			Telemetry.custom(player, "hide_escaped", stars, { item = state.hide.kind, stars = tostring(stars) })
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= TICK then
			local step_ = elapsed
			elapsed = 0
			step(step_)
		end
	end)
end

return Hiding
