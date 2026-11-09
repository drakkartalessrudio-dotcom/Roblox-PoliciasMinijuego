--[[
	Tools · módulo core: el uso de las acciones y herramientas del jugador y sus
	enfriamientos. Acciones siempre disponibles: "dash" (Embestida) y "push" (Empujón).
	Herramientas que se compran: tarta, banana, humo, patineta y señuelo.

	Valida que la herramienta exista, que el jugador la tenga (Game le pasa `owns`) y que no
	esté en enfriamiento, y publica `used`. Lo que hace cada herramienta en el mundo lo
	implementa Game (necesita policías, velocidad y el espacio de juego).

	Publica atributos del jugador: ToolReady_<id> con la hora del servidor
	(Workspace:GetServerTimeNow()) en que vuelve a estar disponible. La UI compara con esa
	hora para dibujar el enfriamiento.

	API:
	  Tools.init(options)                    { owns(player, toolId) -> boolean }
	  Tools.start()
	  Tools.use(player, toolId)              -> (boolean, string?)
	  Tools.setActive(player, id, seconds)   efecto con duración (patineta)
	  Tools.isActive(player, id)             -> boolean
	  Tools.used                             Signal (player, toolId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

export type Options = {
	owns: (player: Player, toolId: string) -> boolean,
}

local Tools = {}

Tools.used = Signal.new() :: Signal.Signal<Player, string>

local options: Options? = nil
local readyAt: { [Player]: { [string]: number } } = {} -- os.clock
local activeUntil: { [Player]: { [string]: number } } = {}

local function cooldownOf(toolId: string): number?
	if toolId == "dash" then
		return Tuning.get("Player.DashCooldown")
	elseif toolId == "push" then
		return Tuning.get("Player.PushCooldown")
	end
	local def = Catalog.toolById[toolId]
	return if def then Tuning.get(`Tools.{def.configKey}.Cooldown`) else nil
end

function Tools.init(opts: Options)
	options = opts
end

function Tools.start()
	Players.PlayerAdded:Connect(function(player)
		readyAt[player] = {}
		activeUntil[player] = {}
	end)
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		activeUntil[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		readyAt[player] = readyAt[player] or {}
		activeUntil[player] = activeUntil[player] or {}
	end
end

function Tools.use(player: Player, toolId: string): (boolean, string?)
	assert(options)
	local cooldown = cooldownOf(toolId)
	if not cooldown then
		return false, "unknown"
	end
	if toolId ~= "dash" and toolId ~= "push" and not options.owns(player, toolId) then
		return false, "locked"
	end
	local state = readyAt[player]
	if not state then
		return false, "gone"
	end
	local now = os.clock()
	if state[toolId] and now < state[toolId] then
		return false, "cooldown"
	end
	state[toolId] = now + cooldown
	player:SetAttribute(`ToolReady_{toolId}`, Workspace:GetServerTimeNow() + cooldown)
	Tools.used:Fire(player, toolId)
	return true, nil
end

function Tools.setActive(player: Player, id: string, seconds: number)
	local state = activeUntil[player]
	if state then
		state[id] = os.clock() + seconds
	end
end

function Tools.isActive(player: Player, id: string): boolean
	local state = activeUntil[player]
	return state ~= nil and state[id] ~= nil and os.clock() < state[id]
end

return Tools
