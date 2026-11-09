--[[
	Obby · módulo core con las reglas del obby de ejemplo.

	- Peligros: dañan al tocarlos (atributo Damage de la pieza o Hazards.Damage).
	- Checkpoints: guardan el punto de reaparición, solo hacia adelante y dentro del
	  nivel actual del jugador.
	- Meta: completa el nivel y lleva al jugador al inicio del siguiente; la última
	  termina el obby.

	El progreso se guarda con ObbyData (la fachada de la sección "obby" del perfil):
	nivel y checkpoint actuales y el mejor tiempo de cada nivel. Al cargar el perfil,
	el jugador vuelve al último checkpoint que alcanzó. Si la carga falla, juega desde
	el nivel 1 sin guardar.

	API:
	  Obby.init(options)     niveles construidos y física, antes de start
	  Obby.start()           conecta las piezas y atiende a los jugadores
	  Obby.levelCompleted    Signal (player, levelIndex)
	  Obby.finished          Signal (player, segundos)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local LevelLoader = require(ServerScriptService.Server.LevelLoader)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local ObbyData = require(script.ObbyData)

-- Nombres estables definidos en el GDD (KPIs y funnel de onboarding).
local PROGRESSION_PATH = "Obby"
local ONBOARDING_JOINED = 1
local ONBOARDING_FIRST_CHECKPOINT = 2
local ONBOARDING_LEVEL_1_COMPLETE = 3

type PlayerState = {
	levelIndex: number,
	checkpointOrder: number,
	respawnPart: BasePart?,
	finished: boolean,
	startedAt: number,
	levelStartedAt: number,
	stage: IntValue,
	characterConnection: RBXScriptConnection?,
}

export type Options = {
	built: LevelLoader.Built, -- niveles construidos por LevelLoader.build
	physics: any, -- física de Levels.json
}

local Obby = {}

Obby.levelCompleted = Signal.new() :: Signal.Signal<Player, number>
Obby.finished = Signal.new() :: Signal.Signal<Player, number>

local built: LevelLoader.Built
local physics: any
local states: { [Player]: PlayerState } = {}
local hazardCooldowns: { [Player]: { [BasePart]: number } } = {}

-- Devuelve el jugador y su Humanoid vivo a partir de la parte que tocó algo.
local function characterFromHit(hit: BasePart): (Player?, Humanoid?)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil, nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return player, humanoid
end

local function respawnCFrame(part: BasePart): CFrame
	return LevelLoader.standCFrame(part, Tuning.get("Respawn.HeightOffset"))
end

-- Roblox coloca al personaje en un SpawnLocation después de emparentarlo a Workspace
-- (Player:LoadCharacterAsync), así que moverlo una sola vez puede quedar pisado.
-- Durante unos frames, si el personaje está lejos de su punto de reaparición, se lo
-- vuelve a mover. La distancia mínima evita pelear con un jugador que ya camina.
local PLACE_FRAMES = 15
local PLACE_DISTANCE = 8

local function placeCharacter(player: Player, character: Model)
	local function settle()
		for _ = 1, PLACE_FRAMES do
			task.wait()
			local state = states[player]
			local root = character:FindFirstChild("HumanoidRootPart")
			if not (state and state.respawnPart and root and root:IsA("BasePart") and character.Parent) then
				return
			end
			local target = respawnCFrame(state.respawnPart)
			if (root.Position - target.Position).Magnitude > PLACE_DISTANCE then
				character:PivotTo(target)
			end
		end
	end
	if character:IsDescendantOf(Workspace) then
		task.spawn(settle)
		return
	end
	local connection: RBXScriptConnection
	connection = character.AncestryChanged:Connect(function()
		if character:IsDescendantOf(Workspace) then
			connection:Disconnect()
			task.spawn(settle)
		elseif not character.Parent then
			connection:Disconnect()
		end
	end)
end

-- save = false no guarda: la entrada al nivel 1 al conectarse no debe pisar el progreso
-- guardado antes de que restore lo lea.
local function enterLevel(player: Player, state: PlayerState, index: number, save: boolean?)
	local level = built.levels[index]
	state.levelIndex = index
	state.checkpointOrder = 0
	state.respawnPart = level.start
	state.stage.Value = index
	state.levelStartedAt = os.clock()
	player:SetAttribute("Level", index)
	player:SetAttribute("Checkpoint", 0)
	if save ~= false then
		ObbyData.setCurrent(player, level.id, 0)
	end
	Telemetry.progressionStart(player, PROGRESSION_PATH, index, level.name)
end

-- Lleva al jugador al nivel y checkpoint guardados, cuando su perfil termina de cargar.
local function restore(player: Player, state: PlayerState)
	local levelId, checkpoint = ObbyData.current(player)
	local level = levelId and built.byId[levelId]
	if not level or state.finished or states[player] ~= state then
		return
	end
	enterLevel(player, state, level.index)
	for _, part in level.checkpoints do
		if part:GetAttribute("Order") == checkpoint then
			state.checkpointOrder = checkpoint
			state.respawnPart = part
			player:SetAttribute("Checkpoint", checkpoint)
			ObbyData.setCurrent(player, level.id, checkpoint)
		end
	end
	local character = player.Character
	if character and state.respawnPart then
		character:PivotTo(respawnCFrame(state.respawnPart))
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		LevelLoader.applyToHumanoid(humanoid, physics)
		humanoid.Died:Connect(function()
			local state = states[player]
			if state and not state.finished then
				Telemetry.custom(player, "death", state.levelIndex)
			end
		end)
	end
	placeCharacter(player, character)
end

local function onPlayerAdded(player: Player)
	if states[player] then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local stage = Instance.new("IntValue")
	stage.Name = "Etapa"
	stage.Value = 1
	stage.Parent = leaderstats
	leaderstats.Parent = player

	local state: PlayerState = {
		levelIndex = 1,
		checkpointOrder = 0,
		respawnPart = nil,
		finished = false,
		startedAt = os.clock(),
		levelStartedAt = os.clock(),
		stage = stage,
	}
	states[player] = state
	hazardCooldowns[player] = {}
	player:SetAttribute("LevelCount", #built.levels)
	player:SetAttribute("Finished", false)
	enterLevel(player, state, 1, false)
	Telemetry.onboarding(player, ONBOARDING_JOINED, "joined")
	task.spawn(function()
		if ObbyData.waitUntilReady(player) then
			restore(player, state)
		end
	end)

	state.characterConnection = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onHazardTouched(hazard: BasePart, hit: BasePart)
	local player, humanoid = characterFromHit(hit)
	local cooldowns = player and hazardCooldowns[player]
	if not humanoid or not cooldowns then
		return
	end
	local now = os.clock()
	if (cooldowns[hazard] or 0) > now then
		return
	end
	cooldowns[hazard] = now + Tuning.get("Hazards.TouchCooldown")
	local damage = hazard:GetAttribute("Damage")
	humanoid:TakeDamage(if type(damage) == "number" then damage else Tuning.get("Hazards.Damage"))
end

local function onCheckpointTouched(checkpoint: BasePart, levelIndex: number, hit: BasePart)
	local player = characterFromHit(hit)
	local state = player and states[player]
	if not player or not state or state.finished or state.levelIndex ~= levelIndex then
		return
	end
	local order = checkpoint:GetAttribute("Order")
	if type(order) ~= "number" or order <= state.checkpointOrder then
		return
	end
	state.checkpointOrder = order
	state.respawnPart = checkpoint
	player:SetAttribute("Checkpoint", order)
	ObbyData.setCurrent(player, built.levels[levelIndex].id, order)
	if levelIndex == 1 then
		Telemetry.onboarding(player, ONBOARDING_FIRST_CHECKPOINT, "first_checkpoint")
	end
end

local function onGoalTouched(levelIndex: number, hit: BasePart)
	local player = characterFromHit(hit)
	local state = player and states[player]
	if not player or not state or state.finished or state.levelIndex ~= levelIndex then
		return
	end
	local level = built.levels[levelIndex]
	ObbyData.completeLevel(player, level.id, math.floor((os.clock() - state.levelStartedAt) * 1000))
	Telemetry.progressionComplete(player, PROGRESSION_PATH, levelIndex, level.name)
	if levelIndex == 1 then
		Telemetry.onboarding(player, ONBOARDING_LEVEL_1_COMPLETE, "level_1_complete")
	end
	Obby.levelCompleted:Fire(player, levelIndex)
	if levelIndex < #built.levels then
		enterLevel(player, state, levelIndex + 1)
		local character = player.Character
		if character and state.respawnPart then
			character:PivotTo(respawnCFrame(state.respawnPart))
		end
	else
		state.finished = true
		player:SetAttribute("Finished", true)
		local seconds = os.clock() - state.startedAt
		ObbyData.finish(player)
		Telemetry.custom(player, "obby_finished", seconds)
		Obby.finished:Fire(player, seconds)
	end
end

function Obby.init(options: Options)
	built = options.built
	physics = options.physics
end

function Obby.start()
	for _, level in built.levels do
		for _, hazard in level.byKind.hazard or {} do
			hazard.Touched:Connect(function(hit)
				onHazardTouched(hazard, hit)
			end)
		end
		for _, checkpoint in level.checkpoints do
			checkpoint.Touched:Connect(function(hit)
				onCheckpointTouched(checkpoint, level.index, hit)
			end)
		end
		for _, goal in level.byKind.goal or {} do
			goal.Touched:Connect(function(hit)
				onGoalTouched(level.index, hit)
			end)
		end
	end

	-- Tiempo entre morir y reaparecer; el valor por defecto de Roblox es de varios segundos.
	Players.RespawnTime = Tuning.get("Respawn.Time")

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state and state.characterConnection then
			state.characterConnection:Disconnect()
		end
		states[player] = nil
		hazardCooldowns[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Obby
