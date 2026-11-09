--[[
	QuestData · fachada del core Quests sobre su sección del perfil ("quests"). Es el
	único archivo del juego que usa PlayerData.section(player, "quests"). Si el perfil
	no está listo, las lecturas dicen que no hay nada y las escrituras devuelven false.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local QuestData = {}

local function read(player: Player): DataTypes.Quests?
	return PlayerData.section(player, "quests"):get()
end

function QuestData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

function QuestData.isActive(player: Player, questId: string): boolean
	local data = read(player)
	return data ~= nil and data.active[questId] ~= nil
end

function QuestData.isCompleted(player: Player, questId: string): boolean
	local data = read(player)
	return data ~= nil and data.completed[questId] ~= nil
end

-- Progreso de cada objetivo de una misión activa, o nil si no está activa.
function QuestData.progress(player: Player, questId: string): { [string]: number }?
	local data = read(player)
	local quest = data and data.active[questId]
	return if quest then quest.objectives else nil
end

-- Empieza una misión con todos sus objetivos en 0.
function QuestData.start(player: Player, questId: string, objectives: { [string]: number }): boolean
	return PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
		local progress = {}
		for objectiveId in objectives do
			progress[objectiveId] = 0
		end
		draft.active[questId] = { startedAt = os.time(), objectives = progress }
	end)
end

-- Suma progreso a un objetivo sin pasar de goal. Devuelve el valor nuevo, o nil si no se pudo.
function QuestData.addProgress(player: Player, questId: string, objectiveId: string, amount: number, goal: number): number?
	local value: number? = nil
	local ok = PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
		local quest = draft.active[questId]
		if quest then
			local current = math.min(goal, (quest.objectives[objectiveId] or 0) + amount)
			quest.objectives[objectiveId] = current
			value = current
		end
	end)
	return if ok then value else nil
end

-- Pasa una misión de activa a completada, con la fecha.
function QuestData.complete(player: Player, questId: string): boolean
	return PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
		draft.active[questId] = nil
		draft.completed[questId] = os.time()
	end)
end

return QuestData
