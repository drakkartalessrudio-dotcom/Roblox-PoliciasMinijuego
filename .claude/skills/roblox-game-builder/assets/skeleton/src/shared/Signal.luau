--[[
	Signal · plantilla del contrato de la fábrica (roblox-game-builder).

	Eventos entre módulos sin instancias. Un módulo core publica lo que pasa con un
	Signal y un puente o Game se conecta; el core no sabe quién escucha. Es el
	equivalente de las funciones Subscribe de los módulos de UEFN.

	  local Quests = {}
	  Quests.completed = Signal.new() :: Signal.Signal<Player, string>

	  local connection = Quests.completed:Connect(function(player, questId) end)
	  Quests.completed:Fire(player, "intro") -- solo lo llama el módulo dueño
	  connection:Disconnect()

	Cada handler corre en su propio hilo (task.spawn): un error en un handler no
	corta a los demás ni al módulo que emite. Un handler que se desconecta durante
	un Fire no recibe ese Fire si todavía no le tocaba.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Entry = {
	callback: (...any) -> (),
	connection: Connection,
	once: boolean,
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local entries: { Entry } = {}

	local function remove(entry: Entry)
		local index = table.find(entries, entry)
		if index then
			table.remove(entries, index)
		end
		entry.connection.Connected = false
	end

	local function add(callback: (...any) -> (), once: boolean): Connection
		local entry: Entry
		local connection: Connection = {
			Connected = true,
			Disconnect = function(_self: Connection)
				remove(entry)
			end,
		}
		entry = { callback = callback, connection = connection, once = once }
		table.insert(entries, entry)
		return connection
	end

	local signal = {}

	function signal.Connect(_self: any, handler: (...any) -> ()): Connection
		return add(handler, false)
	end

	function signal.Once(_self: any, handler: (...any) -> ()): Connection
		return add(handler, true)
	end

	function signal.Wait(_self: any): ...any
		local thread = coroutine.running()
		add(function(...)
			task.spawn(thread, ...)
		end, true)
		return coroutine.yield()
	end

	function signal.Fire(_self: any, ...: any)
		for _, entry in table.clone(entries) do
			if entry.connection.Connected then
				if entry.once then
					remove(entry)
				end
				task.spawn(entry.callback, ...)
			end
		end
	end

	function signal.DisconnectAll(_self: any)
		for _, entry in entries do
			entry.connection.Connected = false
		end
		table.clear(entries)
	end

	return (signal :: any) :: Signal<T...>
end

return Signal
