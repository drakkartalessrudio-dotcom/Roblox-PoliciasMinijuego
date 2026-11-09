--[[
	Game · composición de Aldea de Gremios. Equivale a Module_Main de UEFN: el único
	lugar que conoce todos los cores. Les pasa el contenido, conecta los puentes y los
	arranca, en este orden:

	  1. init de cada core, con su contenido (todavía sin jugadores);
	  2. connect de cada puente, para no perder eventos del arranque (la recompensa
	     diaria se entrega apenas carga el perfil);
	  3. start de cada core.

	También tiene lo propio de este juego que mezcla cores: los pasos del onboarding.

	La cadena de una misión: Zones.entered → Zones_Quests → Quests.reportObjective →
	Quests.completed → Quests_Rewards → Rewards.granted → Rewards_Economy → Economy.add.
]]

local Players = game:GetService("Players")

local Content = require(script.Content)
local LevelLoader = require(script.Parent.LevelLoader)
local Telemetry = require(script.Parent.Telemetry)
local Economy = require(script.Parent.Modules.Economy)
local Quests = require(script.Parent.Modules.Quests)
local Rewards = require(script.Parent.Modules.Rewards)
local Zones = require(script.Parent.Modules.Zones)
local Quests_Rewards = require(script.Parent.Bridges.Quests_Rewards)
local Rewards_Economy = require(script.Parent.Bridges.Rewards_Economy)
local Zones_Quests = require(script.Parent.Bridges.Zones_Quests)

-- Pasos del funnel de onboarding del GDD.
local ONBOARDING_JOINED = 1
local ONBOARDING_FIRST_ZONE = 2
local ONBOARDING_FIRST_QUEST = 3

export type Context = {
	built: LevelLoader.Built,
}

local Game = {}

function Game.start(context: Context)
	Zones.init({ built = context.built })
	Quests.init({ catalog = Content.quests })
	Economy.init({ currencies = Content.currencies })
	Rewards.init({ daily = Content.dailyRewards })

	Zones_Quests.connect({ objectiveByZone = Content.objectiveByZone })
	Quests_Rewards.connect({ rewardByQuest = Content.rewardByQuest })
	Rewards_Economy.connect()

	-- Onboarding: propio de este juego, mezcla eventos de varios cores.
	local function onPlayerAdded(player: Player)
		Telemetry.onboarding(player, ONBOARDING_JOINED, "joined")
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Zones.entered:Connect(function(player, zoneId)
		if Content.objectiveByZone[zoneId] then
			Telemetry.onboarding(player, ONBOARDING_FIRST_ZONE, "first_zone")
		end
	end)
	Quests.completed:Connect(function(player, questId)
		if questId == "bienvenida" then
			Telemetry.onboarding(player, ONBOARDING_FIRST_QUEST, "first_quest_completed")
		end
	end)

	Zones.start()
	Quests.start()
	Economy.start()
	Rewards.start()
end

return Game
