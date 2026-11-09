--[[
	Quests · módulo core: misiones con objetivos que se cumplen sumando progreso.

	El catálogo (facción, título, objetivos y requisitos) lo pasa Game en init, como el
	módulo Main de UEFN pasaba sus subclases de misiones. El progreso se guarda en la
	sección "quests" del perfil, con QuestData. Este core no sabe de dónde viene el
	progreso (zonas, enemigos…) ni qué recompensa da cada misión: eso lo conectan los
	puentes con reportObjective y con el evento completed.

	Una misión empieza sola cuando su perfil cargó y el jugador completó las misiones
	de requires. El atributo QuestSummary resume las misiones activas para la UI.

	API:
	  Quests.init(options)                               catálogo, antes de start
	  Quests.start()                                     atiende a los jugadores
	  Quests.reportObjective(player, objectiveId, amount)  suma a cada misión activa con ese objetivo
	  Quests.isCompleted(player, questId)                -> boolean
	  Quests.started / Quests.completed                  Signal (player, questId)
	  Quests.progressed                                  Signal (player, questId, objectiveId, valor)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local QuestData = require(script.QuestData)

export type Quest = {
	faction: string, -- facción o grupo de la misión; es el camino de progresión de la telemetría
	title: string, -- lo que ve el jugador
	objectives: { [string]: number }, -- objetivo → cantidad necesaria
	requires: { string }?, -- misiones que tiene que haber completado antes
}
export type Catalog = { [string]: Quest }
export type Options = {
	catalog: Catalog,
}

local Quests = {}

Quests.started = Signal.new() :: Signal.Signal<Player, string>
Quests.progressed = Signal.new() :: Signal.Signal<Player, string, string, number>
Quests.completed = Signal.new() :: Signal.Signal<Player, string>

local catalog: Catalog = {}
local order: { string } = {} -- ids ordenados: el resultado no depende del orden de una tabla
local stepInFaction: { [string]: number } = {} -- número de la misión dentro de su facción, para la telemetría

local function summary(player: Player): string
	local parts = {}
	for _, questId in order do
		local progress = QuestData.progress(player, questId)
		if progress then
			local done, total = 0, 0
			for objectiveId, goal in catalog[questId].objectives do
				done += progress[objectiveId] or 0
				total += goal
			end
			table.insert(parts, `{catalog[questId].title} {done}/{total}`)
		end
	end
	return if #parts > 0 then table.concat(parts, " · ") else "Sin misiones activas"
end

local function publish(player: Player)
	player:SetAttribute("QuestSummary", summary(player))
end

-- Empieza las misiones que el jugador ya puede tomar.
local function refresh(player: Player)
	for _, questId in order do
		local quest = catalog[questId]
		if not QuestData.isActive(player, questId) and not QuestData.isCompleted(player, questId) then
			local ready = true
			for _, required in quest.requires or {} do
				if not QuestData.isCompleted(player, required) then
					ready = false
				end
			end
			if ready and QuestData.start(player, questId, quest.objectives) then
				Telemetry.progressionStart(player, quest.faction, stepInFaction[questId], quest.title)
				Quests.started:Fire(player, questId)
			end
		end
	end
	publish(player)
end

local function objectivesDone(player: Player, questId: string): boolean
	local progress = QuestData.progress(player, questId)
	if not progress then
		return false
	end
	for objectiveId, goal in catalog[questId].objectives do
		if (progress[objectiveId] or 0) < goal then
			return false
		end
	end
	return true
end

function Quests.init(options: Options)
	catalog = options.catalog
	table.clear(order)
	for questId in catalog do
		table.insert(order, questId)
	end
	table.sort(order)
	local counts: { [string]: number } = {}
	for _, questId in order do
		local faction = catalog[questId].faction
		counts[faction] = (counts[faction] or 0) + 1
		stepInFaction[questId] = counts[faction]
	end
end

function Quests.start()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("QuestSummary", "Cargando misiones…")
		-- No escribas antes de leer: las misiones empiezan cuando el perfil cargó.
		if QuestData.waitUntilReady(player) then
			refresh(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Quests.reportObjective(player: Player, objectiveId: string, amount: number)
	local anyCompleted = false
	for _, questId in order do
		local quest = catalog[questId]
		local goal = quest.objectives[objectiveId]
		if goal and QuestData.isActive(player, questId) then
			local value = QuestData.addProgress(player, questId, objectiveId, amount, goal)
			if value then
				Quests.progressed:Fire(player, questId, objectiveId, value)
				if objectivesDone(player, questId) and QuestData.complete(player, questId) then
					Telemetry.progressionComplete(player, quest.faction, stepInFaction[questId], quest.title)
					Quests.completed:Fire(player, questId)
					anyCompleted = true
				end
			end
		end
	end
	if anyCompleted then
		refresh(player)
	else
		publish(player)
	end
end

function Quests.isCompleted(player: Player, questId: string): boolean
	return QuestData.isCompleted(player, questId)
end

return Quests
