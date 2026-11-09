--[[
	Tower · módulo core con las reglas del place torre. Los peligros matan, cada meta
	lleva al nivel siguiente y la última devuelve al jugador a la plaza con Travel. Si
	el viaje no ocurre (Studio o PlaceId pendiente), el jugador vuelve al comienzo de
	la torre.

	API:
	  Tower.init(options)   niveles construidos del place y física, antes de start
	  Tower.start()         conecta las piezas y atiende a los jugadores
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Tuning = require(ReplicatedStorage.Shared.Tuning)
local LevelLoader = require(ServerScriptService.Server.LevelLoader)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local Travel = require(ServerScriptService.Server.Travel)

export type Options = {
	built: LevelLoader.Built, -- niveles de la torre
	physics: any, -- física de Levels.json
}

local Tower = {}

local PROGRESSION_PATH = "tower"
local SETTLE_FRAMES = 15 -- Roblox ubica al personaje en un SpawnLocation después de crearlo

type State = { levelIndex: number }

local built: LevelLoader.Built
local physics: any
local states: { [Player]: State } = {}

local function playerFromHit(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function startCFrame(index: number): CFrame
	return LevelLoader.standCFrame(built.levels[index].start :: BasePart)
end

local function enterLevel(player: Player, state: State, index: number)
	state.levelIndex = index
	player:SetAttribute("Level", index)
	Telemetry.progressionStart(player, PROGRESSION_PATH, index, built.levels[index].name)
end

-- Lleva al personaje al comienzo de su nivel, repitiendo unos frames por el spawn de Roblox.
local function placeCharacter(player: Player, character: Model)
	for _ = 1, SETTLE_FRAMES do
		local state = states[player]
		if not state or character.Parent == nil then
			return
		end
		local target = startCFrame(state.levelIndex)
		if (character:GetPivot().Position - target.Position).Magnitude > 4 then
			character:PivotTo(target)
		end
		RunService.Heartbeat:Wait()
	end
end

local function onHazardTouched(hit: BasePart)
	local player = playerFromHit(hit)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

local function onGoalTouched(index: number, hit: BasePart)
	local player = playerFromHit(hit)
	local state = player and states[player]
	if not player or not state or state.levelIndex ~= index then
		return
	end
	Telemetry.progressionComplete(player, PROGRESSION_PATH, index, built.levels[index].name)
	local nextIndex = if index < #built.levels then index + 1 else 1
	if index == #built.levels then
		Telemetry.custom(player, "tower_finished")
		if Travel.toStart({ player }) then
			return
		end
	end
	enterLevel(player, state, nextIndex)
	local character = player.Character
	if character then
		character:PivotTo(startCFrame(nextIndex))
	end
end

function Tower.init(options: Options)
	built = options.built
	physics = options.physics
end

function Tower.start()
	for _, level in built.levels do
		for _, hazard in level.byKind.hazard or {} do
			hazard.Touched:Connect(onHazardTouched)
		end
		for _, goal in level.byKind.goal or {} do
			goal.Touched:Connect(function(hit)
				onGoalTouched(level.index, hit)
			end)
		end
	end
	Players.RespawnTime = Tuning.get("Respawn.Time")

	local function onPlayerAdded(player: Player)
		local state: State = { levelIndex = 1 }
		states[player] = state
		enterLevel(player, state, 1)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			LevelLoader.applyToHumanoid(humanoid, physics)
			placeCharacter(player, character)
		end)
		if player.Character then
			task.spawn(placeCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return Tower
