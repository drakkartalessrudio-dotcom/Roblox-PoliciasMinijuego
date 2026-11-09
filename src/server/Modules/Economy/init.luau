--[[
	Economy · módulo core: el Dinero y los Cerebros del jugador (guardados en la sección
	"economy" con EconomyData) y el Botín (Dinero sin depositar, solo de la sesión).

	El Botín se gana con las travesuras, tiene un tope de capacidad y se convierte en
	Dinero al depositarlo en una Guarida. Si arrestan al jugador, pierde una fracción.
	Cada movimiento de la cartera se registra con Telemetry.economy después de aplicarlo.

	No sabe por qué se gana o se gasta: lo deciden los puentes y Game.

	API:
	  Economy.init(options)                          { currencies, capFor }
	  Economy.start()                                publica los saldos al cargar cada perfil
	  Economy.add(player, moneda, cantidad, tipo)    -> boolean   (tipo: Gameplay, Shop, IAP…)
	  Economy.spend(player, moneda, cantidad, tipo)  -> boolean   (false si no alcanza)
	  Economy.balance(player, moneda)                -> number
	  Economy.set(player, moneda, cantidad)          reinicio de la Ascensión
	  Economy.addLoot(player, cantidad)              -> number    Botín que entró (respeta el tope)
	  Economy.loot(player)                           -> number
	  Economy.deposit(player)                        -> number    pasa el Botín a Dinero
	  Economy.loseLoot(player, fraccion)             -> number    Botín perdido
	  Economy.refreshCap(player)                     vuelve a calcular el tope
	  Economy.changed                                Signal (player, moneda, saldo)
	  Economy.lootChanged                            Signal (player, botín)
	  Economy.deposited                              Signal (player, cantidad)
	  Economy.lootLost                               Signal (player, cantidad)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local EconomyData = require(script.EconomyData)

export type Currency = {
	attribute: string, -- atributo del jugador que lee la UI
}
export type Options = {
	currencies: { [string]: Currency },
	capFor: (player: Player) -> number, -- capacidad de Botín de un jugador
}

local Economy = {}

Economy.changed = Signal.new() :: Signal.Signal<Player, string, number>
Economy.lootChanged = Signal.new() :: Signal.Signal<Player, number>
Economy.deposited = Signal.new() :: Signal.Signal<Player, number>
Economy.lootLost = Signal.new() :: Signal.Signal<Player, number>

local currencies: { [string]: Currency } = {}
local capFor: (Player) -> number = function()
	return 0
end
local loot: { [Player]: number } = {}

local function publish(player: Player, currencyId: string, balance: number)
	player:SetAttribute(currencies[currencyId].attribute, balance)
end

local function publishLoot(player: Player)
	player:SetAttribute("Botin", loot[player] or 0)
	Economy.lootChanged:Fire(player, loot[player] or 0)
end

local function validAmount(currencyId: string, amount: number): boolean
	assert(currencies[currencyId], `la moneda {currencyId} no está en Economy.init`)
	return amount == amount and amount > 0 and math.floor(amount) == amount
end

function Economy.init(options: Options)
	currencies = options.currencies
	capFor = options.capFor
end

function Economy.start()
	local function onPlayerAdded(player: Player)
		loot[player] = 0
		player:SetAttribute("Botin", 0)
		for _, currency in currencies do
			player:SetAttribute(currency.attribute, 0)
		end
		Economy.refreshCap(player)
		if EconomyData.waitUntilReady(player) then
			for currencyId in currencies do
				publish(player, currencyId, EconomyData.balance(player, currencyId))
			end
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		loot[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Economy.refreshCap(player: Player)
	player:SetAttribute("BotinCap", math.floor(capFor(player)))
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

function Economy.set(player: Player, currencyId: string, amount: number)
	assert(currencies[currencyId], `la moneda {currencyId} no está en Economy.init`)
	if EconomyData.set(player, currencyId, math.max(0, math.floor(amount))) then
		local balance = EconomyData.balance(player, currencyId)
		publish(player, currencyId, balance)
		Economy.changed:Fire(player, currencyId, balance)
	end
end

function Economy.loot(player: Player): number
	return loot[player] or 0
end

function Economy.addLoot(player: Player, amount: number): number
	if loot[player] == nil or amount ~= amount or amount <= 0 then
		return 0
	end
	local room = math.max(0, math.floor(capFor(player)) - loot[player])
	local added = math.min(math.floor(amount), room)
	if added > 0 then
		loot[player] += added
		publishLoot(player)
	end
	return added
end

-- Pasa todo el Botín a Dinero. Devuelve cuánto se depositó (0 si el perfil no está listo).
function Economy.deposit(player: Player): number
	local amount = loot[player] or 0
	if amount <= 0 then
		return 0
	end
	if not Economy.add(player, "dinero", amount, "Gameplay") then
		return 0
	end
	loot[player] = 0
	publishLoot(player)
	Economy.deposited:Fire(player, amount)
	return amount
end

function Economy.loseLoot(player: Player, fraction: number): number
	local current = loot[player] or 0
	if current <= 0 then
		return 0
	end
	local lost = math.floor(current * math.clamp(fraction, 0, 1))
	loot[player] = current - lost
	publishLoot(player)
	if lost > 0 then
		Economy.lootLost:Fire(player, lost)
	end
	return lost
end

return Economy
