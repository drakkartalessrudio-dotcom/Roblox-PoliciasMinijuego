--[[
	Place · plantilla del contrato de la fábrica (roblox-game-builder).

	Registro de los places de una experiencia con varios places
	(src/shared/Places.json). Todos los places comparten este mismo código: cada uno
	se construye con su propio proyecto de Rojo, que pone en ReplicatedStorage un
	StringValue "PlaceKey" con su clave. Así el código sabe en qué place corre, en
	Studio y publicado, y construye solo lo suyo.

	Los PlaceId los carga el usuario después de crear los places en Creator Hub;
	0 significa pendiente. Un juego de un solo place no necesita este módulo.
	Uso: references/hooks.md del builder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry: any = require(script.Parent:WaitForChild("Places"))

local Place = {}

export type Role = "start" | "match" | "area"

local function entries(): { [string]: any }
	return if type(Registry.places) == "table" then Registry.places else {}
end

-- Clave del place de inicio: la entrada de la experiencia.
function Place.start(): string
	return tostring(Registry.start)
end

-- Clave del place en el que corre este servidor o cliente.
function Place.current(): string
	local value = ReplicatedStorage:FindFirstChild("PlaceKey")
	if value and value:IsA("StringValue") and entries()[value.Value] then
		return value.Value
	end
	if game.PlaceId ~= 0 then
		for key, entry in entries() do
			if tonumber(entry.placeId) == game.PlaceId then
				return key
			end
		end
	end
	return Place.start()
end

-- Datos de un place de Places.json (por defecto, el actual).
function Place.info(key: string?): { [string]: any }
	local name = key or Place.current()
	local entry = entries()[name]
	assert(type(entry) == "table", `[Place] No existe el place "{name}" en Places.json`)
	return entry
end

-- Rol de un place: "start", "match" (partidas en servidores reservados) o "area" (zona del mundo).
function Place.role(key: string?): Role
	return Place.info(key).role
end

-- PlaceId publicado, o nil si todavía está pendiente.
function Place.id(key: string): number?
	local id = tonumber(Place.info(key).placeId)
	return if id and id > 0 then id else nil
end

-- Claves de todos los places.
function Place.all(): { string }
	local keys = {}
	for key in entries() do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Ids de los niveles de Levels.json que se construyen en un place (por defecto, el actual).
-- Un nivel sin "place" pertenece al place de inicio.
function Place.levels(levels: any, key: string?): { string }
	local target = key or Place.current()
	local result = {}
	for _, level in (if type(levels) == "table" and type(levels.levels) == "table" then levels.levels else {}) do
		local owner = if type(level.place) == "string" then level.place else Place.start()
		if owner == target then
			table.insert(result, tostring(level.id))
		end
	end
	return result
end

return Place
