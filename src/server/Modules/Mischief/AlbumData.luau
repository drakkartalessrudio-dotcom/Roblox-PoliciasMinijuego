--[[
	AlbumData · fachada del core Mischief sobre su sección del perfil ("album"): los
	diseños de graffiti desbloqueados. Es el único archivo que usa
	PlayerData.section(player, "album").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local AlbumData = {}

function AlbumData.has(player: Player, designId: string): boolean
	local data: DataTypes.Album? = PlayerData.section(player, "album"):get()
	return data ~= nil and data.designs[designId] ~= nil
end

function AlbumData.count(player: Player): number
	local data: DataTypes.Album? = PlayerData.section(player, "album"):get()
	local total = 0
	if data then
		for _ in data.designs do
			total += 1
		end
	end
	return total
end

-- Desbloquea un diseño. true solo si era nuevo y quedó guardado.
function AlbumData.unlock(player: Player, designId: string, maxEntries: number): boolean
	local created = false
	local ok = PlayerData.section(player, "album"):update(function(draft: DataTypes.Album)
		local total = 0
		for _ in draft.designs do
			total += 1
		end
		if draft.designs[designId] == nil and total < maxEntries then
			draft.designs[designId] = os.time()
			created = true
		end
	end)
	return ok and created
end

return AlbumData
