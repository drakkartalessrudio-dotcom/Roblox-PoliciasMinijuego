--[[
	ProgressData · fachada del core Progress sobre su sección del perfil ("progress").
	Es el único archivo que usa PlayerData.section(player, "progress").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local ProgressData = {}

function ProgressData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

function ProgressData.level(player: Player): number
	local data: DataTypes.Progress? = PlayerData.section(player, "progress"):get()
	return if data then data.level else 1
end

function ProgressData.xp(player: Player): number
	local data: DataTypes.Progress? = PlayerData.section(player, "progress"):get()
	return if data then data.xp else 0
end

-- Sube XP y niveles en una sola escritura. Devuelve (nivel nuevo, niveles ganados) o nil si no se pudo.
function ProgressData.addXp(player: Player, amount: number, maxLevel: number, xpToNext: (number) -> number): (number?, number)
	local newLevel, gained = nil, 0
	local ok = PlayerData.section(player, "progress"):update(function(draft: DataTypes.Progress)
		local level, xp = draft.level, draft.xp + amount
		while level < maxLevel and xp >= xpToNext(level) do
			xp -= xpToNext(level)
			level += 1
			gained += 1
		end
		if level >= maxLevel then
			xp = 0
		end
		draft.level, draft.xp = level, xp
		newLevel = level
	end)
	return if ok then newLevel else nil, gained
end

function ProgressData.reset(player: Player): boolean
	return (PlayerData.section(player, "progress"):update(function(draft: DataTypes.Progress)
		draft.level, draft.xp = 1, 0
	end))
end

function ProgressData.hasFlag(player: Player, flagId: string): boolean
	local data: DataTypes.Progress? = PlayerData.section(player, "progress"):get()
	return data ~= nil and data.flags[flagId] ~= nil
end

-- Pone la bandera con la hora del servidor. true solo si no existía y quedó guardada.
function ProgressData.setFlag(player: Player, flagId: string): boolean
	local created = false
	local ok = PlayerData.section(player, "progress"):update(function(draft: DataTypes.Progress)
		if draft.flags[flagId] == nil then
			draft.flags[flagId] = os.time()
			created = true
		end
	end)
	return ok and created
end

return ProgressData
