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

-- Dónde quedó el jugador y su mejor tiempo en cada nivel
export type Obby = {
	current: {
		levelId: string,
		checkpoint: number,
	},
	levels: { [string]: {
		completedAt: number,
		bestTimeMs: number,
	} },
	finishedAt: number,
}

export type Document = {
	meta: Meta,
	obby: Obby,
}

return {}
