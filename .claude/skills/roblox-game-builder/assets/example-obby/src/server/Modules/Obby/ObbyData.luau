--[[
	ObbyData · fachada del core Obby sobre su sección del perfil ("obby"). Es el único
	archivo del juego que usa PlayerData.section(player, "obby"); el resto de Obby
	llama a estas funciones. Si el perfil no está listo, las lecturas devuelven nil y
	las escrituras devuelven false: el jugador sigue jugando, sin guardar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

local ObbyData = {}

-- Espera a que cargue el perfil. true si quedó listo.
function ObbyData.waitUntilReady(player: Player): boolean
	return PlayerData.waitUntilReady(player)
end

-- Dónde quedó el jugador: id del nivel y checkpoint, o nil si no hay progreso guardado.
function ObbyData.current(player: Player): (string?, number)
	local data: DataTypes.Obby? = PlayerData.section(player, "obby"):get()
	if not data or data.current.levelId == "" then
		return nil, 0
	end
	return data.current.levelId, data.current.checkpoint
end

function ObbyData.setCurrent(player: Player, levelId: string, checkpoint: number): boolean
	return PlayerData.section(player, "obby"):update(function(draft: DataTypes.Obby)
		draft.current.levelId = levelId
		draft.current.checkpoint = checkpoint
	end)
end

-- Registra un nivel completado. Devuelve true si es el mejor tiempo del jugador en ese nivel.
function ObbyData.completeLevel(player: Player, levelId: string, milliseconds: number): boolean
	local best = false
	PlayerData.section(player, "obby"):update(function(draft: DataTypes.Obby)
		local record = draft.levels[levelId]
		if not record then
			record = { completedAt = 0, bestTimeMs = 0 }
			draft.levels[levelId] = record
		end
		record.completedAt = os.time()
		if record.bestTimeMs == 0 or milliseconds < record.bestTimeMs then
			record.bestTimeMs = milliseconds
			best = true
		end
	end)
	return best
end

-- Mejor tiempo en un nivel, en milisegundos (0 si nunca lo completó).
function ObbyData.bestTime(player: Player, levelId: string): number
	local data: DataTypes.Obby? = PlayerData.section(player, "obby"):get()
	local record = data and data.levels[levelId]
	return if record then record.bestTimeMs else 0
end

-- Marca el obby como terminado la primera vez.
function ObbyData.finish(player: Player)
	PlayerData.section(player, "obby"):update(function(draft: DataTypes.Obby)
		if draft.finishedAt == 0 then
			draft.finishedAt = os.time()
		end
	end)
end

return ObbyData
