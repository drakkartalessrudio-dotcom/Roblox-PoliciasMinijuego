--!strict
--[[
	Session · plantilla de roblox-data-architect. Cópiala sin cambios a src/server/Data/.

	Los perfiles cargados en este servidor, sin servicios de Roblox: PlayerData le pasa el
	almacén, el reloj y la espera, y las pruebas con Lune le pasan un almacén en memoria.

	- Carga con bloqueo de sesión: el bloqueo vive en los metadatos de la clave y se toma
	  y renueva dentro de la misma operación de update. Otro servidor espera a que se
	  libere o a que pasen lockExpiry segundos sin renovarlo.
	- Un perfil guardado con una versión más nueva que el esquema no se toca: este
	  servidor corre código viejo.
	- Un perfil con otro formato (de antes de PlayerData) tampoco se toca, salvo que el
	  esquema declare document.legacy: entonces entra como versión 0 en la sección
	  "legacy" y las migraciones desde la 0 lo pasan a las secciones nuevas.
	- Si la carga falla, el estado queda en "unavailable" y nunca se guarda: así un error
	  no se convierte en un perfil vacío encima del real.
	- Si al guardar el bloqueo ya no es de este servidor, deja de guardar ("lost").
	- grantPurchase registra el PurchaseId en la misma escritura que el beneficio.

	Estados: "loading", "ready" y "unavailable" (con el motivo "locked", "error", "newer"
	o "lost").
]]

local Profile = require("./Profile")

local KEY_LIMIT = 4194304 -- caracteres por clave, medidos con JSONEncode

export type Metadata = { [string]: any }
export type Transform = (value: any, metadata: Metadata?) -> (any, Metadata?)
export type Store = {
	update: (self: any, key: string, transform: Transform, userIds: { number }?) -> (boolean, string?),
}
export type Status = "loading" | "ready" | "unavailable"
export type Options = {
	store: Store,
	schema: { [string]: any },
	migrations: Profile.Migrations?,
	jobId: string, -- identifica a este servidor en el bloqueo
	now: () -> number, -- segundos UTC (os.time)
	sleep: (seconds: number) -> (), -- task.wait
	log: ((message: string) -> ())?,
	encode: ((value: any) -> string)?, -- para medir el tamaño antes de guardar
	retries: number?, -- intentos de carga (5)
	retryDelay: number?, -- segundos antes del segundo intento; se duplica (2)
	lockExpiry: number?, -- segundos sin renovar para que otro servidor tome el bloqueo (400)
}

type Entry = {
	userId: number,
	key: string,
	status: Status,
	reason: string?,
	document: Profile.Document?,
	snapshots: { [string]: any },
	revision: number, -- cambios en memoria
	savedRevision: number, -- último cambio guardado
	unsaved: { [string]: number }, -- PurchaseId → revisión en que se registró
	lastSaveAt: number,
}

local Session = {}
Session.__index = Session

export type Session = typeof(setmetatable(
	{} :: {
		options: Options,
		schema: { [string]: any },
		entries: { [number]: Entry },
		lockExpiry: number,
	},
	Session
))

function Session.new(options: Options): Session
	local self = {
		options = options,
		schema = options.schema,
		entries = {},
		lockExpiry = options.lockExpiry or 400,
	}
	return setmetatable(self, Session)
end

local function log(self: Session, message: string)
	if self.options.log then
		self.options.log(message)
	end
end

function Session.key(self: Session, userId: number): string
	local key = string.gsub(self.schema.document.key, "{UserId}", tostring(userId))
	return key
end

local function lockOf(metadata: Metadata?): { id: string, at: number }?
	local lock = metadata and metadata.lock
	if type(lock) == "table" and type(lock.id) == "string" then
		return { id = lock.id, at = tonumber(lock.at) or 0 }
	end
	return nil
end

local function withLock(metadata: Metadata?, lock: { id: string, at: number }?): Metadata
	local copy: Metadata = if metadata then table.clone(metadata) else {}
	copy.lock = lock
	return copy
end

-- Saca el bloqueo de este servidor sin cambiar el valor (por ejemplo, si la carga falló después de tomarlo).
local function unlock(self: Session, key: string, userId: number)
	self.options.store:update(key, function(value: any, metadata: Metadata?)
		local lock = lockOf(metadata)
		if value == nil or not lock or lock.id ~= self.options.jobId then
			return nil, nil
		end
		return value, withLock(metadata, nil)
	end, { userId })
end

local function touchMeta(self: Session, document: Profile.Document)
	local name = Profile.metaSection(self.schema)
	if not name then
		return
	end
	local meta = document.sections[name]
	local fields = self.schema.sections[name].fields
	local now = self.options.now()
	if fields.firstJoinAt and meta.firstJoinAt == 0 then
		meta.firstJoinAt = now
	end
	if fields.lastJoinAt then
		meta.lastJoinAt = now
	end
	if fields.sessions then
		meta.sessions += 1
	end
end

-- Carga el perfil de un jugador. Devuelve el estado y, si no quedó listo, el motivo.
function Session.load(self: Session, userId: number): (Status, string?)
	local entry: Entry = {
		userId = userId,
		key = self:key(userId),
		status = "loading",
		snapshots = {},
		revision = 0,
		savedRevision = 0,
		unsaved = {},
		lastSaveAt = self.options.now(),
	}
	self.entries[userId] = entry
	local attempts = self.options.retries or 5
	local delay = self.options.retryDelay or 2
	local reason = "error"
	for attempt = 1, attempts do
		local outcome = "error"
		local loaded: any = nil
		local ok, err = self.options.store:update(entry.key, function(value: any, metadata: Metadata?)
			local lock = lockOf(metadata)
			local now = self.options.now()
			if lock and lock.id ~= self.options.jobId and now - lock.at < self.lockExpiry then
				outcome = "locked"
				return nil, nil
			end
			if type(value) == "table" and type(value.version) == "number" and value.version > self.schema.version then
				outcome = "newer"
				return nil, nil
			end
			outcome = "ok"
			loaded = value
			return value or Profile.new(self.schema), withLock(metadata, { id = self.options.jobId, at = now })
		end, { userId })

		if self.entries[userId] ~= entry then
			-- El jugador se fue mientras cargaba: devolver el bloqueo si se tomó.
			if ok and outcome == "ok" then
				unlock(self, entry.key, userId)
			end
			return "unavailable", "released"
		end
		if ok and outcome == "ok" then
			local document: Profile.Document
			if loaded == nil then
				document = Profile.new(self.schema)
			elseif type(loaded) == "table" and type(loaded.version) == "number" and type(loaded.sections) == "table" then
				document = Profile.deepCopy(loaded)
			elseif self.schema.document.legacy == true then
				-- Perfil de antes de PlayerData: entra como versión 0 en la sección legacy y se migra.
				document = { version = 0, sections = { legacy = Profile.deepCopy(loaded) } }
			else
				log(self, `el perfil de {userId} no tiene el formato de PlayerData; para adoptarlo, declara document.legacy y una migración desde la versión 0`)
				unlock(self, entry.key, userId)
				entry.status, entry.reason = "unavailable", "error"
				return "unavailable", "error"
			end
			local migrated, problem = Profile.migrate(self.schema, document, self.options.migrations)
			if not migrated then
				log(self, `no se pudo migrar el perfil de {userId}: {problem}`)
				unlock(self, entry.key, userId)
				entry.status, entry.reason = "unavailable", "error"
				return "unavailable", "error"
			end
			Profile.reconcileAll(self.schema, document)
			touchMeta(self, document)
			entry.document = document
			entry.status = "ready"
			entry.revision = 1 -- meta, migración y valores completados se guardan en el primer autosave
			entry.lastSaveAt = self.options.now()
			return "ready", nil
		elseif ok and outcome == "newer" then
			log(self, `el perfil de {userId} es de una versión más nueva que este servidor; no se carga ni se guarda`)
			entry.status, entry.reason = "unavailable", "newer"
			return "unavailable", "newer"
		end
		reason = if ok then outcome else "error"
		if not ok then
			log(self, `falló la carga de {userId} (intento {attempt}): {err}`)
		end
		if attempt < attempts then
			self.options.sleep(delay)
			delay *= 2
		end
	end
	entry.status, entry.reason = "unavailable", reason
	log(self, `el perfil de {userId} no está disponible ({reason})`)
	return "unavailable", reason
end

function Session.status(self: Session, userId: number): (Status?, string?)
	local entry = self.entries[userId]
	if not entry then
		return nil, nil
	end
	return entry.status, entry.reason
end

-- Copia de solo lectura de una sección, o nil si el perfil no está listo.
function Session.get(self: Session, userId: number, name: string): any
	local entry = self.entries[userId]
	if not entry or entry.status ~= "ready" or not entry.document then
		return nil
	end
	assert(self.schema.sections[name], `la sección {name} no existe en DataSchema`)
	local snapshot = entry.snapshots[name]
	if snapshot == nil then
		snapshot = Profile.deepFreeze(Profile.deepCopy(entry.document.sections[name]))
		entry.snapshots[name] = snapshot
	end
	return snapshot
end

--[[
	Cambia una sección: fn recibe una copia y la modifica. El cambio se aplica solo si
	respeta el esquema (tipos y límites). Devuelve false y el motivo si no está listo o
	si el resultado no es válido.
]]
function Session.update(self: Session, userId: number, name: string, fn: (draft: any) -> ()): (boolean, string?)
	local section = self.schema.sections[name]
	assert(section, `la sección {name} no existe en DataSchema`)
	local entry = self.entries[userId]
	if not entry or entry.status ~= "ready" or not entry.document then
		return false, "el perfil no está listo"
	end
	local draft = Profile.deepCopy(entry.document.sections[name])
	fn(draft)
	local problems = Profile.problems(Profile.sectionSpec(section), draft, name)
	if #problems > 0 then
		log(self, `cambio rechazado en {name} de {userId}: {problems[1]}`)
		return false, problems[1]
	end
	entry.document.sections[name] = draft
	entry.snapshots[name] = nil
	entry.revision += 1
	return true, nil
end

-- Vuelve una sección (o todo el perfil) a sus valores por defecto. Para DataDebug en Studio.
function Session.reset(self: Session, userId: number, name: string?): boolean
	local entry = self.entries[userId]
	if not entry or entry.status ~= "ready" or not entry.document then
		return false
	end
	for sectionName, section in self.schema.sections do
		if name == nil or name == sectionName then
			entry.document.sections[sectionName] = Profile.default(Profile.sectionSpec(section))
			entry.snapshots[sectionName] = nil
		end
	end
	entry.revision += 1
	return true
end

function Session.isDirty(self: Session, userId: number): boolean
	local entry = self.entries[userId]
	return entry ~= nil and entry.revision ~= entry.savedRevision
end

local function write(self: Session, entry: Entry, final: boolean): (boolean, string?)
	local document = entry.document :: Profile.Document
	local now = self.options.now()
	local meta = Profile.metaSection(self.schema)
	if meta and self.schema.sections[meta].fields.playTimeSec then
		document.sections[meta].playTimeSec += math.max(0, now - entry.lastSaveAt)
		entry.snapshots[meta] = nil
	end
	entry.lastSaveAt = now
	local revision = entry.revision
	local payload = Profile.deepCopy(document)
	if self.options.encode then
		local ok, text = pcall(self.options.encode, payload)
		if ok and #text > KEY_LIMIT then
			log(self, `el perfil de {entry.userId} pasa el límite por clave ({#text} caracteres); no se guarda`)
			return false, "too large"
		end
	end
	local outcome = "error"
	local ok, err = self.options.store:update(entry.key, function(_value: any, metadata: Metadata?)
		local lock = lockOf(metadata)
		if not lock or lock.id ~= self.options.jobId then
			outcome = "lost"
			return nil, nil
		end
		outcome = "ok"
		return payload, withLock(metadata, if final then nil else { id = self.options.jobId, at = now })
	end, { entry.userId })
	if ok and outcome == "ok" then
		entry.savedRevision = math.max(entry.savedRevision, revision)
		for purchaseId, mark in entry.unsaved do
			if mark <= revision then
				entry.unsaved[purchaseId] = nil
			end
		end
		return true, nil
	elseif ok and outcome == "lost" then
		log(self, `otro servidor tomó el perfil de {entry.userId}; este servidor deja de guardarlo`)
		entry.status, entry.reason = "unavailable", "lost"
		return false, "lost"
	end
	log(self, `falló el guardado de {entry.userId}: {err}`)
	return false, err
end

-- Guarda si hay cambios (o siempre, con force). El bloqueo sigue siendo de este servidor.
function Session.save(self: Session, userId: number, force: boolean?): (boolean, string?)
	local entry = self.entries[userId]
	if not entry or entry.status ~= "ready" then
		return false, "el perfil no está listo"
	end
	if not force and entry.revision == entry.savedRevision then
		return true, nil
	end
	return write(self, entry, false)
end

--[[
	Guardado final y liberación del bloqueo, al salir el jugador o al cerrar el servidor.
	Un perfil que no se cargó no se guarda. Reintenta hasta 3 veces.
]]
function Session.release(self: Session, userId: number): boolean
	local entry = self.entries[userId]
	if not entry then
		return true
	end
	self.entries[userId] = nil
	if entry.status ~= "ready" then
		return true
	end
	for attempt = 1, 3 do
		local ok, reason = write(self, entry, true)
		if ok or reason == "lost" or reason == "too large" then
			return ok
		end
		if attempt < 3 then
			self.options.sleep(1)
		end
	end
	return false
end

function Session.players(self: Session): { number }
	local list = {}
	for userId in self.entries do
		table.insert(list, userId)
	end
	return list
end

--[[
	Entrega una compra de Developer Products una sola vez. grant aplica el beneficio con
	la API de los módulos (en memoria) y devuelve true si lo aplicó. Devuelve "granted"
	solo cuando el PurchaseId quedó guardado junto con el beneficio; si no, "pending"
	(ProcessReceipt responde NotProcessedYet y Roblox lo vuelve a intentar).
]]
function Session.grantPurchase(self: Session, userId: number, purchaseId: string, grant: () -> boolean): "granted" | "pending"
	local entry = self.entries[userId]
	if not entry or entry.status ~= "ready" or not entry.document then
		return "pending"
	end
	local sectionName, field = Profile.purchasesField(self.schema)
	assert(sectionName and field, "DataSchema no tiene una sección con role purchases y un mapa de recibos")
	local processed = entry.document.sections[sectionName][field]
	if processed[purchaseId] == nil then
		local spec = self.schema.sections[sectionName].fields[field]
		if #purchaseId > (spec.keyMaxLength or 32) then
			-- Antes de entregar: si el recibo no se puede registrar, la compra se entregaría dos veces.
			log(self, `el PurchaseId {purchaseId} pasa de keyMaxLength en {sectionName}.{field}; no se entrega`)
			return "pending"
		end
		if not grant() then
			return "pending"
		end
		local limit = spec.maxEntries
		self:update(userId, sectionName, function(draft)
			-- Al llegar al límite se borra el recibo guardado más viejo: Roblox no reenvía un
			-- recibo confirmado con PurchaseGranted. Uno sin guardar nunca se borra.
			local map = draft[field]
			local count, oldestId, oldestAt = 0, nil, math.huge
			for id, at in map do
				count += 1
				if at < oldestAt and entry.unsaved[id] == nil then
					oldestId, oldestAt = id, at
				end
			end
			if count >= limit and oldestId then
				map[oldestId] = nil
			end
			map[purchaseId] = self.options.now()
		end)
		entry.unsaved[purchaseId] = entry.revision
	elseif entry.unsaved[purchaseId] == nil then
		return "granted" -- ya entregada y guardada
	end
	local saved = self:save(userId)
	return if saved and entry.unsaved[purchaseId] == nil then "granted" else "pending"
end

return Session
