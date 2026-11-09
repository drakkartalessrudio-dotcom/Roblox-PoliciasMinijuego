--[[
	Mischief · módulo core: las travesuras. Cada punto de travesura es una zona de
	Levels.json (graffiti, timbrazo, hidrante…, y las de banda). El jugador la inicia
	desde un ProximityPrompt; el cliente muestra el minijuego y envía el resultado; el
	SERVIDOR valida la distancia, el nivel, el enfriamiento y la duración, y publica el
	resultado. El pago, el calor y el XP los pone Game: este módulo no conoce la economía.

	El servidor no ve el minijuego, así que valida lo que sí puede: que el jugador esté
	cerca, que haya pasado al menos MinDurationRatio de la duración (ya reducida por Manos
	Rápidas) y que no haya expirado. El Timbrazo se verifica por completo en el servidor:
	hay que alejarse TimbrazoDistance studs antes de TimbrazoSeconds.

	Travesuras de banda: Game pasa `partyFor` para saber quiénes participan; solo
	arrancan con el mínimo de jugadores y pagan a cada uno según cuántos participan.

	También guarda el álbum de graffitis en la sección "album" (AlbumData).

	API:
	  Mischief.init(options)                 { spots, canStart, durationScale, partyFor, maxDesigns }
	  Mischief.start()                       crea los ProximityPrompt y atiende los mensajes
	  Mischief.request(player, spotKey)      -> (boolean, string?)  lo llama Net
	  Mischief.submit(player, sessionId, success) -> (boolean, string?)
	  Mischief.cancel(player)
	  Mischief.active(player)                -> boolean ¿está haciendo una travesura ahora mismo?
	  Mischief.unlockDesign(player, designId) -> boolean
	  Mischief.started                       Signal (player, session)
	  Mischief.completed                     Signal (player, result)
	  Mischief.failed                        Signal (player, defId, reason)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local AlbumData = require(script.AlbumData)

export type Spot = {
	key: string,
	part: BasePart,
	def: Catalog.MischiefDef,
}

export type Session = {
	id: string,
	player: Player,
	spot: Spot,
	startedAt: number,
	duration: number, -- segundos nominales ya reducidos por Manos Rápidas
	partySize: number,
	game: Catalog.MischiefGame,
}

export type Result = {
	def: Catalog.MischiefDef,
	config: { [string]: number },
	position: Vector3,
	partySize: number,
	speedMult: number, -- solo el Timbrazo: 1,0 a 1,8
	spotKey: string,
}

export type Options = {
	spots: { Spot },
	canStart: (player: Player, def: Catalog.MischiefDef) -> (boolean, string?),
	durationScale: (player: Player) -> number, -- 1 = sin reducción; 0,6 = −40 %
	partyFor: (player: Player, spot: Spot) -> { Player },
	maxDesigns: number,
}

local Mischief = {}

Mischief.started = Signal.new() :: Signal.Signal<Player, Session>
Mischief.completed = Signal.new() :: Signal.Signal<Player, Result>
Mischief.failed = Signal.new() :: Signal.Signal<Player, string, string>

local options: Options? = nil
local spotsByKey: { [string]: Spot } = {}
local sessions: { [Player]: Session } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local timbrazos: { [Player]: { session: Session, origin: Vector3 } } = {}
local serial = 0

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function distanceToSpot(root: BasePart, part: BasePart): number
	local local_ = part.CFrame:PointToObjectSpace(root.Position)
	local half = part.Size / 2
	local outside = Vector3.new(math.max(math.abs(local_.X) - half.X, 0), math.max(math.abs(local_.Y) - half.Y, 0), math.max(math.abs(local_.Z) - half.Z, 0))
	return outside.Magnitude
end

local function spotKeyOf(part: BasePart): string
	return `{part:GetAttribute("LevelId")}:{part:GetAttribute("PieceId")}`
end

local function createPrompt(spot: Spot)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if spot.def.coop then "Hacer en banda" else "Hacer travesura"
	prompt.ObjectText = spot.def.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Tuning.get("Mischief.StartRange")
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = spot.part
	prompt.Triggered:Connect(function(player: Player)
		Mischief.request(player, spot.key)
	end)
end

local function finish(player: Player)
	sessions[player] = nil
	timbrazos[player] = nil
end

local function begin(player: Player, spot: Spot, partySize: number): Session
	assert(options)
	serial += 1
	local config = Catalog.mischiefConfig(spot.def)
	local session: Session = {
		id = `{player.UserId}-{serial}`,
		player = player,
		spot = spot,
		startedAt = os.clock(),
		duration = config.Duration * options.durationScale(player),
		partySize = partySize,
		game = spot.def.game,
	}
	sessions[player] = session
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player][spot.key] = os.clock() + Tuning.get("Mischief.SpotCooldown")
	Mischief.started:Fire(player, session)
	return session
end

function Mischief.init(opts: Options)
	options = opts
	spotsByKey = {}
	for _, spot in opts.spots do
		spotsByKey[spot.key] = spot
	end
end

function Mischief.spotKey(part: BasePart): string
	return spotKeyOf(part)
end

function Mischief.start()
	assert(options)
	for _, spot in options.spots do
		createPrompt(spot)
	end
	Players.PlayerRemoving:Connect(function(player)
		finish(player)
		cooldowns[player] = nil
	end)
	-- Timbrazo: se completa alejándose lo suficiente antes de que se acabe el tiempo.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		local now = os.clock()
		for player, entry in timbrazos do
			local root = rootOf(player)
			local window = Tuning.get("Mischief.TimbrazoSeconds")
			local used = now - entry.session.startedAt
			if not root then
				finish(player)
			elseif (root.Position - entry.origin).Magnitude >= Tuning.get("Mischief.TimbrazoDistance") then
				local speedMult = 1 + (Tuning.get("Mischief.TimbrazoMaxMult") - 1) * math.clamp(1 - used / window, 0, 1)
				local spot = entry.session.spot
				finish(player)
				Mischief.completed:Fire(player, {
					def = spot.def,
					config = Catalog.mischiefConfig(spot.def),
					position = spot.part.Position,
					partySize = 1,
					speedMult = speedMult,
					spotKey = spot.key,
				})
			elseif used > window then
				local defId = entry.session.spot.def.id
				finish(player)
				Mischief.failed:Fire(player, defId, "slow")
			end
		end
	end)
end

function Mischief.request(player: Player, spotKey: string): (boolean, string?)
	assert(options)
	local spot = spotsByKey[spotKey]
	if not spot then
		return false, "unknown"
	end
	local existing = sessions[player]
	if existing and os.clock() - existing.startedAt <= existing.duration + Tuning.get("Mischief.GraceSeconds") then
		return false, "busy"
	end
	local root = rootOf(player)
	if not root then
		return false, "dead"
	end
	if distanceToSpot(root, spot.part) > Tuning.get("Mischief.StartRange") then
		return false, "far"
	end
	local ok, reason = options.canStart(player, spot.def)
	if not ok then
		return false, reason
	end
	local readyAt = cooldowns[player] and cooldowns[player][spotKey]
	if readyAt and os.clock() < readyAt then
		return false, "cooldown"
	end
	local config = Catalog.mischiefConfig(spot.def)
	if spot.def.coop then
		local party = options.partyFor(player, spot)
		if #party < config.MinPlayers then
			return false, "party"
		end
		-- Todos los que están cerca arrancan a la vez; cada uno juega su minijuego.
		for _, member in party do
			if sessions[member] == nil or os.clock() - sessions[member].startedAt > sessions[member].duration + Tuning.get("Mischief.GraceSeconds") then
				begin(member, spot, #party)
			end
		end
		return true, nil
	end
	local session = begin(player, spot, 1)
	if spot.def.game.type == "timbrazo" then
		timbrazos[player] = { session = session, origin = root.Position }
	end
	return true, nil
end

function Mischief.submit(player: Player, sessionId: string, success: boolean): (boolean, string?)
	local session = sessions[player]
	if not session or session.id ~= sessionId then
		return false, "stale"
	end
	if session.game.type == "timbrazo" then
		return false, "server"
	end
	finish(player)
	local elapsed = os.clock() - session.startedAt
	if not success then
		Mischief.failed:Fire(player, session.spot.def.id, "failed")
		return true, nil
	end
	if elapsed < session.duration * Tuning.get("Mischief.MinDurationRatio") then
		Mischief.failed:Fire(player, session.spot.def.id, "fast")
		return false, "fast"
	end
	if elapsed > session.duration + Tuning.get("Mischief.GraceSeconds") then
		Mischief.failed:Fire(player, session.spot.def.id, "late")
		return false, "late"
	end
	Mischief.completed:Fire(player, {
		def = session.spot.def,
		config = Catalog.mischiefConfig(session.spot.def),
		position = session.spot.part.Position,
		partySize = session.partySize,
		speedMult = 1,
		spotKey = session.spot.key,
	})
	return true, nil
end

function Mischief.cancel(player: Player)
	finish(player)
end

-- ¿Está en medio de una travesura? Una sesión que se pasó de tiempo sin enviar resultado ya no cuenta.
function Mischief.active(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and os.clock() - session.startedAt <= session.duration + Tuning.get("Mischief.GraceSeconds")
end

function Mischief.unlockDesign(player: Player, designId: string): boolean
	assert(options)
	return AlbumData.unlock(player, designId, options.maxDesigns)
end

function Mischief.designCount(player: Player): number
	return AlbumData.count(player)
end

return Mischief
