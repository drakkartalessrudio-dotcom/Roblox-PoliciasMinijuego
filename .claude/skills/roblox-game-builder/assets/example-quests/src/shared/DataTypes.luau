--!strict
--[[
	DataTypes · generado por gen_types.py (roblox-data-architect) desde
	src/server/Data/DataSchema.json, versión 2. No lo edites a mano:
	vuelve a generarlo cuando cambie el esquema.
]]

-- Fechas, sesiones y tiempo de juego; los mantiene el servicio de datos
export type Meta = {
	firstJoinAt: number,
	lastJoinAt: number,
	sessions: number,
	playTimeSec: number,
}

-- Misiones activas con el progreso de cada objetivo y misiones completadas
export type Quests = {
	active: { [string]: {
		startedAt: number,
		objectives: { [string]: number },
	} },
	completed: { [string]: number },
}

-- Saldo de cada moneda
export type Economy = {
	wallet: { [string]: number },
}

-- Racha de la recompensa diaria
export type Rewards = {
	daily: {
		streak: number,
		lastClaimAt: number,
	},
}

export type Document = {
	meta: Meta,
	quests: Quests,
	economy: Economy,
	rewards: Rewards,
}

return {}
