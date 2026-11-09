--[[
	Game · composición del obby de ejemplo.

	Recibe el mundo que construyó Bootstrap, configura el core Obby y lo arranca.
	El obby tiene un solo core, así que no hay puentes: si se agregara, por ejemplo,
	un core de recompensas, el puente Obby_Rewards escucharía Obby.levelCompleted y
	Game le pasaría qué recompensa da cada nivel.
]]

local LevelLoader = require(script.Parent.LevelLoader)
local Obby = require(script.Parent.Modules.Obby)

export type Context = {
	built: LevelLoader.Built,
	physics: any,
}

local Game = {}

function Game.start(context: Context)
	Obby.init({ built = context.built, physics = context.physics })
	Obby.start()
end

return Game
