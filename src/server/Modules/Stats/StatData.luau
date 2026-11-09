--[[
	StatData · fachada del core Stats sobre su sección del perfil ("stats").
	Es el único archivo que usa PlayerData.section(player, "stats").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local StatData = {}

function StatData.get(player: Player, statId: string): number
	local data: DataTypes.Stats? = PlayerData.section(player, "stats"):get()
	return if data then data.counters[statId] or 0 else 0
end

-- Suma y devuelve el total nuevo (nil si no se pudo guardar).
function StatData.increment(player: Player, statId: string, amount: number): number?
	local total: number? = nil
	local ok = PlayerData.section(player, "stats"):update(function(draft: DataTypes.Stats)
		local value = math.min((draft.counters[statId] or 0) + amount, 999999999)
		draft.counters[statId] = value
		total = value
	end)
	return if ok then total else nil
end

return StatData
