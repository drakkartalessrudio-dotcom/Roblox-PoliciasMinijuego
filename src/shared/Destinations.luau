--[[
	Destinations · a dónde se puede viajar en TravesurasBrainrot (núcleo, datos puros).

	La Guarida (lobby) y los seis distritos son destinos. Cada uno es un nivel de
	Levels.json construido lejos de los demás (ver `origin` de cada nivel) para que el
	streaming nunca los muestre juntos: viajar es un teletransporte, no una caminata.

	El viaje lo hace un solo método del servidor, `Transit.to(jugador, destino)`
	(Game/Transit.luau). Que un destino esté en este mismo place o en otro es un dato:

	  levelId   nivel de Levels.json donde se llega
	  placeId   PlaceId de otro place de la experiencia, o nil si es este mismo place.
	            Con placeId, Transit.to usa TeleportService en lugar de mover al personaje;
	            nada más del juego cambia. Nunca se inventa un PlaceId: lo carga el usuario.
	  arrival   id de la pieza (spawn) donde aparece el jugador; sin él, uno de los spawn del nivel

	La lista está en el orden en que los muestran el mapa y el tablero del lobby.
]]

export type Destination = {
	id: string,
	name: string,
	kind: "hub" | "district",
	levelId: string,
	minLevel: number,
	lighting: string,
	color: Color3, -- color del portal y de su cartel (de la paleta de Theme.json)
	placeId: number?,
	arrival: string?,
}

local Destinations = {}

Destinations.HOME = "lobby" -- La Guarida: donde aparecen todos al entrar y a donde se vuelve
Destinations.START = "barrio-papa" -- primer distrito, el del tutorial

Destinations.list = {
	{ id = "lobby", name = "La Guarida", kind = "hub", levelId = "lobby", minLevel = 1, lighting = "default", color = Color3.fromHex("#19D3F3") },
	{ id = "barrio-papa", name = "Barrio Papa", kind = "district", levelId = "barrio-papa", minLevel = 1, lighting = "default", color = Color3.fromHex("#FFD60A") },
	{ id = "colegio", name = "Colegio Brainrot", kind = "district", levelId = "colegio", minLevel = 6, lighting = "default", color = Color3.fromHex("#4ADE80") },
	{ id = "playa-podrida", name = "Playa Podrida", kind = "district", levelId = "playa-podrida", minLevel = 14, lighting = "playa", color = Color3.fromHex("#7CC8FF") },
	{ id = "centro-neon", name = "Centro Neón", kind = "district", levelId = "centro-neon", minLevel = 20, lighting = "neon", color = Color3.fromHex("#B97CFF") },
	{ id = "distrito-queso", name = "Distrito Queso", kind = "district", levelId = "distrito-queso", minLevel = 26, lighting = "queso", color = Color3.fromHex("#FF9F1C") },
	{ id = "puerto-podrido", name = "Puerto Podrido", kind = "district", levelId = "puerto-podrido", minLevel = 40, lighting = "puerto", color = Color3.fromHex("#FF6B8A") },
} :: { Destination }

Destinations.byId = {} :: { [string]: Destination }
Destinations.byLevel = {} :: { [string]: Destination }
for _, destination in Destinations.list do
	Destinations.byId[destination.id] = destination
	Destinations.byLevel[destination.levelId] = destination
end

-- Destinos que se desbloquean exactamente con este nivel (para avisar "Nuevo: Colegio…").
function Destinations.unlockedAt(level: number): { Destination }
	local list = {}
	for _, destination in Destinations.list do
		if destination.kind == "district" and destination.minLevel == level and level > 1 then
			table.insert(list, destination)
		end
	end
	return list
end

return Destinations
