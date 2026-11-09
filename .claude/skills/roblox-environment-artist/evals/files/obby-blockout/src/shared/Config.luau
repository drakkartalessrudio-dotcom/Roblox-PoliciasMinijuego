--[[
	Config: valores ajustables del obby. Léelos con Tuning.get("Seccion.Valor").

	La física del personaje (velocidad, salto y gravedad) no está acá: vive en
	Levels.json porque los niveles se validan con esos valores. Para cambiarla,
	edita Levels.json y vuelve a correr validate_levels.py.
]]

local Config = {
	Hazards = {
		Damage = 100, -- daño al tocar un peligro sin daño propio; 100 = muerte instantánea
		TouchCooldown = 0.5, -- segundos entre daños del mismo peligro al mismo jugador
	},
	Respawn = {
		Time = 1.5, -- segundos entre morir y reaparecer
		HeightOffset = 3, -- studs sobre el checkpoint donde reaparece el personaje
	},
	Hud = {
		HintText = "Salta de plataforma en plataforma y evita la lava",
		HintSeconds = 8, -- cuánto dura el mensaje inicial
	},
}

return Config
