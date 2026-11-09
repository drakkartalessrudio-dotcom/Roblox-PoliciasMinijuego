--[[
	CosmeticData · fachada del core Cosmetics sobre su sección del perfil ("cosmetics").
	Es el único archivo que usa PlayerData.section(player, "cosmetics").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local CosmeticData = {}

function CosmeticData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

function CosmeticData.get(player: Player): DataTypes.Cosmetics?
	return PlayerData.section(player, "cosmetics"):get()
end

function CosmeticData.owns(player: Player, cosmeticId: string): boolean
	local data = CosmeticData.get(player)
	return data ~= nil and data.owned[cosmeticId] ~= nil
end

function CosmeticData.grant(player: Player, cosmeticId: string, source: string): boolean
	local created = false
	local ok = PlayerData.section(player, "cosmetics"):update(function(draft: DataTypes.Cosmetics)
		if draft.owned[cosmeticId] == nil then
			draft.owned[cosmeticId] = { grantedAt = os.time(), source = source }
			created = true
		end
	end)
	return ok and created
end

function CosmeticData.equip(player: Player, slot: string, cosmeticId: string?): boolean
	return (PlayerData.section(player, "cosmetics"):update(function(draft: DataTypes.Cosmetics)
		if cosmeticId then
			draft.equipped[slot] = cosmeticId
		else
			draft.equipped[slot] = nil
		end
	end))
end

return CosmeticData
