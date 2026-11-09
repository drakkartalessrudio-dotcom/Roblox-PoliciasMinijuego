--[[
	Content · el contenido propio de TravesurasBrainrot que Game les pasa a los cores:
	los tipos de policía, los nombres de banda, las monedas y las ofertas de Robux.
	Cambiar el juego (un policía nuevo, un nombre, una oferta) solo toca este archivo.
]]

local CopModels = require(script.Parent.CopModels)

local Content = {}

-- Policías: id, clave en Config.Cops y aspecto. Tres de ellos (Helicóptero y Comisario) tienen reglas propias.
Content.copTypes = {
	patata = { id = "patata", configKey = "Patata", name = "Patrullero Patata", build = function()
		return CopModels.build("patata")
	end },
	capibara = { id = "capibara", configKey = "Capibara", name = "Capibara Motorizada", build = function()
		return CopModels.build("capibara")
	end },
	tiburon = { id = "tiburon", configKey = "Tiburon", name = "Tiburón Zapatilla", build = function()
		return CopModels.build("tiburon")
	end },
	cafetera = { id = "cafetera", configKey = "Cafetera", name = "Cafetera K-9", build = function()
		return CopModels.build("cafetera")
	end },
	helicoptero = { id = "helicoptero", configKey = "Helicoptero", name = "Helicóptero Banana", flying = true, build = function()
		return CopModels.build("helicoptero")
	end },
	comisario = { id = "comisario", configKey = "Comisario", name = "Comisario Cerebrote", boss = true, build = function()
		return CopModels.build("comisario")
	end },
}

-- Qué patrulla ambiental ve un jugador según el techo de estrellas de su nivel.
Content.patrolByCap = {
	[1] = { "patata" },
	[2] = { "patata", "capibara" },
	[3] = { "patata", "capibara", "tiburon" },
	[4] = { "patata", "capibara", "tiburon", "cafetera" },
	[5] = { "patata", "capibara", "tiburon", "cafetera" },
	[6] = { "patata", "capibara", "tiburon", "cafetera" },
}

-- Nombres de banda (sin texto libre del jugador) y colores de la banda (hexadecimales del tema).
Content.bandNames = {
	"Los Papas Fritos",
	"Capibara Crew",
	"Tiburones de Zapatilla",
	"Cafeteras Locas",
	"Bananas Furiosas",
	"Cerebros Podridos",
	"Los Travesuras",
	"Banda del Confeti",
}
Content.bandColors = { "#FF9F1C", "#19D3F3", "#B97CFF", "#FFD60A", "#4ADE80", "#FF6B8A" }

Content.currencies = {
	dinero = { attribute = "Dinero" },
	cerebros = { attribute = "Cerebros" },
}

-- Ofertas de Robux. Los IDs son 0 (pendientes): hasta que el usuario los cree en Creator Hub la
-- oferta no se puede comprar. No se inventan IDs.
Content.passes = {
	money2x = { passId = 0 }, -- Dinero ×2: +1,0 al bono total aditivo
	aura_vip = { passId = 0 }, -- Aura Brainrot VIP: cosmético
	stash_extended = { passId = 0 }, -- Alijo extendido: tope de 90 a 240 min
	phone = { passId = 0 }, -- Teléfono de Guarida: depositar a distancia sin estrellas
}

-- Cantidades de los paquetes de Dinero (equivalen a ≈ 30, 120 y 480 min de ingreso a nivel 20).
Content.moneyPacks = { pack_small = 8100, pack_medium = 32400, pack_large = 129600 }

return Content
