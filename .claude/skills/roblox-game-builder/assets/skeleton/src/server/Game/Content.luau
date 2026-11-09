--[[
	Contenido de este juego: lo que en UEFN eran las subclases del módulo Main
	(el catálogo de misiones, qué nodo o zona avanza cada misión). Cambiarlo no toca
	ningún core ni ningún puente.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Quests = require(ServerScriptService.Server.Modules.Quests)

local quests: Quests.Catalog = {
	visit_plaza = { goal = 1 },
	explore_ruins = { goal = 3 },
}

return {
	quests = quests,
	questsByZone = {
		plaza = { "visit_plaza" },
		ruins = { "explore_ruins" },
	},
}
