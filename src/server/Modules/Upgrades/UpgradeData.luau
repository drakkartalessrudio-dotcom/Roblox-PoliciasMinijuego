--[[
	UpgradeData · fachada del core Upgrades sobre su sección del perfil ("upgrades").
	Es el único archivo que usa PlayerData.section(player, "upgrades").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local UpgradeData = {}

function UpgradeData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

function UpgradeData.levels(player: Player): { [string]: number }
	local data: DataTypes.Upgrades? = PlayerData.section(player, "upgrades"):get()
	return if data then data.levels else {}
end

function UpgradeData.tools(player: Player): { [string]: number }
	local data: DataTypes.Upgrades? = PlayerData.section(player, "upgrades"):get()
	return if data then data.tools else {}
end

function UpgradeData.levelOf(player: Player, upgradeId: string): number
	return UpgradeData.levels(player)[upgradeId] or 0
end

function UpgradeData.hasTool(player: Player, toolId: string): boolean
	return UpgradeData.tools(player)[toolId] ~= nil
end

function UpgradeData.setLevel(player: Player, upgradeId: string, level: number): boolean
	return (PlayerData.section(player, "upgrades"):update(function(draft: DataTypes.Upgrades)
		draft.levels[upgradeId] = level
	end))
end

function UpgradeData.grantTool(player: Player, toolId: string): boolean
	return (PlayerData.section(player, "upgrades"):update(function(draft: DataTypes.Upgrades)
		draft.tools[toolId] = os.time()
	end))
end

-- Reinicio de la Ascensión: borra mejoras y herramientas.
function UpgradeData.clear(player: Player): boolean
	return (PlayerData.section(player, "upgrades"):update(function(draft: DataTypes.Upgrades)
		draft.levels = {}
		draft.tools = {}
	end))
end

return UpgradeData
