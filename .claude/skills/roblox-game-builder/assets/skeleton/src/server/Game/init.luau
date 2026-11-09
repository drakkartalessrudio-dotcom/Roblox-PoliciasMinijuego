--[[
	Game · composición del juego (esqueleto de capas). Equivale al módulo Main de UEFN.

	Es el único lugar que conoce todos los módulos. Les pasa el contenido del juego,
	conecta los puentes y los arranca, en este orden:

	  1. init de cada core, con su contenido y opciones (todavía sin jugadores);
	  2. connect de cada puente, para no perder eventos del arranque;
	  3. start de cada core: atienden PlayerAdded y a los jugadores ya presentes.

	Aquí también van las reacciones propias de este juego que mezclan módulos o el
	núcleo (telemetría, atributos para la UI) sin tocar los cores.
]]

local Content = require(script.Content)
local Quests = require(script.Parent.Modules.Quests)
local Zones = require(script.Parent.Modules.Zones)
local Zones_Quests = require(script.Parent.Bridges.Zones_Quests)

local Game = {}

function Game.start()
	Zones.init({ cooldown = 2 })
	Quests.init(Content.quests)

	Zones_Quests.connect({ questsByZone = Content.questsByZone })

	-- Reacción propia de este juego: la UI muestra la última misión completada.
	Quests.completed:Connect(function(player, questId)
		player:SetAttribute("LastQuestCompleted", questId)
	end)

	Zones.start()
	Quests.start()
end

return Game
