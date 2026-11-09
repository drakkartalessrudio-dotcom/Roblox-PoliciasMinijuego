--[[
	Quests_Rewards · puente: Quests emite, Rewards reacciona. Al completar una misión,
	entrega la recompensa que Game le asigna. Ni Quests sabe qué recompensa da, ni
	Rewards sabe qué es una misión.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Quests = require(ServerScriptService.Server.Modules.Quests)
local Rewards = require(ServerScriptService.Server.Modules.Rewards)

export type Options = {
	rewardByQuest: { [string]: Rewards.Reward }, -- misión → recompensa
}

local Quests_Rewards = {}

function Quests_Rewards.connect(options: Options)
	Quests.completed:Connect(function(player, questId)
		local reward = options.rewardByQuest[questId]
		if reward then
			Rewards.grant(player, reward, `quest:{questId}`)
		end
	end)
end

return Quests_Rewards
