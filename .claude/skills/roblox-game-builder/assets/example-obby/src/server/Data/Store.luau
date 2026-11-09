--!strict
--[[
	Store · plantilla de roblox-data-architect. Cópiala sin cambios a src/server/Data/.

	Dónde se guardan los perfiles. Session solo usa update(key, transform, userIds):
	transform recibe el valor y los metadatos actuales y devuelve el valor y los
	metadatos nuevos, o nil para no escribir.

	- Store.dataStore(nombre): un DataStore de Roblox con UpdateAsync. Los userIds quedan
	  asociados a la clave, como pide Roblox para los pedidos de borrado de datos.
	- Store.memory(): en memoria del servidor (persistence "memory", Studio sin acceso a
	  la API y pruebas). Copia los valores al leer y al escribir, como un DataStore, y
	  puede simular fallos: failures = n hace fallar los próximos n pedidos.
]]

local Profile = require("./Profile")

export type Metadata = { [string]: any }
export type Transform = (value: any, metadata: Metadata?) -> (any, Metadata?)

local Store = {}

function Store.dataStore(name: string)
	local DataStoreService = game:GetService("DataStoreService")
	local dataStore = DataStoreService:GetDataStore(name)
	local store = {}

	function store.update(_self: any, key: string, transform: Transform, userIds: { number }?): (boolean, string?)
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(value: any, keyInfo: DataStoreKeyInfo?)
				local metadata = if keyInfo then keyInfo:GetMetadata() else nil
				local newValue, newMetadata = transform(value, metadata)
				if newValue == nil then
					return nil
				end
				return newValue, userIds, newMetadata
			end)
		end)
		if ok then
			return true, nil
		end
		return false, tostring(err)
	end

	-- Pedidos de UpdateAsync que le quedan a este servidor en este minuto.
	function store.budget(_self: any): number
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end

	return store
end

export type Entry = { value: any, metadata: Metadata, userIds: { number }? }

function Store.memory(backing: { [string]: Entry }?)
	local store = {
		data = backing or {} :: { [string]: Entry },
		failures = 0,
		calls = 0,
	}

	function store.update(self: any, key: string, transform: Transform, userIds: { number }?): (boolean, string?)
		self.calls += 1
		if self.failures > 0 then
			self.failures -= 1
			return false, "fallo simulado"
		end
		local current = self.data[key]
		local value = if current then Profile.deepCopy(current.value) else nil
		local metadata = if current then Profile.deepCopy(current.metadata) else nil
		local newValue, newMetadata = transform(value, metadata)
		if newValue == nil then
			return true, nil
		end
		self.data[key] = {
			value = Profile.deepCopy(newValue),
			metadata = Profile.deepCopy(newMetadata) or {},
			userIds = userIds,
		}
		return true, nil
	end

	function store.budget(_self: any): number
		return math.huge
	end

	return store
end

return Store
