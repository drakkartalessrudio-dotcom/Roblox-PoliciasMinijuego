--[[
	Economy · módulo core: las monedas del jugador. Cada moneda tiene un saldo en la
	sección "economy" del perfil (con EconomyData), un atributo para la UI y, si se
	pide, una columna en leaderstats. Cada movimiento se registra con
	Telemetry.economy después de aplicarlo.

	No sabe por qué se gana o se gasta: lo deciden los puentes y Game.

	API:
	  Economy.init(options)                          monedas, antes de start
	  Economy.start()                                publica los saldos al cargar cada perfil
	  Economy.add(player, moneda, cantidad, tipo)    -> boolean (tipo: Gameplay, TimedReward, Shop…)
	  Economy.spend(player, moneda, cantidad, tipo)  -> boolean (false si no alcanza)
	  Economy.balance(player, moneda)                -> number
	  Economy.changed                                Signal (player, moneda, saldo)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local EconomyData = require(script.EconomyData)

export type Currency = {
	name: string, -- nombre visible (columna de leaderstats)
	attribute: string, -- atributo del jugador que lee la UI
	leaderstat: boolean?, -- true para mostrarla en la lista de jugadores
}
export type Options = {
	currencies: { [string]: Currency },
}

local Economy = {}

Economy.changed = Signal.new() :: Signal.Signal<Player, string, number>

local currencies: { [string]: Currency } = {}

local function publish(player: Player, currencyId: string, balance: number)
	local currency = currencies[currencyId]
	player:SetAttribute(currency.attribute, balance)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(currency.name)
	if value and value:IsA("IntValue") then
		value.Value = balance
	end
end

local function validAmount(currencyId: string, amount: number): boolean
	assert(currencies[currencyId], `la moneda {currencyId} no está en Economy.init`)
	return amount > 0 and math.floor(amount) == amount
end

function Economy.init(options: Options)
	currencies = options.currencies
end

function Economy.start()
	local function onPlayerAdded(player: Player)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		for _, currency in currencies do
			if currency.leaderstat then
				local value = Instance.new("IntValue")
				value.Name = currency.name
				value.Parent = leaderstats
			end
		end
		leaderstats.Parent = player
		if EconomyData.waitUntilReady(player) then
			for currencyId in currencies do
				publish(player, currencyId, EconomyData.balance(player, currencyId))
			end
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Economy.balance(player: Player, currencyId: string): number
	return EconomyData.balance(player, currencyId)
end

function Economy.add(player: Player, currencyId: string, amount: number, kind: string): boolean
	if not validAmount(currencyId, amount) then
		return false
	end
	local balance = EconomyData.add(player, currencyId, amount)
	if not balance then
		return false
	end
	Telemetry.economy(player, "source", currencyId, amount, balance, kind)
	publish(player, currencyId, balance)
	Economy.changed:Fire(player, currencyId, balance)
	return true
end

function Economy.spend(player: Player, currencyId: string, amount: number, kind: string): boolean
	if not validAmount(currencyId, amount) then
		return false
	end
	local balance = EconomyData.spend(player, currencyId, amount)
	if not balance then
		return false
	end
	Telemetry.economy(player, "sink", currencyId, amount, balance, kind)
	publish(player, currencyId, balance)
	Economy.changed:Fire(player, currencyId, balance)
	return true
end

return Economy
