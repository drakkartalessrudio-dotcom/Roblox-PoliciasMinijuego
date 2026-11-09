--[[
	Upgrades · módulo core: las mejoras de ocho líneas (Zapatillas, Sigilo, Bolsillos,
	Manos, Fortachón, Cinta, Batería, Gimnasio) y las herramientas desbloqueadas. Guarda
	en la sección "upgrades" (UpgradeData) y publica los niveles en atributos del jugador:
	  Up_<id> (número) y Tool_<id> (booleano).

	No conoce la economía ni el nivel del jugador: Game le pasa una función para cobrar
	y otra para consultar el nivel.

	API:
	  Upgrades.init(options)                  { spend(player, amount, sku) -> boolean, levelOf(player) -> number }
	  Upgrades.start()
	  Upgrades.levelOf(player, upgradeId)     -> number
	  Upgrades.hasTool(player, toolId)        -> boolean
	  Upgrades.buy(player, upgradeId)         -> (boolean, string?) motivo si no se pudo
	  Upgrades.buyTool(player, toolId)        -> (boolean, string?)
	  Upgrades.clear(player)                  reinicia mejoras y herramientas (Ascensión)
	  Upgrades.upgraded                       Signal (player, upgradeId, nivel)
	  Upgrades.toolGranted                    Signal (player, toolId)
	  Upgrades.changed                        Signal (player) cualquier cambio
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local UpgradeData = require(script.UpgradeData)

export type Options = {
	spend: (player: Player, amount: number, sku: string) -> boolean,
	levelOf: (player: Player) -> number,
}

local Upgrades = {}

Upgrades.upgraded = Signal.new() :: Signal.Signal<Player, string, number>
Upgrades.toolGranted = Signal.new() :: Signal.Signal<Player, string>
Upgrades.changed = Signal.new() :: Signal.Signal<Player>

local spend: (Player, number, string) -> boolean = function()
	return false
end
local playerLevel: (Player) -> number = function()
	return 1
end

local function publish(player: Player)
	local levels = UpgradeData.levels(player)
	for _, def in Catalog.upgrades do
		player:SetAttribute(`Up_{def.id}`, levels[def.id] or 0)
	end
	local tools = UpgradeData.tools(player)
	for _, def in Catalog.tools do
		player:SetAttribute(`Tool_{def.id}`, tools[def.id] ~= nil)
	end
end

function Upgrades.init(options: Options)
	spend = options.spend
	playerLevel = options.levelOf
end

function Upgrades.start()
	local function onPlayerAdded(player: Player)
		for _, def in Catalog.upgrades do
			player:SetAttribute(`Up_{def.id}`, 0)
		end
		for _, def in Catalog.tools do
			player:SetAttribute(`Tool_{def.id}`, false)
		end
		if UpgradeData.waitUntilReady(player) then
			publish(player)
			Upgrades.changed:Fire(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Upgrades.levelOf(player: Player, upgradeId: string): number
	return UpgradeData.levelOf(player, upgradeId)
end

function Upgrades.hasTool(player: Player, toolId: string): boolean
	return UpgradeData.hasTool(player, toolId)
end

function Upgrades.buy(player: Player, upgradeId: string): (boolean, string?)
	local def = Catalog.upgradeById[upgradeId]
	if not def then
		return false, "unknown"
	end
	local current = UpgradeData.levelOf(player, upgradeId)
	if current >= Catalog.upgradeMaxLevel(upgradeId) then
		return false, "max"
	end
	if (def.group == "Sala") and playerLevel(player) < Tuning.get("Afk.UnlockLevel") then
		return false, "locked"
	end
	local cost = Catalog.upgradeCost(upgradeId, current + 1)
	if not spend(player, cost, `upgrade_{upgradeId}`) then
		return false, "funds"
	end
	if not UpgradeData.setLevel(player, upgradeId, current + 1) then
		return false, "data"
	end
	publish(player)
	Upgrades.upgraded:Fire(player, upgradeId, current + 1)
	Upgrades.changed:Fire(player)
	return true, nil
end

function Upgrades.buyTool(player: Player, toolId: string): (boolean, string?)
	local def = Catalog.toolById[toolId]
	if not def then
		return false, "unknown"
	end
	if UpgradeData.hasTool(player, toolId) then
		return false, "owned"
	end
	if playerLevel(player) < Tuning.get(`Tools.{def.configKey}.Level`) then
		return false, "locked"
	end
	if not spend(player, Tuning.get(`Tools.{def.configKey}.Cost`), `tool_{toolId}`) then
		return false, "funds"
	end
	if not UpgradeData.grantTool(player, toolId) then
		return false, "data"
	end
	publish(player)
	Upgrades.toolGranted:Fire(player, toolId)
	Upgrades.changed:Fire(player)
	return true, nil
end

function Upgrades.clear(player: Player)
	if UpgradeData.clear(player) then
		publish(player)
		Upgrades.changed:Fire(player)
	end
end

return Upgrades
