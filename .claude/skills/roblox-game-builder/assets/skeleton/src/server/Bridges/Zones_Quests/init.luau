--[[
	Zones_Quests · puente del esqueleto de capas: Zones emite, Quests reacciona.

	Equivale a ModuleRoomSystem_TrackerQuest de UEFN: escucha a Zones y le avisa a
	Quests. Ninguno de los dos módulos sabe que el otro existe. Qué zona cuenta
	para qué misión es contenido del juego, así que lo pasa Game en connect.

	Un puente requiere solo sus dos módulos y el núcleo.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Quests = require(ServerScriptService.Server.Modules.Quests)
local Zones = require(ServerScriptService.Server.Modules.Zones)

export type Options = {
	questsByZone: { [string]: { string } }, -- zona → misiones que avanza
}

local Zones_Quests = {}

function Zones_Quests.connect(options: Options)
	Zones.entered:Connect(function(player, zoneId)
		local questIds = options.questsByZone[zoneId]
		if not questIds then
			return
		end
		for _, questId in questIds do
			Quests.progress(player, questId, 1)
		end
	end)
end

return Zones_Quests
