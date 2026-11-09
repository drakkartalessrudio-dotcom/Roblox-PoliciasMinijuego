--[[
	Stats · módulo core: contadores para misiones, logros y KPIs (arrestos, travesuras,
	derribos, rescates…). Guarda en la sección "stats" (StatData). Un contador nuevo es
	una clave nueva: no cambia el esquema.

	API:
	  Stats.increment(player, statId, amount?)   -> number? total nuevo
	  Stats.get(player, statId)                  -> number
	  Stats.incremented                          Signal (player, statId, amount, total)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local StatData = require(script.StatData)

local Stats = {}

Stats.incremented = Signal.new() :: Signal.Signal<Player, string, number, number>

function Stats.init() end
function Stats.start() end

function Stats.get(player: Player, statId: string): number
	return StatData.get(player, statId)
end

function Stats.increment(player: Player, statId: string, amount: number?): number?
	local delta = math.max(1, math.floor(amount or 1))
	local total = StatData.increment(player, statId, delta)
	if total then
		Stats.incremented:Fire(player, statId, delta, total)
	end
	return total
end

return Stats
