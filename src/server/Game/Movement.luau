--[[
	Movement · lo propio de TravesurasBrainrot sobre el personaje: velocidad según nivel y
	efectos, grupos de colisión, reaparición en la Guarida y teletransporte.

	Los distritos ya no se separan con vallas: están lejos unos de otros y se viaja entre
	ellos con Transit (que exige el nivel). Aquí solo queda el grupo de colisión de los
	jugadores: no se bloquean entre sí ni chocan con los policías.

	Velocidad: Zapatillas, nivel y perks (PlayerStats.baseSpeed) × patineta × Dash × arena
	× efectos de los policías (vapor, red, grito). La recalcula el servidor cada
	Player.SpeedRefreshSeconds y al instante cuando algo cambia.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Tuning = require(ReplicatedStorage.Shared.Tuning)
local LevelLoader = require(ServerScriptService.Server.LevelLoader)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local Arrest = require(ServerScriptService.Server.Modules.Arrest)
local Progress = require(ServerScriptService.Server.Modules.Progress)
local Tools = require(ServerScriptService.Server.Modules.Tools)
local PlayerStats = require(script.Parent.PlayerStats)

export type Context = {
	built: LevelLoader.Built,
	physics: any,
}

local Movement = {}

Movement.COPS_GROUP = "Cops"
Movement.PLAYERS_GROUP = "Players"

local physics: any = nil
local dashUntil: { [Player]: number } = {}
local slowUntil: { [Player]: number } = {}
local slowFactor: { [Player]: number } = {}
local stunUntil: { [Player]: number } = {}
local lastGuarida: { [Player]: Vector3 } = {}
local groupOf: { [Player]: string } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

local function setGroup(character: Model, group: string)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

local function updateGroup(player: Player)
	groupOf[player] = Movement.PLAYERS_GROUP
	if player.Character then
		setGroup(player.Character, Movement.PLAYERS_GROUP)
	end
end

local function setupGroups()
	register(Movement.COPS_GROUP)
	register(Movement.PLAYERS_GROUP)
	PhysicsService:CollisionGroupSetCollidable(Movement.COPS_GROUP, Movement.COPS_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(Movement.COPS_GROUP, Movement.PLAYERS_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(Movement.PLAYERS_GROUP, Movement.PLAYERS_GROUP, false) -- sin bloquearse entre jugadores
end

-- Velocidad que corresponde ahora a un jugador.
local function speedFor(player: Player, root: BasePart): number
	local now = os.clock()
	if now < (stunUntil[player] or 0) then
		return 0
	end
	local speed = PlayerStats.baseSpeed(player)
	if Tools.isActive(player, "patineta") then
		speed *= Tuning.get("Tools.Patineta.SpeedMult")
	end
	if now < (dashUntil[player] or 0) then
		speed *= Tuning.get("Player.DashSpeedMult")
	end
	if Areas.containing(root.Position, "sand") then
		speed *= Tuning.get("World.SandSpeedMult")
	end
	if now < (slowUntil[player] or 0) then
		speed *= slowFactor[player] or 1
	end
	return math.min(speed, 100)
end

function Movement.applySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or Arrest.isHeld(player) then
		return
	end
	humanoid.WalkSpeed = speedFor(player, root)
	player:SetAttribute("Speed", math.floor(humanoid.WalkSpeed * 10) / 10)
end

function Movement.slow(player: Player, factor: number, seconds: number)
	slowFactor[player] = factor
	slowUntil[player] = os.clock() + seconds
	Movement.applySpeed(player)
end

function Movement.stun(player: Player, seconds: number)
	stunUntil[player] = os.clock() + seconds
	Movement.applySpeed(player)
	task.delay(seconds + 0.05, function()
		Movement.applySpeed(player)
	end)
end

function Movement.dash(player: Player, seconds: number)
	dashUntil[player] = os.clock() + seconds
	Movement.applySpeed(player)
	task.delay(seconds + 0.05, function()
		Movement.applySpeed(player)
	end)
end

function Movement.refreshGroup(player: Player)
	updateGroup(player)
end

-- Devuelve el movimiento normal después de un arresto o una inmovilización.
function Movement.restore(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		LevelLoader.applyToHumanoid(humanoid, physics)
	end
	Movement.applySpeed(player)
end

-- Coloca al personaje en un punto. Roblox lo mueve a un SpawnLocation después de
-- emparentarlo, así que se reintenta unos frames.
function Movement.placeAt(player: Player, position: Vector3)
	task.spawn(function()
		-- Los niveles están lejos unos de otros: el cliente debe cargar el destino antes de aparecer.
		pcall(function()
			player:RequestStreamAroundAsync(position, Tuning.get("Travel.StreamTimeoutSeconds"))
		end)
		for _ = 1, 12 do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				if (root.Position - position).Magnitude > 6 then
					character:PivotTo(CFrame.new(position + Vector3.new(0, 4, 0)))
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- Mueve al personaje de golpe a un punto (viajes). A diferencia de placeAt no reintenta:
-- el personaje ya existe y nadie lo va a devolver a un SpawnLocation.
function Movement.teleport(player: Player, position: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return false
	end
	character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- Punto al que vuelve el jugador al reaparecer, si no está dentro de una Guarida.
function Movement.setHome(player: Player, position: Vector3)
	lastGuarida[player] = position
end

-- Guarida desde la que reaparece un jugador (la última que pisó o la más cercana).
function Movement.guaridaFor(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local part = Areas.nearest("guarida", root.Position)
		if part then
			return part.Position
		end
	end
	return lastGuarida[player]
end

function Movement.respawnAtGuarida(player: Player)
	local position = Movement.guaridaFor(player) or lastGuarida[player]
	if position then
		Movement.placeAt(player, position)
	end
	task.defer(Movement.applySpeed, player)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	LevelLoader.applyToHumanoid(humanoid, physics)
	updateGroup(player)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and groupOf[player] then
			descendant.CollisionGroup = groupOf[player]
		end
	end)
	Movement.applySpeed(player)
	local last = lastGuarida[player]
	if last then
		Movement.placeAt(player, last)
	end
end

function Movement.init(context: Context)
	physics = context.physics
	setupGroups()
end

function Movement.start()
	local function onPlayerAdded(player: Player)
		connections[player] = {
			player.CharacterAdded:Connect(function(character)
				onCharacterAdded(player, character)
			end),
		}
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local list = connections[player]
		if list then
			for _, connection in list do
				connection:Disconnect()
			end
		end
		connections[player] = nil
		dashUntil[player], slowUntil[player], slowFactor[player], stunUntil[player] = nil, nil, nil, nil
		lastGuarida[player], groupOf[player] = nil, nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Areas.entered:Connect(function(player, name, part)
		if name == "guarida" then
			lastGuarida[player] = part.Position
		end
	end)
	Progress.leveledUp:Connect(function(player)
		updateGroup(player)
		Movement.applySpeed(player)
	end)
	Progress.loaded:Connect(function(player)
		updateGroup(player)
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < Tuning.get("Player.SpeedRefreshSeconds") then
			return
		end
		elapsed = 0
		for _, player in Players:GetPlayers() do
			Movement.applySpeed(player)
		end
	end)
end

return Movement
