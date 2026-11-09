--[[
	EconomyData · fachada del core Economy sobre su sección del perfil ("economy"). Es
	el único archivo del juego que usa PlayerData.section(player, "economy").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local EconomyData = {}

function EconomyData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

-- Saldo de una moneda (0 si no tiene o si el perfil no está listo).
function EconomyData.balance(player: Player, currencyId: string): number
	local data: DataTypes.Economy? = PlayerData.section(player, "economy"):get()
	return if data then data.wallet[currencyId] or 0 else 0
end

-- Suma y devuelve el saldo nuevo, o nil si no se pudo (perfil no listo o pasa el máximo).
function EconomyData.add(player: Player, currencyId: string, amount: number): number?
	local balance: number? = nil
	local ok = PlayerData.section(player, "economy"):update(function(draft: DataTypes.Economy)
		local newBalance = (draft.wallet[currencyId] or 0) + amount
		draft.wallet[currencyId] = newBalance
		balance = newBalance
	end)
	return if ok then balance else nil
end

-- Resta y devuelve el saldo nuevo, o nil si no alcanza o no se pudo.
function EconomyData.spend(player: Player, currencyId: string, amount: number): number?
	local balance: number? = nil
	local ok = PlayerData.section(player, "economy"):update(function(draft: DataTypes.Economy)
		local current = draft.wallet[currencyId] or 0
		if current >= amount then
			local newBalance = current - amount
			draft.wallet[currencyId] = newBalance
			balance = newBalance
		end
	end)
	return if ok then balance else nil
end

return EconomyData
