--[[
	Travel · plantilla del contrato de la fábrica (roblox-game-builder).

	Lleva jugadores de un place a otro de la misma experiencia con TeleportService,
	como pide la guía de Roblox: solo desde el servidor, con reintentos, y con
	TeleportInitFailed para los fallos que llegan tarde. Un viaje a un servidor
	reservado que falla se reintenta al mismo servidor, para no separar al grupo.

	Antes de viajar llama a las funciones registradas con Travel.onBeforeTravel (por
	ejemplo, guardar el perfil): el progreso viaja por DataStore, nunca en los datos
	del teleport, que el cliente puede leer. Si un viaje falla del todo, el jugador
	recibe el atributo "TravelFailed" con la clave del destino para que la UI lo avise.

	TeleportService no funciona en Studio: ahí Travel.to no viaja, avisa y devuelve
	false con el motivo "studio". Los viajes se prueban en la experiencia publicada.
	Emite los eventos travel y travel_failed con Telemetry.
	Uso: references/hooks.md del builder.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Place = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Place"))
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))

local Travel = {}

export type Options = {
	reserved: boolean?, -- un servidor reservado nuevo para todo el grupo (partidas)
	accessCode: string?, -- unirse a un servidor reservado existente
	data: { [string]: any }?, -- datos no sensibles para el destino (mapa, id de partida)
}

type Pending = { key: string, placeId: number, data: { [string]: any }?, accessCode: string?, attempts: number }

local MAX_ATTEMPTS = 3
local RETRY_DELAY = 2 -- segundos; crece con cada intento
local FLOODED_DELAY = 15 -- Roblox pide esperar más cuando el destino está saturado

local beforeTravel: { (Player, string) -> () } = {}
local pending: { [Player]: Pending } = {}

-- Registra una función que corre antes de cada viaje, por jugador (por ejemplo, guardar datos).
function Travel.onBeforeTravel(callback: (player: Player, destination: string) -> ())
	table.insert(beforeTravel, callback)
end

local function buildOptions(data: { [string]: any }?, reserved: boolean?, accessCode: string?): TeleportOptions
	local options = Instance.new("TeleportOptions")
	if accessCode then
		options.ReservedServerAccessCode = accessCode
	elseif reserved then
		options.ShouldReserveServer = true
	end
	if data then
		options:SetTeleportData(data)
	end
	return options
end

local function fail(player: Player, key: string, reason: string)
	pending[player] = nil
	player:SetAttribute("TravelFailed", key)
	Telemetry.custom(player, "travel_failed", nil, { to = key, reason = reason })
	warn(`[Travel] {player.Name} no pudo viajar a "{key}": {reason}`)
end

-- Lleva a los jugadores al place `key`. Devuelve (true, resultado) o (false, motivo):
-- "desconocido", "pendiente" (falta el PlaceId), "studio" o el error de Roblox.
function Travel.to(players: { Player }, key: string, options: Options?): (boolean, any)
	local known = pcall(Place.info, key)
	if not known then
		warn(`[Travel] No existe el place "{key}" en Places.json`)
		return false, "desconocido"
	end
	local placeId = Place.id(key)
	if not placeId then
		warn(`[Travel] El place "{key}" todavía no tiene PlaceId: créalo en Creator Hub y carga su ID en Places.json`)
		return false, "pendiente"
	end
	if RunService:IsStudio() then
		warn(`[Travel] TeleportService no funciona en Studio: el viaje a "{key}" se prueba en la experiencia publicada`)
		return false, "studio"
	end
	for _, player in players do
		player:SetAttribute("TravelFailed", nil)
		for _, callback in beforeTravel do
			local ok, err = pcall(callback, player, key)
			if not ok then
				warn(`[Travel] onBeforeTravel falló para {player.Name}: {err}`)
			end
		end
	end
	local data = options and options.data
	local teleportOptions = buildOptions(data, options and options.reserved, options and options.accessCode)
	local lastError: any = nil
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(function()
			return TeleportService:TeleportAsync(placeId, players, teleportOptions)
		end)
		if ok then
			local code = (result :: TeleportAsyncResult).ReservedServerAccessCode
			for _, player in players do
				pending[player] = {
					key = key,
					placeId = placeId,
					data = data,
					accessCode = if code ~= "" then code else options and options.accessCode,
					attempts = attempt,
				}
				Telemetry.custom(player, "travel", nil, { to = key })
			end
			return true, result
		end
		lastError = result
		if attempt < MAX_ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end
	for _, player in players do
		fail(player, key, tostring(lastError))
	end
	return false, lastError
end

-- Vuelve al place de inicio.
function Travel.toStart(players: { Player }, options: Options?): (boolean, any)
	return Travel.to(players, Place.start(), options)
end

-- Datos con los que llegó el jugador desde otro place. No son confiables: el cliente puede
-- verlos. Úsalos solo como pistas (qué mapa, qué partida) y valida cada valor.
function Travel.arrival(player: Player): { [string]: any }
	local data = player:GetJoinData().TeleportData
	return if type(data) == "table" then data else {}
end

-- Fallos tardíos: TeleportAsync puede terminar bien y fallar después. Se reintenta con espera.
TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
	local entry = pending[player]
	if not entry then
		return
	end
	local retryable = result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.Failure
	if not retryable or entry.attempts >= MAX_ATTEMPTS then
		fail(player, entry.key, `{result.Name}: {message}`)
		return
	end
	entry.attempts += 1
	task.delay(if result == Enum.TeleportResult.Flooded then FLOODED_DELAY else RETRY_DELAY, function()
		if player.Parent ~= Players then
			return
		end
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(entry.placeId, { player }, buildOptions(entry.data, false, entry.accessCode))
		end)
		if not ok then
			fail(player, entry.key, tostring(err))
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
end)

return Travel
