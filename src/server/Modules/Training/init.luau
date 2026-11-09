--[[
	Training · módulo core: la Sala de Entrenamiento (AFK activo) y el alijo de la Guarida.

	Un jugador "entrena" mientras Game dice que está dentro del volumen de la Sala, sin
	estrellas y con el nivel necesario. Cada TickSeconds el servidor suma tiempo pagado
	(con tope diario, guardado en la sección "training") y publica `ticked`; Game paga XP y
	Dinero. Cada cierto tiempo (con variación aleatoria) el servidor emite un reto de
	check-in; sin respuesta a tiempo el pago se pausa. Respuestas demasiado rápidas o con
	tiempos idénticos se marcan como sospechosas. Un autoclick no rinde más que un
	jugador atento: el reto cambia de lugar y el tope diario es el mismo.

	El alijo calcula, con la hora del servidor, cuánto se acumuló desde la última vez.

	No sabe cómo se paga ni dónde está la sala: Game le pasa funciones.

	Publica atributos: AfkActive, AfkPaused, AfkReason ("", "checkin", "locked", "cap"),
	AfkUsed, AfkCap (segundos) y AfkNextCheckIn (segundos que faltan).

	API:
	  Training.init(options)    { isTraining(player), capSeconds(player), intervalSeconds(player), stashCapSeconds(player) }
	  Training.start()
	  Training.answer(player, challengeId, choice) -> "ok" | "wrong" | "fast" | "stale" | "locked"
	  Training.stashSeconds(player)                -> number segundos acumulados (con tope)
	  Training.claimStash(player)                  -> number? segundos reclamados
	  Training.ticked                              Signal (player, segundos)
	  Training.challengeIssued                     Signal (player, spec)
	  Training.checkedIn                           Signal (player, minutosDeBono)
	  Training.suspect                             Signal (player)
	  Training.stateChanged                        Signal (player, "active" | "paused" | "idle")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local TrainingData = require(script.TrainingData)

export type Options = {
	isTraining: (player: Player) -> boolean,
	capSeconds: (player: Player) -> number,
	intervalSeconds: (player: Player) -> number,
	stashCapSeconds: (player: Player) -> number,
}

export type Spec = {
	id: string,
	options: { string },
	target: string,
	window: number,
}

type State = {
	active: boolean,
	nextCheckIn: number?,
	pending: { spec: Spec, issuedAt: number, deadline: number }?,
	paused: boolean,
	lockUntil: number,
	wrong: number,
	reactions: { number },
	hard: boolean,
	lastState: string,
}

local Training = {}

Training.ticked = Signal.new() :: Signal.Signal<Player, number>
Training.challengeIssued = Signal.new() :: Signal.Signal<Player, Spec>
Training.checkedIn = Signal.new() :: Signal.Signal<Player, number>
Training.suspect = Signal.new() :: Signal.Signal<Player>
Training.stateChanged = Signal.new() :: Signal.Signal<Player, string>

local CHOICES = { "patata", "capibara", "tiburon", "cafetera", "banana", "estrella", "helicoptero" }

local options: Options? = nil
local states: { [Player]: State } = {}
local random = Random.new()
local serial = 0

local function schedule(player: Player, state: State)
	assert(options)
	local base = options.intervalSeconds(player)
	local jitter = Tuning.get("Afk.CheckInJitter")
	local seconds = math.min(base * (1 + random:NextNumber(-jitter, jitter)), Tuning.get("Afk.CheckInMaxSeconds"))
	state.nextCheckIn = os.clock() + math.max(30, seconds)
end

local function issue(player: Player, state: State)
	local count = if state.hard then 5 else 3
	local pool = table.clone(CHOICES)
	local picked: { string } = {}
	for _ = 1, count do
		table.insert(picked, table.remove(pool, random:NextInteger(1, #pool)) :: string)
	end
	serial += 1
	local spec: Spec = {
		id = `{player.UserId}-{serial}`,
		options = picked,
		target = picked[random:NextInteger(1, #picked)],
		window = Tuning.get("Afk.ChallengeWindowSeconds"),
	}
	local now = os.clock()
	state.pending = { spec = spec, issuedAt = now, deadline = now + spec.window }
	Training.challengeIssued:Fire(player, spec)
end

local function setState(player: Player, state: State, label: string)
	if state.lastState ~= label then
		state.lastState = label
		Training.stateChanged:Fire(player, label)
	end
end

local function publish(player: Player, state: State, used: number, cap: number, reason: string)
	player:SetAttribute("AfkActive", state.active)
	player:SetAttribute("AfkPaused", reason == "checkin" or reason == "locked")
	player:SetAttribute("AfkReason", reason)
	player:SetAttribute("AfkUsed", math.floor(used))
	player:SetAttribute("AfkCap", math.floor(cap))
	player:SetAttribute("AfkNextCheckIn", if state.nextCheckIn and state.active then math.max(0, math.floor(state.nextCheckIn - os.clock())) else 0)
end

local function think(player: Player, state: State)
	assert(options)
	local now = os.clock()
	local cap = options.capSeconds(player)
	local used = TrainingData.usedToday(player)
	local active = options.isTraining(player)
	state.active = active
	local reason = ""
	if not active then
		state.nextCheckIn = nil
		state.pending = nil
		state.paused = false
		setState(player, state, "idle")
		publish(player, state, used, cap, "")
		return
	end
	if not state.nextCheckIn then
		schedule(player, state)
	end
	local pending = state.pending
	if pending and now > pending.deadline then
		state.paused = true
	end
	if not pending and now >= state.lockUntil and state.nextCheckIn and now >= state.nextCheckIn then
		issue(player, state)
	end
	if now < state.lockUntil then
		reason = "locked"
	elseif state.paused then
		reason = "checkin"
	elseif used >= cap then
		reason = "cap"
	end
	if reason == "" then
		local total = TrainingData.addUsed(player, Tuning.get("Afk.TickSeconds"))
		if total then
			used = total
			Training.ticked:Fire(player, Tuning.get("Afk.TickSeconds"))
		end
		setState(player, state, "active")
	else
		setState(player, state, "paused")
	end
	publish(player, state, used, cap, reason)
end

function Training.init(opts: Options)
	options = opts
end

function Training.start()
	local function onPlayerAdded(player: Player)
		states[player] = {
			active = false,
			nextCheckIn = nil,
			pending = nil,
			paused = false,
			lockUntil = 0,
			wrong = 0,
			reactions = {},
			hard = false,
			lastState = "idle",
		}
		player:SetAttribute("AfkActive", false)
		if TrainingData.waitUntilReady(player) then
			local data = TrainingData.get(player)
			if data and data.stashClaimedAt == 0 then
				TrainingData.claimStash(player) -- la primera vez el alijo empieza a acumular desde ahora
			end
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < Tuning.get("Afk.TickSeconds") then
			return
		end
		elapsed = 0
		for player, state in states do
			if player.Parent and TrainingData.get(player) then
				local ok, err = pcall(think, player, state)
				if not ok then
					warn(`[Training] {player.Name}: {err}`)
				end
			end
		end
	end)
end

function Training.answer(player: Player, challengeId: string, choice: string): string
	local state = states[player]
	if not state then
		return "stale"
	end
	local now = os.clock()
	if now < state.lockUntil then
		return "locked"
	end
	local pending = state.pending
	if not pending or pending.spec.id ~= challengeId then
		return "stale"
	end
	local reaction = now - pending.issuedAt
	if reaction < Tuning.get("Afk.ChallengeMinReactionSeconds") then
		-- Imposible para una persona: se descarta y vuelve un reto más difícil.
		state.hard = true
		state.pending = nil
		issue(player, state)
		return "fast"
	end
	if choice ~= pending.spec.target then
		state.wrong += 1
		state.pending = nil
		if state.wrong >= Tuning.get("Afk.ChallengeWrongLimit") then
			state.wrong = 0
			state.lockUntil = now + Tuning.get("Afk.ChallengeLockMinutes") * 60
			state.paused = true
		else
			issue(player, state)
		end
		return "wrong"
	end
	state.wrong = 0
	state.pending = nil
	state.paused = false
	table.insert(state.reactions, reaction)
	local streak = Tuning.get("Afk.SuspectStreak")
	while #state.reactions > streak do
		table.remove(state.reactions, 1)
	end
	local suspicious = false
	if #state.reactions == streak then
		local low, high = math.huge, -math.huge
		for _, value in state.reactions do
			low, high = math.min(low, value), math.max(high, value)
		end
		suspicious = high - low <= Tuning.get("Afk.SuspectToleranceSeconds")
	end
	schedule(player, state)
	if suspicious then
		state.hard = true
		Training.suspect:Fire(player)
	else
		state.hard = false
		Training.checkedIn:Fire(player, Tuning.get("Afk.CheckInBonusMinutes"))
	end
	return "ok"
end

function Training.stashSeconds(player: Player): number
	assert(options)
	local data = TrainingData.get(player)
	if not data or data.stashClaimedAt == 0 then
		return 0
	end
	return math.clamp(os.time() - data.stashClaimedAt, 0, options.stashCapSeconds(player))
end

function Training.claimStash(player: Player): number?
	local seconds = Training.stashSeconds(player)
	if seconds <= 0 then
		return nil
	end
	if TrainingData.claimStash(player) == nil then
		return nil
	end
	return seconds
end

return Training
