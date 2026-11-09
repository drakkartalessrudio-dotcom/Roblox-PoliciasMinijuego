--[[
	Quests · módulo core del esqueleto de capas.

	Lleva el progreso de las misiones de cada jugador. No sabe de dónde viene ese
	progreso (zonas, enemigos, compras): lo traen los puentes con Quests.progress.
	El catálogo lo pasa Game en init, como hacía el módulo Main en UEFN con sus
	subclases de misiones. Este esqueleto no guarda datos: en un juego que guarda, el
	progreso vive en la sección de datos que posee este módulo.

	API:
	  Quests.init(catalog)                         antes de start
	  Quests.start()                               atiende a los jugadores
	  Quests.progress(player, questId, amount)     -> boolean
	  Quests.isCompleted(player, questId)          -> boolean
	  Quests.progressed                            Signal (player, questId, progreso)
	  Quests.completed                             Signal (player, questId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

export type Quest = {
	goal: number, -- progreso necesario para completarla
}
export type Catalog = { [string]: Quest }

local Quests = {}

Quests.progressed = Signal.new() :: Signal.Signal<Player, string, number>
Quests.completed = Signal.new() :: Signal.Signal<Player, string>

local catalog: Catalog = {}
local progressByPlayer: { [Player]: { [string]: number } } = {}

function Quests.init(questCatalog: Catalog)
	catalog = questCatalog
end

function Quests.start()
	local function onPlayerAdded(player: Player)
		progressByPlayer[player] = {}
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		progressByPlayer[player] = nil
	end)
end

-- Suma progreso a una misión. Devuelve false si no existe, ya está completa o el
-- jugador todavía no está listo.
function Quests.progress(player: Player, questId: string, amount: number): boolean
	local quest = catalog[questId]
	local progress = progressByPlayer[player]
	if not quest or not progress or amount <= 0 then
		return false
	end
	local current = progress[questId] or 0
	if current >= quest.goal then
		return false
	end
	current = math.min(quest.goal, current + amount)
	progress[questId] = current
	Quests.progressed:Fire(player, questId, current)
	if current >= quest.goal then
		Quests.completed:Fire(player, questId)
	end
	return true
end

function Quests.isCompleted(player: Player, questId: string): boolean
	local quest = catalog[questId]
	local progress = progressByPlayer[player]
	return quest ~= nil and progress ~= nil and (progress[questId] or 0) >= quest.goal
end

return Quests
