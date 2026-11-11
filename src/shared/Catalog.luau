--[[
	Catalog · contenido y fórmulas del juego que comparten servidor y cliente (núcleo).
	Solo datos y funciones puras; los precios y valores salen de Config con Tuning.
	El servidor decide con esto; la UI lo usa para mostrar nombres, costos y descripciones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Destinations = require(ReplicatedStorage.Shared.Destinations)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

local Catalog = {}

export type UpgradeDef = { id: string, name: string, configKey: string, description: string, group: string }

-- Mejoras en el orden en que las muestra la tienda.
Catalog.upgrades = {
	{ id = "zapatillas", name = "Zapatillas", configKey = "Zapatillas", group = "Travesuras", description = "+1,5 de velocidad por nivel" },
	{ id = "sigilo", name = "Sigilo", configKey = "Sigilo", group = "Travesuras", description = "−4 % de visión y ruido por nivel" },
	{ id = "bolsillos", name = "Bolsillos", configKey = "Bolsillos", group = "Travesuras", description = "Más capacidad de Botín y menos pérdida al arresto" },
	{ id = "manos", name = "Manos rápidas", configKey = "Manos", group = "Travesuras", description = "−4 % de duración de los minijuegos por nivel" },
	{ id = "fortachon", name = "Fortachón", configKey = "Fortachon", group = "Travesuras", description = "+8 % de poder de embestida por nivel" },
	{ id = "cinta", name = "Cinta", configKey = "Cinta", group = "Sala", description = "+2 % de ganancia AFK por nivel" },
	{ id = "bateria", name = "Batería", configKey = "Bateria", group = "Sala", description = "Más tiempo entre check-ins" },
	{ id = "gimnasio", name = "Gimnasio", configKey = "Gimnasio", group = "Sala", description = "+8 min de tope diario por nivel" },
} :: { UpgradeDef }

Catalog.upgradeById = {} :: { [string]: UpgradeDef }
for _, def in Catalog.upgrades do
	Catalog.upgradeById[def.id] = def
end

function Catalog.upgradeMaxLevel(id: string): number
	local def = Catalog.upgradeById[id]
	if def and Tuning.has(`Upgrades.{def.configKey}.MaxLevel`) then
		return Tuning.get(`Upgrades.{def.configKey}.MaxLevel`)
	end
	return Tuning.get("Upgrades.MaxLevel")
end

-- Costo de pasar a `nextLevel` (1 a MaxLevel): base × factor^(n−1).
function Catalog.upgradeCost(id: string, nextLevel: number): number
	local def = Catalog.upgradeById[id]
	local base = Tuning.get(`Upgrades.{def.configKey}.BaseCost`)
	local factor = if Tuning.has(`Upgrades.{def.configKey}.CostFactor`) then Tuning.get(`Upgrades.{def.configKey}.CostFactor`) else Tuning.get("Upgrades.CostFactor")
	return math.floor(base * factor ^ (nextLevel - 1) + 0.5)
end

export type ToolDef = { id: string, name: string, configKey: string, hotkey: Enum.KeyCode, description: string }

Catalog.tools = {
	{ id = "tarta", name = "Tarta", configKey = "Tarta", hotkey = Enum.KeyCode.One, description = "Aturde a un policía 2 s" },
	{ id = "banana", name = "Banana", configKey = "Banana", hotkey = Enum.KeyCode.Two, description = "Trampa: resbala a un policía 3 s" },
	{ id = "humo", name = "Bomba de confeti", configKey = "Humo", hotkey = Enum.KeyCode.Three, description = "Los policías pierden la vista 5 s" },
	{ id = "patineta", name = "Patineta turbo", configKey = "Patineta", hotkey = Enum.KeyCode.Four, description = "+35 % de velocidad 8 s" },
	{ id = "senuelo", name = "Señuelo", configKey = "Senuelo", hotkey = Enum.KeyCode.Five, description = "Un muñeco que los policías persiguen 6 s" },
} :: { ToolDef }

Catalog.toolById = {} :: { [string]: ToolDef }
for _, def in Catalog.tools do
	Catalog.toolById[def.id] = def
end

export type PerkDef = { id: string, name: string, configKey: string, description: string }

Catalog.perks = {
	{ id = "pies_de_rayo", name = "Pies de rayo", configKey = "PiesDeRayo", description = "+1 de velocidad por nivel" },
	{ id = "sigilo_innato", name = "Sigilo innato", configKey = "SigiloInnato", description = "−3 % de detección por nivel" },
	{ id = "capital_inicial", name = "Capital inicial", configKey = "CapitalInicial", description = "+$300 × nivel al empezar cada carrera" },
	{ id = "sangre_fria", name = "Sangre fría", configKey = "SangreFria", description = "+8 % de bajada del calor por nivel" },
} :: { PerkDef }

Catalog.perkById = {} :: { [string]: PerkDef }
for _, def in Catalog.perks do
	Catalog.perkById[def.id] = def
end

export type MischiefGame = {
	type: string, -- sequence | hold | mash | timing | memory | timbrazo
	count: number?, -- puntos de la secuencia, golpes del ritmo, largo de la memoria
	taps: number?,
	seconds: number?,
}
export type MischiefDef = {
	id: string, -- clave en Config.Mischief o Config.Coop
	zone: string, -- ZoneName de Levels.json
	name: string,
	game: MischiefGame,
	coop: boolean?,
	tag: string?, -- estadística que sube (por ejemplo murals_painted)
}

Catalog.mischiefs = {
	{ id = "Graffiti", zone = "mischief_graffiti", name = "Graffiti", game = { type = "sequence", count = 6 }, tag = "murals_painted" },
	{ id = "Timbrazo", zone = "mischief_timbrazo", name = "Timbrazo y a correr", game = { type = "timbrazo" } },
	{ id = "Hidrante", zone = "mischief_hidrante", name = "Hidrante", game = { type = "hold", seconds = 8 } },
	{ id = "Carrito", zone = "mischief_carrito", name = "Birlar del carrito", game = { type = "timing", count = 3 } },
	{ id = "Castillo", zone = "mischief_castillo", name = "Castillo de arena", game = { type = "mash", taps = 14 } },
	{ id = "Sombrillas", zone = "mischief_sombrillas", name = "Sombrillas voladoras", game = { type = "sequence", count = 4 } },
	{ id = "Bocinas", zone = "mischief_bocinas", name = "Concierto de bocinas", game = { type = "timing", count = 4 } },
	{ id = "Semaforos", zone = "mischief_semaforos", name = "Semáforos locos", game = { type = "memory", count = 4 } },
	{ id = "Cajero", zone = "mischief_cajero", name = "Cajero glitcheado", game = { type = "mash", taps = 18 } },
	{ id = "Estatua", zone = "mischief_estatua", name = "Estatua con bigote", game = { type = "timing", count = 5 } },
	{ id = "Contenedor", zone = "mischief_contenedor", name = "Contenedor misterioso", game = { type = "memory", count = 3 } },
	{ id = "MuralGigante", zone = "coop_mural", name = "Mural Gigante", game = { type = "sequence", count = 8 }, coop = true, tag = "murals_painted" },
	{ id = "Sinfonia", zone = "coop_sinfonia", name = "Sinfonía de bocinas", game = { type = "timing", count = 6 }, coop = true },
	{ id = "CajaFuerte", zone = "coop_cajafuerte", name = "Caja Fuerte del Queso", game = { type = "hold", seconds = 12 }, coop = true },
} :: { MischiefDef }

Catalog.mischiefByZone = {} :: { [string]: MischiefDef }
Catalog.mischiefById = {} :: { [string]: MischiefDef }
for _, def in Catalog.mischiefs do
	Catalog.mischiefByZone[def.zone] = def
	Catalog.mischiefById[def.id] = def
end
-- El primer muro del tutorial (cerca del spawn de barrio-papa) es un graffiti normal: sin esto no tenía prompt.
Catalog.mischiefByZone.tutorial_graffiti = Catalog.mischiefById.Graffiti

-- Valores de una travesura (individual en Config.Mischief, de banda en Config.Coop).
function Catalog.mischiefConfig(def: MischiefDef): { [string]: number }
	return Tuning.get(`{if def.coop then "Coop" else "Mischief"}.{def.id}`)
end

-- XP para pasar del nivel n al n+1: 30 × n^1,4 redondeado a 5.
function Catalog.xpToNext(level: number): number
	return math.max(5, math.floor(Tuning.get("Progress.XpBase") * level ^ Tuning.get("Progress.XpExponent") / 5 + 0.5) * 5)
end

-- Techo de estrellas para un nivel de jugador.
function Catalog.starCap(level: number): number
	local cap = 1
	for _, entry in Tuning.get("Heat.StarCapByLevel") do
		if level >= entry[1] then
			cap = entry[2]
		end
	end
	return cap
end

-- Bono de Ascensión (aditivo) tras `count` Ascensiones: +50 % hasta la 6ª, +25 % después.
function Catalog.ascensionBonus(count: number): number
	local early = math.min(count, Tuning.get("Ascension.EarlyCount"))
	local late = math.max(0, count - Tuning.get("Ascension.EarlyCount"))
	return early * Tuning.get("Ascension.BonusEarly") + late * Tuning.get("Ascension.BonusLate")
end

-- Cuota de Ascensión que se paga al ascender por vez número count+1.
function Catalog.ascensionFee(count: number): number
	return math.floor(Tuning.get("Ascension.FeeBase") * Tuning.get("Ascension.FeeGrowth") ^ count + 0.5)
end

-- XP media por minuto en el modelo de diseño (100 + 14 × nivel).
function Catalog.xpPerMinute(level: number): number
	return 100 + 14 * level
end

-- Ingreso medio por minuto en el modelo de diseño (para recompensas medidas en minutos).
function Catalog.incomePerMinute(level: number): number
	return Tuning.get("Economy.IncomeBase") + Tuning.get("Economy.IncomePerLevel") * level
end

-- Misiones diarias (el servidor sortea Daily.QuestCount) y el cartel semanal.
Catalog.dailyQuests = {
	{ id = "pinta_muros", text = "Pinta 3 muros", stat = "murals_painted", goal = 3 },
	{ id = "escapa_3", text = "Escapa con 3 estrellas o más", stat = "escapes_3star", goal = 1 },
	{ id = "derriba_5", text = "Derriba 5 policías", stat = "cop_knockdowns", goal = 5 },
	{ id = "travesuras_8", text = "Haz 8 travesuras", stat = "mischief_total", goal = 8 },
	{ id = "deposita_3", text = "Deposita tu Botín 3 veces", stat = "deposits", goal = 3 },
	{ id = "banda_2", text = "Hagan 2 travesuras de banda", stat = "band_mischiefs", goal = 2 },
}
Catalog.dailyById = {} :: { [string]: { id: string, text: string, stat: string, goal: number } }
for _, quest in Catalog.dailyQuests do
	Catalog.dailyById[quest.id] = quest
end
Catalog.weeklyQuest = { id = "se_busca", text = "Se Busca: alcanza 5 estrellas 3 veces", stat = "stars5_reached", goal = 3 }

-- Cosméticos: slot, precio en Dinero (0 = no se compra con Dinero) y de dónde salen.
Catalog.cosmetics = {
	{ id = "skin_gorra", name = "Gorra torcida", slot = "skin", cost = 500, source = "shop" },
	{ id = "skin_capa", name = "Capa de travieso", slot = "skin", cost = 3000, source = "shop" },
	{ id = "aura_confeti", name = "Aura de confeti", slot = "aura", cost = 1500, source = "shop" },
	{ id = "aura_vip", name = "Aura Brainrot VIP", slot = "aura", cost = 0, source = "gamepass" },
	{ id = "estela_arcoiris", name = "Estela arcoíris", slot = "trail", cost = 5000, source = "shop" },
	{ id = "cinta_dorada", name = "Cinta dorada", slot = "cinta", cost = 2000, source = "shop" },
	{ id = "cinta_neon", name = "Cinta neón", slot = "cinta", cost = 5000, source = "shop" },
}
for index = 1, 10 do
	table.insert(Catalog.cosmetics, { id = `badge_asc_{index}`, name = `Distintivo de Ascensión {index}`, slot = "badge", cost = 0, source = "level" })
end
Catalog.cosmeticById = {} :: { [string]: { id: string, name: string, slot: string, cost: number, source: string } }
for _, cosmetic in Catalog.cosmetics do
	Catalog.cosmeticById[cosmetic.id] = cosmetic
end

-- Vista de los destinos por id de nivel (la usa el HUD para el nombre del lugar). Los datos
-- viven en Destinations: el nivel de acceso es el minLevel de cada destino.
Catalog.districts = {} :: { [string]: { name: string, level: number, lighting: string } }
for _, destination in Destinations.list do
	Catalog.districts[destination.levelId] = { name = destination.name, level = destination.minLevel, lighting = destination.lighting }
end

export type AchievementDef = { id: string, name: string, description: string, metric: string, goal: number }

-- Logros. No se guardan: se calculan de contadores que ya se guardan (Stats, nivel más alto,
-- Ascensiones, álbum). `metric` es "stat:<contador>" o una de: level, ascensions, album.
-- El nivel cuenta el más alto alcanzado, así que la Ascensión no los quita.
Catalog.achievements = {
	{ id = "first_prank", name = "Primera travesura", description = "Completa una travesura", metric = "stat:mischief_total", goal = 1 },
	{ id = "prankster", name = "Travieso", description = "Completa 25 travesuras", metric = "stat:mischief_total", goal = 25 },
	{ id = "chaos_master", name = "Maestro del caos", description = "Completa 250 travesuras", metric = "stat:mischief_total", goal = 250 },
	{ id = "street_artist", name = "Artista callejero", description = "Pinta 10 murales", metric = "stat:murals_painted", goal = 10 },
	{ id = "collector", name = "Coleccionista", description = "Desbloquea 15 diseños del álbum", metric = "album", goal = 15 },
	{ id = "slippery", name = "Escurridizo", description = "Escapa de la policía 5 veces", metric = "stat:escapes", goal = 5 },
	{ id = "elite_runner", name = "Fugitivo de élite", description = "Escapa 3 veces con 3 estrellas o más", metric = "stat:escapes_3star", goal = 3 },
	{ id = "most_wanted", name = "El más buscado", description = "Llega a 5 estrellas", metric = "stat:stars5_reached", goal = 1 },
	{ id = "regular", name = "Cliente frecuente", description = "Que te arresten 10 veces", metric = "stat:arrests", goal = 10 },
	{ id = "cop_bowler", name = "Derribapolicías", description = "Derriba 25 policías", metric = "stat:cop_knockdowns", goal = 25 },
	{ id = "saver", name = "Ahorrador", description = "Deposita el Botín 20 veces", metric = "stat:deposits", goal = 20 },
	{ id = "accomplice", name = "Compinche", description = "Haz 5 travesuras de banda", metric = "stat:band_mischiefs", goal = 5 },
	{ id = "band_hero", name = "Héroe de la banda", description = "Rescata a 3 compañeros arrestados", metric = "stat:band_rescues", goal = 3 },
	{ id = "boss_hunter", name = "Cazador de jefes", description = "Derrota al Comisario Cerebrote", metric = "stat:comisario_defeated", goal = 1 },
	{ id = "level_10", name = "Calentando", description = "Llega al nivel 10", metric = "level", goal = 10 },
	{ id = "level_25", name = "Ya corres", description = "Llega al nivel 25", metric = "level", goal = 25 },
	{ id = "level_50", name = "Leyenda del barrio", description = "Llega al nivel 50", metric = "level", goal = 50 },
	{ id = "reborn", name = "Renacido", description = "Haz tu primera Ascensión", metric = "ascensions", goal = 1 },
	{ id = "ascended_5", name = "Cerebro supremo", description = "Haz 5 Ascensiones", metric = "ascensions", goal = 5 },
} :: { AchievementDef }

Catalog.achievementById = {} :: { [string]: AchievementDef }
for _, achievement in Catalog.achievements do
	Catalog.achievementById[achievement.id] = achievement
end

-- Pasos del funnel de onboarding (nombres estables del GDD).
Catalog.onboarding = {
	{ step = 1, name = "joined" },
	{ step = 2, name = "first_mischief" },
	{ step = 3, name = "first_star" },
	{ step = 4, name = "first_escape" },
	{ step = 5, name = "first_deposit" },
	{ step = 6, name = "first_upgrade" },
	{ step = 7, name = "first_level_up" },
}

return Catalog
