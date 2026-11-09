--!strict
--[[
	Profile · plantilla de roblox-data-architect. Cópiala sin cambios a src/server/Data/.

	Funciones puras sobre el esquema de DataSchema.json: valores por defecto, completar
	un perfil cargado, validar una sección y aplicar las migraciones. Siguen las mismas
	reglas que check_data.py. No usan servicios de Roblox: se prueban con Lune.

	Un documento guardado tiene esta forma:
	  { version = 2, sections = { meta = { … }, quests = { … } } }
]]

export type Spec = { [string]: any }
export type Sections = { [string]: any }
export type Document = { version: number, sections: Sections }
export type Migration = (sections: Sections, info: { from: number, to: number }) -> ()
export type Migrations = { [string]: Migration }

local Profile = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end
Profile.deepCopy = deepCopy

-- Congela una tabla y todo lo que contiene: lo que devuelve get() no se puede modificar.
function Profile.deepFreeze(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, item in value do
			Profile.deepFreeze(item)
		end
		table.freeze(value)
	end
	return value
end

function Profile.sectionSpec(section: Spec): Spec
	return { type = "record", fields = section.fields }
end

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge and math.floor(value) == value
end

local function isNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Valor por defecto de un campo: el declarado o el de su tipo.
function Profile.default(spec: Spec): any
	if spec.default ~= nil then
		return deepCopy(spec.default)
	end
	local kind = spec.type
	if kind == "boolean" then
		return false
	elseif kind == "integer" or kind == "number" then
		local value = 0
		if type(spec.min) == "number" and value < spec.min then
			value = spec.min
		end
		if type(spec.max) == "number" and value > spec.max then
			value = spec.max
		end
		return value
	elseif kind == "string" then
		return ""
	elseif kind == "enum" then
		return spec.values[1]
	elseif kind == "time" then
		return 0
	elseif kind == "map" or kind == "list" then
		return {}
	elseif kind == "record" then
		local out = {}
		for name, child in spec.fields do
			out[name] = Profile.default(child)
		end
		return out
	end
	return nil
end

-- Problemas de un valor contra su campo, con la ruta de cada uno. Vacío si es válido.
function Profile.problems(spec: Spec, value: any, path: string): { string }
	local problems: { string } = {}
	local kind = spec.type

	local function bounds(number: number)
		if type(spec.min) == "number" and number < spec.min then
			table.insert(problems, `{path} vale {number}, menos que min {spec.min}`)
		end
		if type(spec.max) == "number" and number > spec.max then
			table.insert(problems, `{path} vale {number}, más que max {spec.max}`)
		end
	end

	if kind == "boolean" then
		if type(value) ~= "boolean" then
			table.insert(problems, `{path} debe ser boolean`)
		end
	elseif kind == "integer" then
		if not isInteger(value) then
			table.insert(problems, `{path} debe ser integer`)
		else
			bounds(value)
		end
	elseif kind == "number" then
		if not isNumber(value) then
			table.insert(problems, `{path} debe ser number`)
		else
			bounds(value)
		end
	elseif kind == "time" then
		if not isInteger(value) or value < 0 then
			table.insert(problems, `{path} debe ser time (segundos UTC, entero ≥ 0)`)
		end
	elseif kind == "string" then
		if type(value) ~= "string" then
			table.insert(problems, `{path} debe ser string`)
		elseif #value > spec.maxLength then
			table.insert(problems, `{path} pasa de maxLength {spec.maxLength}`)
		end
	elseif kind == "enum" then
		if table.find(spec.values, value) == nil then
			table.insert(problems, `{path} vale {tostring(value)}, que no está en values`)
		end
	elseif kind == "map" then
		if type(value) ~= "table" then
			table.insert(problems, `{path} debe ser un mapa`)
		else
			local count = 0
			local keyLimit = spec.keyMaxLength or 32
			for key, item in value do
				count += 1
				if type(key) ~= "string" then
					table.insert(problems, `{path} tiene una clave que no es texto`)
				elseif #key > keyLimit then
					table.insert(problems, `{path}.{key} pasa de keyMaxLength {keyLimit}`)
				else
					for _, problem in Profile.problems(spec.value, item, `{path}.{key}`) do
						table.insert(problems, problem)
					end
				end
			end
			if count > spec.maxEntries then
				table.insert(problems, `{path} tiene más de maxEntries {spec.maxEntries}`)
			end
		end
	elseif kind == "list" then
		if type(value) ~= "table" then
			table.insert(problems, `{path} debe ser una lista`)
		else
			local count = 0
			for key in value do
				count += 1
				if not isInteger(key) or key < 1 then
					table.insert(problems, `{path} debe ser una lista, sin claves de texto`)
					break
				end
			end
			if count ~= #value then
				table.insert(problems, `{path} tiene huecos`)
			elseif count > spec.maxItems then
				table.insert(problems, `{path} tiene más de maxItems {spec.maxItems}`)
			end
			for index, item in ipairs(value) do
				for _, problem in Profile.problems(spec.items, item, `{path}[{index}]`) do
					table.insert(problems, problem)
				end
			end
		end
	elseif kind == "record" then
		if type(value) ~= "table" then
			table.insert(problems, `{path} debe ser un registro`)
		else
			for key, item in value do
				local child = spec.fields[key]
				if child == nil then
					table.insert(problems, `{path}.{tostring(key)} no existe en el esquema`)
				else
					for _, problem in Profile.problems(child, item, `{path}.{key}`) do
						table.insert(problems, problem)
					end
				end
			end
		end
	end
	return problems
end

--[[
	Completa un valor cargado: agrega lo que falta con valores por defecto, descarta lo
	que el esquema no conoce, ajusta a min y max los números fuera de rango y reemplaza
	por el valor por defecto lo que tiene otro tipo.
]]
function Profile.reconcile(spec: Spec, value: any): any
	local kind = spec.type
	if kind == "record" then
		local source = if type(value) == "table" then value else {}
		local out = {}
		for name, child in spec.fields do
			out[name] = Profile.reconcile(child, source[name])
		end
		return out
	elseif kind == "map" then
		local out = {}
		if type(value) == "table" then
			for key, item in value do
				if type(key) == "string" then
					out[key] = Profile.reconcile(spec.value, item)
				end
			end
		end
		return out
	elseif kind == "list" then
		local out = {}
		if type(value) == "table" then
			for _, item in ipairs(value) do
				table.insert(out, Profile.reconcile(spec.items, item))
			end
		end
		return out
	elseif (kind == "integer" or kind == "number") and isNumber(value) then
		local number = if kind == "integer" then math.floor(value) else value
		if type(spec.min) == "number" then
			number = math.max(number, spec.min)
		end
		if type(spec.max) == "number" then
			number = math.min(number, spec.max)
		end
		return number
	end
	if value ~= nil and #Profile.problems(spec, value, "") == 0 then
		return value
	end
	return Profile.default(spec)
end

-- Documento nuevo con todas las secciones por defecto.
function Profile.new(schema: Spec): Document
	local sections = {}
	for name, section in schema.sections do
		sections[name] = Profile.default(Profile.sectionSpec(section))
	end
	return { version = schema.version, sections = sections }
end

-- Completa todas las secciones de un documento ya migrado.
function Profile.reconcileAll(schema: Spec, document: Document)
	local sections = {}
	for name, section in schema.sections do
		sections[name] = Profile.reconcile(Profile.sectionSpec(section), document.sections[name])
	end
	document.sections = sections
end

-- --- Migraciones -------------------------------------------------------------

local function split(path: string): { string }
	return string.split(path, ".")
end

-- Rutas concretas que coinciden con un patrón con *, y las claves que tomó cada *.
local function matches(node: any, parts: { string }, index: number, path: { string }, keys: { string }, found: { any })
	if index > #parts then
		table.insert(found, { path = table.clone(path), keys = table.clone(keys) })
		return
	end
	if type(node) ~= "table" then
		return
	end
	local part = parts[index]
	if part == "*" then
		for key, child in node do
			if type(key) == "string" then
				table.insert(path, key)
				table.insert(keys, key)
				matches(child, parts, index + 1, path, keys, found)
				table.remove(path)
				table.remove(keys)
			end
		end
	elseif node[part] ~= nil then
		table.insert(path, part)
		matches(node[part], parts, index + 1, path, keys, found)
		table.remove(path)
	end
end

local function find(root: Sections, pattern: string): { any }
	local found = {}
	matches(root, split(pattern), 1, {}, {}, found)
	return found
end

local function parentOf(root: Sections, path: { string }, create: boolean): any
	local node: any = root
	for index = 1, #path - 1 do
		local key = path[index]
		if type(node[key]) ~= "table" then
			if not create then
				return nil
			end
			node[key] = {}
		end
		node = node[key]
	end
	return node
end

local function substitute(pattern: string, keys: { string }): { string }
	local parts = split(pattern)
	local next = 1
	for index, part in parts do
		if part == "*" then
			parts[index] = keys[next]
			next += 1
		end
	end
	return parts
end

-- Aplica una operación declarativa. Una ruta de origen que no existe no hace nada.
function Profile.applyOp(root: Sections, op: Spec)
	if op.op == "move" then
		for _, match in find(root, op.from) do
			local parent = parentOf(root, match.path, false)
			local key = match.path[#match.path]
			local value = parent[key]
			parent[key] = nil
			local target = substitute(op.to, match.keys)
			parentOf(root, target, true)[target[#target]] = value
		end
	elseif op.op == "add" or op.op == "set" then
		local parts = split(op.path)
		local last = table.remove(parts) :: string
		local parents: { any } = if table.find(parts, "*") then find(root, table.concat(parts, ".")) else { { path = parts } }
		for _, match in parents do
			local path = table.clone(match.path)
			table.insert(path, last)
			local parent = parentOf(root, path, true)
			if op.op == "set" or parent[last] == nil then
				parent[last] = deepCopy(op.value)
			end
		end
	elseif op.op == "remove" then
		for _, match in find(root, op.path) do
			local parent = parentOf(root, match.path, false)
			if parent then
				parent[match.path[#match.path]] = nil
			end
		end
	end
end

--[[
	Lleva un documento hasta schema.version. Devuelve false y el motivo si falta una
	migración o una función custom. No completa valores por defecto: eso es reconcileAll.
]]
function Profile.migrate(schema: Spec, document: Document, custom: Migrations?): (boolean, string?)
	while document.version < schema.version do
		local from = document.version
		local migration
		for _, candidate in schema.migrations or {} do
			if candidate.from == from then
				migration = candidate
			end
		end
		if not migration then
			return false, `falta la migración de la versión {from} a la {from + 1}`
		end
		for _, op in migration.ops do
			if op.op == "custom" then
				local handler = custom and custom[op.name]
				if not handler then
					return false, `falta la función {op.name} en Migrations`
				end
				handler(document.sections, { from = from, to = from + 1 })
			else
				Profile.applyOp(document.sections, op)
			end
		end
		document.version = from + 1
	end
	return true, nil
end

-- Sección y campo (mapa) donde se registran los recibos: la sección con role purchases.
function Profile.purchasesField(schema: Spec): (string?, string?)
	for name, section in schema.sections do
		if section.role == "purchases" then
			for field, spec in section.fields do
				if spec.type == "map" then
					return name, field
				end
			end
		end
	end
	return nil, nil
end

function Profile.metaSection(schema: Spec): string?
	for name, section in schema.sections do
		if section.role == "meta" then
			return name
		end
	end
	return nil
end

return Profile
