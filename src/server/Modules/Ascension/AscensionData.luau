--[[
	AscensionData · fachada del core Ascension sobre su sección del perfil ("ascension").
	Es el único archivo que usa PlayerData.section(player, "ascension").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local AscensionData = {}

function AscensionData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

function AscensionData.get(player: Player): DataTypes.Ascension?
	return PlayerData.section(player, "ascension"):get()
end

function AscensionData.count(player: Player): number
	local data = AscensionData.get(player)
	return if data then data.count else 0
end

function AscensionData.perkLevel(player: Player, perkId: string): number
	local data = AscensionData.get(player)
	return if data then data.perks[perkId] or 0 else 0
end

function AscensionData.setPerk(player: Player, perkId: string, level: number): boolean
	return (PlayerData.section(player, "ascension"):update(function(draft: DataTypes.Ascension)
		draft.perks[perkId] = level
	end))
end

function AscensionData.reachedSixStar(player: Player): boolean
	local data = AscensionData.get(player)
	return data ~= nil and data.run.reachedSixStar
end

function AscensionData.markSixStar(player: Player): boolean
	return (PlayerData.section(player, "ascension"):update(function(draft: DataTypes.Ascension)
		draft.run.reachedSixStar = true
	end))
end

-- Suma una Ascensión y empieza una carrera nueva.
function AscensionData.advance(player: Player, maxCount: number): number?
	local newCount: number? = nil
	local ok = PlayerData.section(player, "ascension"):update(function(draft: DataTypes.Ascension)
		if draft.count < maxCount then
			draft.count += 1
			draft.run.startedAt = os.time()
			draft.run.reachedSixStar = false
			newCount = draft.count
		end
	end)
	return if ok then newCount else nil
end

return AscensionData
