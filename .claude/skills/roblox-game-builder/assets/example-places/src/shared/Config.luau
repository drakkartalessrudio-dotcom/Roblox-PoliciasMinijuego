--[[
	Config: valores ajustables del juego. Se leen con Tuning.get("Seccion.Valor").
	Los valores iniciales salen de "Parámetros ajustables" del GDD.
]]

local Config = {
	Travel = {
		PortalCooldown = 3, -- segundos entre dos intentos de viaje del mismo jugador por el portal
	},
	Respawn = {
		Time = 1.5, -- segundos entre morir y reaparecer en la torre
	},
}

return Config
