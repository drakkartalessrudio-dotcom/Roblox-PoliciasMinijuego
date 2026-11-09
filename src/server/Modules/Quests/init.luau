--[[
	Quests · módulo core: las misiones diarias (se sortean 3 por día UTC), su racha y el
	cartel "Se Busca" semanal. Guarda en la sección "quests" (QuestData). La racha solo
	sube: si el jugador falta un día no la pierde.

	No paga recompensas: las publica y Game las entrega.

	Publica atributos del jugador:
	  QuestCount (3), Quest<i>Id, Quest<i>Progress, Quest<i>Goal, Quest<i>Claimed,
	  QuestStreak, WeeklyProgress, WeeklyGoal, WeeklyClaimed.

	API:
	  Quests.init(options)                     { dailyCount }
	  Quests.start()                           sortea y publica al cargar cada perfil
	  Quests.report(player, statId, amount)    suma a las misiones que miden esa estadística
	  Quests.claim(player, questId)            -> boolean cobra una misión diaria completada
	  Quests.claimWeekly(player)               -> boolean
	  Quests.streak(player)                    -> number
	  Quests.completed                         Signal (player, questId, weekly)
	  Quests.claimed                           Signal (player, questId, weekly, racha)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local QuestData = require(script.QuestData)

local Quests = {}

Quests.completed = Signal.new() :: Signal.Signal<Player, string, boolean>
Quests.claimed = Signal.new() :: Signal.Signal<Player, string, boolean, number>

local DAY = 86400
local WEEK = 7 * DAY

local function dayStart(): number
	return math.floor(os.time() / DAY) * DAY
end

local function weekId(): string
	return `W{math.floor(os.time() / WEEK)}`
end

local function goals(): { [string]: number }
	local map = {}
	for id, quest in Catalog.dailyById do
		map[id] = quest.goal
	end
	return map
end

local function pickQuests(): { string }
	local pool = {}
	for _, quest in Catalog.dailyQuests do
		table.insert(pool, quest.id)
	end
	local random = Random.new()
	local chosen = {}
	for _ = 1, math.min(Tuning.get("Daily.QuestCount"), #pool) do
		table.insert(chosen, table.remove(pool, random:NextInteger(1, #pool)) :: string)
	end
	table.sort(chosen)
	return chosen
end

local function dailyIds(player: Player): { string }
	local data = QuestData.get(player)
	local ids = {}
	if data then
		for questId in data.daily.active do
			table.insert(ids, questId)
		end
		table.sort(ids)
	end
	return ids
end

local function publish(player: Player)
	local data = QuestData.get(player)
	if not data then
		return
	end
	local ids = dailyIds(player)
	player:SetAttribute("QuestCount", #ids)
	for index, questId in ids do
		local quest = data.daily.active[questId]
		player:SetAttribute(`Quest{index}Id`, questId)
		player:SetAttribute(`Quest{index}Progress`, quest.progress)
		player:SetAttribute(`Quest{index}Goal`, Catalog.dailyById[questId].goal)
		player:SetAttribute(`Quest{index}Claimed`, quest.claimedAt ~= 0)
	end
	player:SetAttribute("QuestStreak", data.daily.streak)
	player:SetAttribute("WeeklyProgress", data.weekly.progress)
	player:SetAttribute("WeeklyGoal", Catalog.weeklyQuest.goal)
	player:SetAttribute("WeeklyClaimed", data.weekly.claimedAt ~= 0)
end

local function roll(player: Player)
	QuestData.rollDay(player, dayStart(), pickQuests(), weekId())
	publish(player)
end

function Quests.init() end

function Quests.start()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("QuestCount", 0)
		if QuestData.waitUntilReady(player) then
			roll(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Quests.streak(player: Player): number
	local data = QuestData.get(player)
	return if data then data.daily.streak else 0
end

function Quests.report(player: Player, statId: string, amount: number)
	local data = QuestData.get(player)
	if not data then
		return
	end
	if data.daily.dayStart ~= dayStart() or data.weekly.weekId ~= weekId() then
		roll(player)
	end
	local matching = {}
	for _, questId in dailyIds(player) do
		if Catalog.dailyById[questId].stat == statId then
			table.insert(matching, questId)
		end
	end
	local weeklyGoal = if Catalog.weeklyQuest.stat == statId then Catalog.weeklyQuest.goal else nil
	if #matching == 0 and not weeklyGoal then
		return
	end
	local completed, weeklyDone = QuestData.addProgress(player, matching, amount, goals(), weeklyGoal)
	publish(player)
	for _, questId in completed do
		Quests.completed:Fire(player, questId, false)
	end
	if weeklyDone then
		Quests.completed:Fire(player, Catalog.weeklyQuest.id, true)
	end
end

function Quests.claim(player: Player, questId: string): boolean
	local quest = Catalog.dailyById[questId]
	if not quest then
		return false
	end
	local ok = QuestData.claimDaily(player, questId, quest.goal, dayStart())
	if not ok then
		return false
	end
	publish(player)
	Quests.claimed:Fire(player, questId, false, Quests.streak(player))
	return true
end

function Quests.claimWeekly(player: Player): boolean
	if not QuestData.claimWeekly(player, Catalog.weeklyQuest.goal) then
		return false
	end
	publish(player)
	Quests.claimed:Fire(player, Catalog.weeklyQuest.id, true, Quests.streak(player))
	return true
end

return Quests
