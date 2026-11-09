--[[
	Zones · módulo core del esqueleto de capas.

	Detecta cuándo un jugador entra a una zona: una BasePart con la etiqueta "Zone"
	y el atributo de texto ZoneId. Publica `entered` y nada más: no sabe si eso
	cuenta para una misión, cambia la música o da un logro. Eso lo conectan los
	puentes, sin tocar este módulo.

	API:
	  Zones.init(options?)  antes de start; opciones: tag y cooldown
	  Zones.start()         empieza a escuchar las zonas y a los jugadores
	  Zones.entered         Signal (player, zoneId)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

export type Options = {
	tag: string?, -- etiqueta de las zonas; por defecto "Zone"
	cooldown: number?, -- segundos antes de volver a contar la misma zona para un jugador
}

local Zones = {}

Zones.entered = Signal.new() :: Signal.Signal<Player, string>

local tag = "Zone"
local cooldown = 2
local lastEntered: { [Player]: { [string]: number } } = {}

local function onTouched(zone: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local player = character and Players:GetPlayerFromCharacter(character)
	local zoneId = zone:GetAttribute("ZoneId")
	local times = player and lastEntered[player]
	if not player or not times or not humanoid or humanoid.Health <= 0 or type(zoneId) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (times[zoneId] or -math.huge) < cooldown then
		return
	end
	times[zoneId] = now
	Zones.entered:Fire(player, zoneId)
end

local function watch(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Touched:Connect(function(hit)
			onTouched(instance, hit)
		end)
	end
end

function Zones.init(options: Options?)
	if options then
		tag = options.tag or tag
		cooldown = options.cooldown or cooldown
	end
end

function Zones.start()
	local function onPlayerAdded(player: Player)
		lastEntered[player] = {}
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastEntered[player] = nil
	end)

	for _, zone in CollectionService:GetTagged(tag) do
		watch(zone)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
end

return Zones
