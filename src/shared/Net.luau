--[[
	Net · canal de red del juego (núcleo). Un solo RemoteEvent con tipos de mensaje por
	nombre, para que el cliente solo pueda enviar INTENCIONES que el servidor valida.

	Servidor:
	  Net.on(kind, validate, handler, minInterval?)
	      validate(payload) -> cleaned? : devuelve el payload limpio o nil si es inválido.
	      handler(player, cleaned). minInterval: segundos mínimos entre mensajes del mismo
	      tipo por jugador (0,1 por defecto): lo que llega más rápido se descarta.
	  Net.send(player, kind, payload)      al cliente
	  Net.broadcast(kind, payload)         a todos
	Cliente:
	  Net.send(kind, payload)              al servidor
	  Net.on(kind, handler)                handler(payload)

	El cliente nunca manda precios, cantidades de recompensa ni resultados confirmados:
	solo qué quiere hacer. Lo decide el servidor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Servidor y cliente exponen funciones distintas con el mismo nombre (send, on): se tipa como any.
local Net = {} :: any

local IS_SERVER = RunService:IsServer()
local remote: RemoteEvent
if IS_SERVER then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Net"
	remote.Parent = ReplicatedStorage
else
	remote = ReplicatedStorage:WaitForChild("Net") :: RemoteEvent
end

local DEFAULT_INTERVAL = 0.1
local MAX_KIND_LENGTH = 32

if IS_SERVER then
	type Route = {
		validate: (payload: any) -> any?,
		handler: (player: Player, payload: any) -> (),
		minInterval: number,
	}
	local routes: { [string]: Route } = {}
	local lastSeen: { [Player]: { [string]: number } } = {}

	function Net.on(kind: string, validate: (payload: any) -> any?, handler: (player: Player, payload: any) -> (), minInterval: number?)
		assert(routes[kind] == nil, `Net.on: el mensaje {kind} ya tiene un manejador`)
		routes[kind] = { validate = validate, handler = handler, minInterval = minInterval or DEFAULT_INTERVAL }
	end

	function Net.send(player: Player, kind: string, payload: any?)
		if player.Parent then
			remote:FireClient(player, kind, payload)
		end
	end

	function Net.broadcast(kind: string, payload: any?)
		remote:FireAllClients(kind, payload)
	end

	remote.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
		if type(kind) ~= "string" or #kind > MAX_KIND_LENGTH then
			return
		end
		local route = routes[kind]
		if not route then
			return
		end
		local seen = lastSeen[player]
		if not seen then
			seen = {}
			lastSeen[player] = seen
		end
		local now = os.clock()
		if seen[kind] and now - seen[kind] < route.minInterval then
			return
		end
		seen[kind] = now
		local ok, cleaned = pcall(route.validate, payload)
		if not ok or cleaned == nil then
			return
		end
		local success, err = pcall(route.handler, player, cleaned)
		if not success then
			warn(`[Net] {kind} de {player.Name} falló: {err}`)
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		lastSeen[player] = nil
	end)
else
	local handlers: { [string]: { (payload: any) -> () } } = {}

	function Net.send(kind: string, payload: any?)
		remote:FireServer(kind, payload)
	end

	function Net.on(kind: string, handler: (payload: any) -> ())
		local list = handlers[kind]
		if not list then
			list = {}
			handlers[kind] = list
		end
		table.insert(list, handler)
	end

	remote.OnClientEvent:Connect(function(kind: any, payload: any)
		if type(kind) ~= "string" then
			return
		end
		local list = handlers[kind]
		if list then
			for _, handler in list do
				task.spawn(handler, payload)
			end
		end
	end)
end

-- Validadores comunes (los usa el servidor al registrar mensajes).
function Net.isId(value: any, maxLength: number?): boolean
	return type(value) == "string" and #value > 0 and #value <= (maxLength or 32) and string.match(value, "^[%w_%-]+$") ~= nil
end

function Net.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 1e9
end

function Net.isDirection(value: any): boolean
	return typeof(value) == "Vector3" and Net.isFiniteNumber(value.X) and Net.isFiniteNumber(value.Y) and Net.isFiniteNumber(value.Z)
		and value.Magnitude > 0.01
end

return Net
