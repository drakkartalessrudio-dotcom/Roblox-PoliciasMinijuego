--[[
	Zones_Quests · puente: Zones emite, Quests reacciona. Entrar a una zona suma 1 al
	objetivo que Game asigna a esa zona en todas las misiones activas que lo tengan.
	Es el equivalente de ModuleRoomSystem_TrackerQuest de UEFN.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Quests = require(ServerScriptService.Server.Modules.Quests)
local Zones = require(ServerScriptService.Server.Modules.Zones)

export type Options = {
	objectiveByZone: { [string]: string }, -- zona → objetivo de misión
}

local Zones_Quests = {}

function Zones_Quests.connect(options: Options)
	Zones.entered:Connect(function(player, zoneId)
		local objectiveId = options.objectiveByZone[zoneId]
		if objectiveId then
			Quests.reportObjective(player, objectiveId, 1)
		end
	end)
end

return Zones_Quests
