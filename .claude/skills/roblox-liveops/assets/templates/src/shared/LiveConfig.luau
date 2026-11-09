--[[
	LiveConfig · plantilla de roblox-liveops.

	Implementa getOverride(path) para Tuning con dos fuentes, en este orden:
	  1. Experience configs de Roblox (ConfigService): valores que el equipo cambia en
	     Creator Hub sin publicar una versión nueva. Solo el servidor puede leerlos.
	  2. Eventos programados en LiveSchema.json (ventanas en UTC).
	Si ninguna aplica, Tuning usa el valor de Config.

	El servidor valida cada valor (ruta existente en Config, mismo tipo, rango del
	esquema), calcula los overrides activos y los publica en el atributo Overrides de
	este ModuleScript como texto JSON. Como el módulo vive en ReplicatedStorage, el
	cliente recibe los mismos valores: la UI y el servidor ven lo mismo.

	El esquema (src/server/LiveSchema.json) queda en el servidor para no revelar a los
	clientes el calendario de eventos futuros. Cópialo tal cual; lo propio de cada
	juego va en el esquema.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))

local LiveConfig = {}

local changed = Instance.new("BindableEvent")
-- Se dispara cuando cambian los overrides activos (por ejemplo, para refrescar la UI).
LiveConfig.Changed = changed.Event

local overrides: { [string]: any } = {}

-- Devuelve (true, valor) si hay un override activo para la ruta de Config.
function LiveConfig.getOverride(path: string): (boolean, any)
	local value = overrides[path]
	if value == nil then
		return false, nil
	end
	return true, value
end

-- Copia de los overrides activos, para diagnóstico.
function LiveConfig.active(): { [string]: any }
	return table.clone(overrides)
end

local function decode(text: any): { [string]: any }
	if type(text) ~= "string" or text == "" then
		return {}
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	return if ok and type(data) == "table" then data else {}
end

if RunService:IsClient() then
	local function sync()
		overrides = decode(script:GetAttribute("Overrides"))
		changed:Fire()
	end
	script:GetAttributeChangedSignal("Overrides"):Connect(sync)
	sync()
	return LiveConfig
end

-- Servidor ---------------------------------------------------------------------

local ConfigService = game:GetService("ConfigService")
local ServerScriptService = game:GetService("ServerScriptService")

local Schema: any = require(ServerScriptService:WaitForChild("Server"):WaitForChild("LiveSchema"))

type KeySpec = { key: string, min: number?, max: number? }

-- Los datos del esquema varían entre juegos: se tratan como any y se validan al usarlos.
local keys: { [string]: KeySpec } = if type(Schema.keys) == "table" then Schema.keys :: any else {}
local events: { any } = if type(Schema.events) == "table" then Schema.events :: any else {}
local REFRESH = if Schema.refresh == "manual" then "manual" else "immediate"
local EVALUATE_SECONDS = 30

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[LiveConfig] {message}`)
	end
end

local function defaultValue(path: string): any
	local node: any = Config
	for _, part in string.split(path, ".") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

-- Devuelve el valor listo para usar, o nil si no es válido para esa ruta.
local function sanitize(path: string, value: any, source: string): any
	local default = defaultValue(path)
	if default == nil then
		warnOnce(`ruta:{path}`, `{source}: la ruta "{path}" no existe en Config; se ignora`)
		return nil
	end
	if type(value) ~= type(default) then
		warnOnce(`tipo:{path}:{source}`, `{source}: "{path}" debe ser {type(default)} y llegó {type(value)}; se ignora`)
		return nil
	end
	local spec = keys[path]
	if type(value) == "number" and spec then
		if spec.min and value < spec.min then
			warnOnce(`min:{path}:{value}`, `{source}: "{path}" = {value} está debajo de {spec.min}; se usa el mínimo`)
			return spec.min
		end
		if spec.max and value > spec.max then
			warnOnce(`max:{path}:{value}`, `{source}: "{path}" = {value} supera {spec.max}; se usa el máximo`)
			return spec.max
		end
	end
	return value
end

local snapshot: any = nil

local function configValue(spec: KeySpec): any
	if not snapshot then
		return nil
	end
	local ok, value = pcall(function()
		return snapshot:GetValue(spec.key)
	end)
	return if ok then value else nil
end

local function isActive(event: any, now: number): boolean
	local startTime = if type(event.start) == "string" then DateTime.fromIsoDate(event.start) else nil
	local endTime = if type(event["end"]) == "string" then DateTime.fromIsoDate(event["end"]) else nil
	if not startTime or not endTime then
		warnOnce(`evento:{event.id}`, `el evento "{event.id}" no tiene fechas ISO válidas en UTC; se ignora`)
		return false
	end
	return now >= startTime.UnixTimestamp and now < endTime.UnixTimestamp
end

local function compute(): { [string]: any }
	local result = {}
	local now = DateTime.now().UnixTimestamp
	for _, event in events do
		if type(event) == "table" and isActive(event, now) and type(event.overrides) == "table" then
			for path, value in event.overrides do
				local clean = sanitize(path, value, `evento {event.id}`)
				if clean ~= nil then
					result[path] = clean
				end
			end
		end
	end
	for path, spec in keys do
		local value = configValue(spec)
		if value ~= nil then
			local clean = sanitize(path, value, `config {spec.key}`)
			if clean ~= nil then
				result[path] = clean
			end
		end
	end
	return result
end

local published = ""

local function publish()
	local result = compute()
	local encoded = HttpService:JSONEncode(result)
	if encoded == published then
		return
	end
	published = encoded
	overrides = result
	script:SetAttribute("Overrides", encoded)
	changed:Fire()
end

-- Aplica los cambios de configs pendientes. Con refresh "manual" en el esquema, el
-- juego la llama en un momento seguro, por ejemplo entre rondas.
function LiveConfig.refresh()
	if snapshot then
		local ok, err = pcall(function()
			snapshot:Refresh()
		end)
		if not ok then
			warn(`[LiveConfig] No se pudo refrescar el snapshot: {err}`)
		end
	end
	publish()
end

local function loadSnapshot()
	local ok, result = pcall(function()
		return ConfigService:GetConfigAsync()
	end)
	if not ok then
		warn(`[LiveConfig] No se pudieron leer los configs ({result}); se usan Config y los eventos programados`)
		return
	end
	snapshot = result
	if REFRESH == "immediate" then
		snapshot.UpdateAvailable:Connect(function()
			LiveConfig.refresh()
		end)
	end
	publish()
end

publish() -- los eventos programados aplican desde el inicio, sin esperar a los configs
task.spawn(loadSnapshot)
task.spawn(function()
	while true do
		task.wait(EVALUATE_SECONDS)
		publish()
	end
end)

return LiveConfig
