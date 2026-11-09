--[[
	RewardData · fachada del core Rewards sobre su sección del perfil ("rewards"). Es
	el único archivo del juego que usa PlayerData.section(player, "rewards").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local RewardData = {}

function RewardData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

-- Racha y fecha de la última recompensa diaria, o nil si el perfil no está listo.
function RewardData.daily(player: Player): (number?, number)
	local data: DataTypes.Rewards? = PlayerData.section(player, "rewards"):get()
	if not data then
		return nil, 0
	end
	return data.daily.streak, data.daily.lastClaimAt
end

function RewardData.setDaily(player: Player, streak: number, claimedAt: number): boolean
	return PlayerData.section(player, "rewards"):update(function(draft: DataTypes.Rewards)
		draft.daily.streak = streak
		draft.daily.lastClaimAt = claimedAt
	end)
end

return RewardData
