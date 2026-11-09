--[[
	Zones · módulo core: detecta cuándo un jugador entra a una zona de los niveles
	(piezas kind "zone" de Levels.json, con su nombre en el atributo ZoneName).

	Publica entered y nada más: no sabe si una zona cuenta para una misión, cambia la
	música o abre una tienda. Eso lo conectan los puentes. Una visita cuenta de nuevo
	después de Zones.Cooldown segundos.

	API:
	  Zones.init(options)   niveles construidos, antes de start
	  Zones.start()         conecta las zonas y atiende a los jugadores
	  Zones.entered         Signal (player, zoneId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local LevelLoader = require(ServerScriptService.Server.LevelLoader)

export type Options = {
	built: LevelLoader.Built, -- niveles construidos por LevelLoader.build
}

local Zones = {}

Zones.entered = Signal.new() :: Signal.Signal<Player, string>

local built: LevelLoader.Built
local lastEntered: { [Player]: { [string]: number } } = {}

local function playerFromHit(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function onTouched(zone: BasePart, hit: BasePart)
	local player = playerFromHit(hit)
	local times = player and lastEntered[player]
	local zoneId = zone:GetAttribute("ZoneName")
	if not player or not times or type(zoneId) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (times[zoneId] or -math.huge) < Tuning.get("Zones.Cooldown") then
		return
	end
	times[zoneId] = now
	Zones.entered:Fire(player, zoneId)
end

function Zones.init(options: Options)
	built = options.built
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

	for _, level in built.levels do
		for _, zone in level.byKind.zone or {} do
			zone.Touched:Connect(function(hit)
				onTouched(zone, hit)
			end)
		end
	end
end

return Zones
