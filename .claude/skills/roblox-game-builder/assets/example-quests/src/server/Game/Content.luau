--[[
	Contenido de Aldea de Gremios: el catálogo de misiones, qué zona avanza qué
	objetivo, qué recompensa da cada misión, las monedas y la recompensa diaria. Es lo
	que en UEFN eran las subclases del módulo Main (mandalorian_quests,
	star_war_tycoon_tracker_device). Agregar una misión o un gremio se hace aquí, sin
	tocar ningún core ni puente, y sin migrar datos: el perfil guarda las misiones
	por su id.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ServerScriptService.Server.Modules.Economy)
local Quests = require(ServerScriptService.Server.Modules.Quests)
local Rewards = require(ServerScriptService.Server.Modules.Rewards)

local quests: Quests.Catalog = {
	bienvenida = { faction = "aldea", title = "Conocé la aldea", objectives = { bosque = 1, mina = 1 } },
	lenadores_1 = { faction = "lenadores", title = "Recorré el bosque", objectives = { bosque = 3 }, requires = { "bienvenida" } },
	lenadores_2 = { faction = "lenadores", title = "Guardabosques", objectives = { bosque = 6 }, requires = { "lenadores_1" } },
	mineros_1 = { faction = "mineros", title = "Bajá a la mina", objectives = { mina = 3 }, requires = { "bienvenida" } },
	mineros_2 = { faction = "mineros", title = "Veta profunda", objectives = { mina = 6 }, requires = { "mineros_1" } },
}

local rewardByQuest: { [string]: Rewards.Reward } = {
	bienvenida = { currency = { coins = 20 } },
	lenadores_1 = { currency = { coins = 30 } },
	lenadores_2 = { currency = { coins = 60, gems = 1 } },
	mineros_1 = { currency = { coins = 30 } },
	mineros_2 = { currency = { coins = 60, gems = 1 } },
}

local currencies: { [string]: Economy.Currency } = {
	coins = { name = "Monedas", attribute = "Coins", leaderstat = true },
	gems = { name = "Gemas", attribute = "Gems" },
}

local dailyRewards: { Rewards.Reward } = {
	{ currency = { coins = 10 } },
	{ currency = { coins = 15 } },
	{ currency = { coins = 20 } },
	{ currency = { coins = 25, gems = 1 } },
}

return {
	quests = quests,
	rewardByQuest = rewardByQuest,
	objectiveByZone = { bosque = "bosque", mina = "mina" },
	currencies = currencies,
	dailyRewards = dailyRewards,
}
