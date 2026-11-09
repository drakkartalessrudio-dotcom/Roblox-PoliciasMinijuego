--[[
	TrainingData · fachada del core Training sobre su sección del perfil ("training").
	Es el único archivo que usa PlayerData.section(player, "training").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local DAY = 86400

local TrainingData = {}

function TrainingData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

function TrainingData.get(player: Player): DataTypes.Training?
	return PlayerData.section(player, "training"):get()
end

-- Segundos pagados hoy (0 si empezó un día nuevo).
function TrainingData.usedToday(player: Player): number
	local data = TrainingData.get(player)
	if not data or os.time() >= data.dayStart + DAY then
		return 0
	end
	return data.usedSeconds
end

-- Suma segundos al día de hoy, reiniciando el contador si cambió el día UTC. Devuelve el total.
function TrainingData.addUsed(player: Player, seconds: number): number?
	local total: number? = nil
	local today = math.floor(os.time() / DAY) * DAY
	local ok = PlayerData.section(player, "training"):update(function(draft: DataTypes.Training)
		if draft.dayStart ~= today then
			draft.dayStart = today
			draft.usedSeconds = 0
		end
		draft.usedSeconds = math.min(draft.usedSeconds + seconds, DAY)
		total = draft.usedSeconds
	end)
	return if ok then total else nil
end

-- Marca el alijo como reclamado ahora. Devuelve la hora anterior (0 si es la primera vez).
function TrainingData.claimStash(player: Player): number?
	local previous: number? = nil
	local ok = PlayerData.section(player, "training"):update(function(draft: DataTypes.Training)
		previous = draft.stashClaimedAt
		draft.stashClaimedAt = os.time()
	end)
	return if ok then previous else nil
end

return TrainingData
