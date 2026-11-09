--[[
	QuestData · fachada del core Quests sobre su sección del perfil ("quests").
	Es el único archivo que usa PlayerData.section(player, "quests").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local QuestData = {}

function QuestData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

function QuestData.get(player: Player): DataTypes.Quests?
	return PlayerData.section(player, "quests"):get()
end

-- Si empezó un día nuevo (UTC), sortea las misiones del día. La racha no baja nunca:
-- solo sube cuando se cobran las tres del día.
function QuestData.rollDay(player: Player, dayStart: number, questIds: { string }, weekId: string): boolean
	return (PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
		if draft.daily.dayStart ~= dayStart then
			draft.daily.dayStart = dayStart
			draft.daily.active = {}
			for _, questId in questIds do
				draft.daily.active[questId] = { progress = 0, claimedAt = 0 }
			end
		end
		if draft.weekly.weekId ~= weekId then
			draft.weekly.weekId = weekId
			draft.weekly.progress = 0
			draft.weekly.claimedAt = 0
		end
	end))
end

function QuestData.addProgress(player: Player, dailyIds: { string }, amount: number, goals: { [string]: number }, weeklyGoal: number?): ({ string }, boolean)
	local completed: { string } = {}
	local weeklyDone = false
	PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
		for _, questId in dailyIds do
			local quest = draft.daily.active[questId]
			if quest and quest.claimedAt == 0 and quest.progress < goals[questId] then
				quest.progress = math.min(goals[questId], quest.progress + amount)
				if quest.progress >= goals[questId] then
					table.insert(completed, questId)
				end
			end
		end
		if weeklyGoal and draft.weekly.claimedAt == 0 and draft.weekly.progress < weeklyGoal then
			draft.weekly.progress = math.min(weeklyGoal, draft.weekly.progress + amount)
			weeklyDone = draft.weekly.progress >= weeklyGoal
		end
	end)
	return completed, weeklyDone
end

-- Cobra una misión diaria. Devuelve (ok, racha nueva si se completaron las tres).
function QuestData.claimDaily(player: Player, questId: string, goal: number, today: number): (boolean, number?)
	local ok, streak = false, nil :: number?
	PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
		local quest = draft.daily.active[questId]
		if not quest or quest.claimedAt ~= 0 or quest.progress < goal then
			return
		end
		quest.claimedAt = os.time()
		ok = true
		local allClaimed = true
		for _, other in draft.daily.active do
			if other.claimedAt == 0 then
				allClaimed = false
			end
		end
		if allClaimed and draft.daily.lastCompletedDay ~= today then
			draft.daily.lastCompletedDay = today
			draft.daily.streak = math.min(draft.daily.streak + 1, 3650)
			streak = draft.daily.streak
		end
	end)
	return ok, streak
end

function QuestData.claimWeekly(player: Player, goal: number): boolean
	local ok = false
	PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
		if draft.weekly.claimedAt == 0 and draft.weekly.progress >= goal then
			draft.weekly.claimedAt = os.time()
			ok = true
		end
	end)
	return ok
end

return QuestData
