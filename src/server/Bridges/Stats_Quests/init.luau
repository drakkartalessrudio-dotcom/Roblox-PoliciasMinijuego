--[[
	Stats_Quests · puente: Stats emite, Quests reacciona. Cada contador que sube se informa
	a las misiones diarias y al cartel semanal que lo miden.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Quests = require(ServerScriptService.Server.Modules.Quests)
local Stats = require(ServerScriptService.Server.Modules.Stats)

local Stats_Quests = {}

function Stats_Quests.connect()
	Stats.incremented:Connect(function(player, statId, amount)
		Quests.report(player, statId, amount)
	end)
end

return Stats_Quests
