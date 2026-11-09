--[[
	Format · utilidades de texto de la interfaz (números con separador de miles, tiempos y
	mensajes de error del servidor). No es una pantalla.
]]

local Format = {}

function Format.number(value: number): string
	local text = tostring(math.floor(value + 0.5))
	local result = text:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (result:gsub("^%.", ""))
end

function Format.money(value: number): string
	return "$" .. Format.number(value)
end

function Format.minutes(seconds: number): string
	return `{math.floor(seconds / 60)} min`
end

function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Texto para cada código de error que manda el servidor en notify { kind = "error" }.
local ERRORS: { [string]: string } = {
	away = "Solo se puede en una Guarida o en el lobby",
	wanted = "Estás buscado: pierde a los policías primero",
	funds = "No te alcanza el dinero",
	locked = "Todavía no lo tienes",
	level = "Te falta nivel",
	max = "Ya está al máximo",
	owned = "Ya lo tienes",
	pending = "Disponible pronto",
	data = "Tu progreso no se puede guardar ahora",
	empty = "No hay nada para cobrar",
	cooldown = "Todavía se está recargando",
	busy = "Ya estás en otra travesura",
	far = "Estás muy lejos",
	party = "Faltan compañeros de banda cerca",
	arrested = "No puedes mientras estás arrestado",
	dead = "No puedes ahora",
	full = "La banda está llena",
	closed = "Esa banda no está abierta",
	already = "Ya estás en una banda",
	expired = "La invitación venció",
	target_busy = "Ese jugador ya tiene banda",
	not_leader = "Solo el jefe de la banda puede hacerlo",
	no_band = "Primero crea una banda",
	clean = "No tienes estrellas",
	fast = "Muy rápido: inténtalo de nuevo",
	late = "Se acabó el tiempo",
	unavailable = "No está disponible",
	plot_have = "Ya tienes una parcela: suéltala para reclamar otra",
	plot_taken = "Esa parcela ya tiene dueño",
	here = "Ya estás ahí",
	unknown = "Ese destino no existe",
	studio = "Los viajes entre places no funcionan en Studio",
	failed = "No se pudo viajar, inténtalo de nuevo",
}

function Format.error(code: string?): string
	return ERRORS[code or ""] or "No se pudo"
end

return Format
