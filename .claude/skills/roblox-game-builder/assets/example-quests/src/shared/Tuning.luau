--[[
	Tuning · plantilla del contrato de la fábrica (roblox-game-builder).

	Punto único de lectura de los valores ajustables de Config. El código del juego
	llama a Tuning.get("Seccion.Valor") en el momento de usar el valor:

	  1. Si existe el módulo LiveConfig (roblox-liveops) y tiene un override activo
	     para esa ruta, devuelve el override.
	  2. Si no, devuelve el valor de Config.

	Una ruta que no existe en Config es un error de programación y falla en el acto,
	para detectarlo en la primera prueba. No copies valores ajustables en variables
	al iniciar: LiveOps puede cambiarlos durante la sesión.
]]

local Config = require(script.Parent:WaitForChild("Config"))

local Tuning = {}

type LiveConfigModule = {
	getOverride: (path: string) -> (boolean, any),
}

local liveConfig: LiveConfigModule? = nil
do
	local module = script.Parent:FindFirstChild("LiveConfig")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result.getOverride) == "function" then
			liveConfig = result
		else
			warn("[Tuning] LiveConfig no cumple el contrato (getOverride); se usa solo Config")
		end
	end
end

local pathCache: { [string]: { string } } = {}

local function splitPath(path: string): { string }
	local parts = pathCache[path]
	if not parts then
		parts = string.split(path, ".")
		pathCache[path] = parts
	end
	return parts
end

local function lookup(path: string): (boolean, any)
	local node: any = Config
	for _, key in splitPath(path) do
		if type(node) ~= "table" then
			return false, nil
		end
		node = node[key]
		if node == nil then
			return false, nil
		end
	end
	return true, node
end

-- Devuelve el valor vigente de una ruta de Config, por ejemplo "Hazards.Damage".
function Tuning.get(path: string): any
	local exists, value = lookup(path)
	if not exists then
		error(`[Tuning] La ruta "{path}" no existe en Config`, 2)
	end
	if liveConfig then
		local ok, active, override = pcall(liveConfig.getOverride, path)
		if not ok then
			warn(`[Tuning] LiveConfig.getOverride falló para "{path}": {active}`)
		elseif active then
			if type(override) == type(value) then
				return override
			end
			warn(`[Tuning] Override de "{path}" ignorado: es {type(override)} y Config espera {type(value)}`)
		end
	end
	return value
end

-- Indica si la ruta existe en Config, sin fallar.
function Tuning.has(path: string): boolean
	local exists = lookup(path)
	return exists
end

return Tuning
