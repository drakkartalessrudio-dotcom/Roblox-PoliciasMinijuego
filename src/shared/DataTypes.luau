--!strict
--[[
	DataTypes · generado por gen_types.py (roblox-data-architect) desde
	src/server/Data/DataSchema.json, versión 1. No lo edites a mano:
	vuelve a generarlo cuando cambie el esquema.
]]

-- Fechas, sesiones y tiempo de juego; los mantiene el servicio de datos
export type Meta = {
	firstJoinAt: number,
	lastJoinAt: number,
	sessions: number,
	playTimeSec: number,
}

-- Nivel (1 a 50), XP hacia el siguiente nivel y banderas con fecha de hitos y onboarding
export type Progress = {
	level: number,
	xp: number, -- XP acumulada dentro del nivel actual
	flags: { [string]: number }, -- joined, first_mischief, first_star, first_escape, first_deposit, first_upgrade, first_level_up, tutorial_done y otros hitos
}

-- Saldo de cada moneda permanente: dinero (se reinicia con la Ascensión) y cerebros. El Botín sin depositar no se guarda
export type Economy = {
	wallet: { [string]: number },
}

-- Nivel de cada mejora (Zapatillas, Sigilo, Bolsillos, Manos, Fortachón, Cinta, Batería, Gimnasio) y herramientas desbloqueadas
export type Upgrades = {
	levels: { [string]: number },
	tools: { [string]: number }, -- Herramientas compradas, con la fecha de compra
}

-- Ascensiones hechas (0 a 10), perks de Cerebros y datos de la carrera actual
export type Ascension = {
	count: number,
	perks: { [string]: number },
	run: {
		startedAt: number,
		reachedSixStar: boolean, -- Llegó a 6 estrellas en esta carrera (+1 Cerebro al ascender)
	},
}

-- Diseños de graffiti desbloqueados (30 normales y los exclusivos de banda)
export type Album = {
	designs: { [string]: number },
}

-- Misiones diarias con su racha, y el cartel Se Busca semanal. Reinician con la hora del servidor (UTC)
export type Quests = {
	daily: {
		dayStart: number, -- Inicio (UTC) del día al que pertenecen las misiones activas
		streak: number,
		lastCompletedDay: number,
		active: { [string]: {
			progress: number,
			claimedAt: number,
		} },
	},
	weekly: {
		weekId: string,
		progress: number,
		claimedAt: number,
	},
}

-- Sala de Entrenamiento (tiempo pagado hoy para el tope diario) y el alijo de la Guarida (última vez reclamado)
export type Training = {
	dayStart: number, -- Inicio (UTC) del día al que pertenece usedSeconds
	usedSeconds: number,
	stashClaimedAt: number,
}

-- Skins, auras, cintas y etiquetas desbloqueadas y equipadas
export type Cosmetics = {
	owned: { [string]: {
		grantedAt: number,
		source: "shop" | "level" | "quest" | "gamepass" | "event",
	} },
	equipped: { [string]: string },
}

-- Contadores para misiones, logros y KPIs (arrestos, travesuras, derribos, travesuras de banda, rescates)
export type Stats = {
	counters: { [string]: number },
}

-- Recibos de Developer Products ya entregados (paquetes de Dinero, Soborno, Fianza)
export type Purchases = {
	processed: { [string]: number },
}

export type Document = {
	meta: Meta,
	progress: Progress,
	economy: Economy,
	upgrades: Upgrades,
	ascension: Ascension,
	album: Album,
	quests: Quests,
	training: Training,
	cosmetics: Cosmetics,
	stats: Stats,
	purchases: Purchases,
}

return {}
