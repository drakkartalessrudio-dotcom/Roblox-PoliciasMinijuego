--[[
	Rewards_Economy · puente: Rewards emite, Economy reacciona. Convierte la parte de
	monedas de cada recompensa en saldo. La recompensa diaria se registra en la
	telemetría como TimedReward y el resto como Gameplay.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ServerScriptService.Server.Modules.Economy)
local Rewards = require(ServerScriptService.Server.Modules.Rewards)

local Rewards_Economy = {}

function Rewards_Economy.connect()
	Rewards.granted:Connect(function(player, reward, source)
		local kind = if source == "daily" then "TimedReward" else "Gameplay"
		for currencyId, amount in reward.currency or {} do
			Economy.add(player, currencyId, amount, kind)
		end
	end)
end

return Rewards_Economy
