--[[
	Config: valores ajustables de Aldea de Gremios, con los nombres de "Parámetros
	ajustables" del GDD. Se leen con Tuning.get("Seccion.Valor").
]]

local Config = {
	Zones = {
		Cooldown = 10, -- segundos antes de que la misma zona vuelva a contar para un jugador
	},
	Rewards = {
		StreakWindowHours = 48, -- horas desde la última recompensa diaria para que la racha siga
	},
}

return Config
