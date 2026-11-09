--[[
	Transit · el único método para viajar en TravesurasBrainrot: Transit.to(jugador, destino).

	Los distritos están lejos unos de otros (cada uno es un nivel de Levels.json con su
	propio `origin`), así que viajar es un teletransporte, no una caminata. Los portales
	del lobby, los de regreso en cada distrito y el menú "Viajar" de la interfaz llaman
	todos a este método, que decide qué hacer según los datos de Destinations:

	  · destino en este mismo place   → funde a negro, mueve al personaje y vuelve a mostrar
	  · destino con `placeId` ajeno   → guarda el perfil y usa TeleportService

	Así pasar de "teletransporte dentro del place" a "viaje entre places" es cambiar un
	dato (el placeId del destino), no el código de quien viaja.

	Reglas (no se aplican con options.force, que usa el juego para sus propios traslados,
	por ejemplo tras una Ascensión): el destino existe, el nivel alcanza, no hay estrellas
	ni arresto ni travesura en curso, se parte de una zona segura y no se viaja dos veces
	seguidas. El cliente nunca decide nada de esto: solo pide.

	  Transit.init(context)                 { built }
	  Transit.canTravel(player, id)         -> (boolean, string?)  motivo: unknown, busy, cooldown, arrested,
	                                           wanted, level, away, here
	  Transit.to(player, id, options?)      -> (boolean, string?)  { force? }  true = el viaje empezó
	  Transit.arrivalPosition(id)           -> Vector3?  dónde se aparece en ese destino
	  Transit.traveled                      Signal (player, destinationId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Destinations = require(ReplicatedStorage.Shared.Destinations)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local LevelLoader = require(ServerScriptService.Server.LevelLoader)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local Arrest = require(ServerScriptService.Server.Modules.Arrest)
local Mischief = require(ServerScriptService.Server.Modules.Mischief)
local Progress = require(ServerScriptService.Server.Modules.Progress)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)
local Movement = require(script.Parent.Movement)

export type Context = {
	built: LevelLoader.Built,
}

export type Options = {
	force: boolean?,
}

local Transit = {}

Transit.traveled = Signal.new() :: Signal.Signal<Player, string>

-- Zonas desde las que se puede salir de viaje: seguras y con portal o menú a mano.
local DEPARTURE_ZONES = { "lobby", "guarida", "portal" }

local built: LevelLoader.Built? = nil
local traveling: { [Player]: boolean } = {}
local lastTravelAt: { [Player]: number } = {}
local random = Random.new()

function Transit.init(context: Context)
	built = context.built
end

local function currentDestination(player: Player): Destinations.Destination?
	local district = player:GetAttribute("District")
	return if type(district) == "string" then Destinations.byLevel[district] else nil
end

local function arrivalPart(destination: Destinations.Destination): BasePart?
	assert(built, "Transit.init no se llamó")
	local level = built.byId[destination.levelId]
	if not level then
		return nil
	end
	if destination.arrival then
		return level.pieces[destination.arrival]
	end
	local spawns = level.byKind.spawn
	return if spawns and #spawns > 0 then spawns[random:NextInteger(1, #spawns)] else level.start
end

function Transit.arrivalPosition(id: string): Vector3?
	local destination = Destinations.byId[id]
	local part = if destination then arrivalPart(destination) else nil
	if not part then
		return nil
	end
	local jitter = Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2))
	return LevelLoader.standCFrame(part, 3).Position + jitter
end

function Transit.canTravel(player: Player, id: string): (boolean, string?)
	local destination = Destinations.byId[id]
	if not destination then
		return false, "unknown"
	end
	if traveling[player] then
		return false, "busy"
	end
	if os.clock() - (lastTravelAt[player] or -math.huge) < Tuning.get("Travel.CooldownSeconds") then
		return false, "cooldown"
	end
	if Arrest.isHeld(player) then
		return false, "arrested"
	end
	if Wanted.stars(player) > 0 or Wanted.state(player) ~= "clear" then
		return false, "wanted"
	end
	if Mischief.active(player) then
		return false, "busy"
	end
	if Progress.level(player) < destination.minLevel then
		return false, "level"
	end
	local safe = false
	for _, zone in DEPARTURE_ZONES do
		if Areas.inside(player, zone) then
			safe = true
			break
		end
	end
	if not safe then
		return false, "away"
	end
	if currentDestination(player) == destination then
		return false, "here"
	end
	return true, nil
end

-- Viaje a otro place de la experiencia. No hay ninguno declarado todavía: el destino debe
-- traer un placeId que el usuario cargó, y TeleportService no funciona en Studio.
local function leavePlace(player: Player, destination: Destinations.Destination): (boolean, string?)
	local placeId = destination.placeId
	if not placeId or placeId <= 0 then
		return false, "pending"
	end
	if RunService:IsStudio() then
		return false, "studio"
	end
	PlayerData.save(player) -- el destino carga el mismo perfil: que no pierda lo último
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)
	if not ok then
		warn(`[Transit] TeleportAsync a {destination.id} falló: {err}`)
		return false, "failed"
	end
	return true, nil
end

local function run(player: Player, destination: Destinations.Destination)
	local fade = Tuning.get("Travel.FadeSeconds")
	Net.send(player, "travel", { phase = "out", name = destination.name, seconds = fade })
	task.wait(fade)
	local position = Transit.arrivalPosition(destination.id)
	if position and player.Parent == Players and player.Character then
		-- Pide al cliente que cargue el mapa de destino antes de aparecer: evita caer al vacío.
		pcall(function()
			player:RequestStreamAroundAsync(position, Tuning.get("Travel.StreamTimeoutSeconds"))
		end)
		if Movement.teleport(player, position) then
			Movement.setHome(player, position) -- World actualiza el atributo District al detectar la zona del nivel
			Telemetry.custom(player, "travel", nil, { district = destination.id })
			Transit.traveled:Fire(player, destination.id)
		end
	else
		warn(`[Transit] No se pudo llevar a {player.Name} a {destination.id}`)
	end
	Net.send(player, "travel", { phase = "in", name = destination.name, seconds = fade })
	traveling[player] = nil
end

function Transit.to(player: Player, id: string, options: Options?): (boolean, string?)
	local force = options ~= nil and options.force == true
	if force then
		if not Destinations.byId[id] then
			return false, "unknown"
		end
		if traveling[player] then
			return false, "busy"
		end
	else
		local ok, reason = Transit.canTravel(player, id)
		if not ok then
			return false, reason
		end
	end
	local destination = Destinations.byId[id]
	lastTravelAt[player] = os.clock()
	if destination.placeId then
		return leavePlace(player, destination)
	end
	traveling[player] = true
	task.spawn(run, player, destination)
	return true, nil
end

Players.PlayerRemoving:Connect(function(player)
	traveling[player], lastTravelAt[player] = nil, nil
end)

return Transit
