--[[
	DataDebug · plantilla de roblox-data-architect. Cópiala sin cambios a src/server/Data/.

	Herramientas para probar los datos en Studio, desde la barra de comandos con el
	juego corriendo (el equivalente del dispositivo de reset de los proyectos de UEFN):

	  local DataDebug = require(game.ServerScriptService.Server.Data.DataDebug)
	  DataDebug.dump(game.Players.TuNombre)            -- imprime el perfil
	  DataDebug.reset(game.Players.TuNombre, "quests") -- una sección a sus valores por defecto
	  DataDebug.reset(game.Players.TuNombre)           -- todo el perfil
	  DataDebug.save(game.Players.TuNombre)            -- guarda ya

	Fuera de Studio no hace nada.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local PlayerData = require("./PlayerData")

local DataDebug = {}

local function inStudio(): boolean
	if not RunService:IsStudio() then
		warn("[DataDebug] solo funciona en Studio")
		return false
	end
	return true
end

function DataDebug.dump(player: Player)
	if not inStudio() then
		return
	end
	local session = PlayerData.debugSession()
	local sections = {}
	for name in session.schema.sections do
		sections[name] = session:get(player.UserId, name)
	end
	print(`[DataDebug] {player.Name} ({session:status(player.UserId)}):`, HttpService:JSONEncode(sections))
end

function DataDebug.reset(player: Player, section: string?)
	if not inStudio() then
		return
	end
	if PlayerData.debugSession():reset(player.UserId, section) then
		print(`[DataDebug] {player.Name}: {section or "todo el perfil"} vuelve a sus valores por defecto; se guarda en el próximo autosave o con DataDebug.save`)
	else
		warn(`[DataDebug] el perfil de {player.Name} no está listo`)
	end
end

function DataDebug.save(player: Player)
	if not inStudio() then
		return
	end
	print(`[DataDebug] guardado de {player.Name}:`, PlayerData.save(player))
end

return DataDebug
