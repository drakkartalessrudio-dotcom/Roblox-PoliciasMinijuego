--!strict
--[[
	PlayerData · plantilla de roblox-data-architect. Cópiala sin cambios a src/server/Data/.

	El único servicio de datos del juego. Carga el perfil de cada jugador con bloqueo de
	sesión, lo migra y lo completa según DataSchema.json, lo guarda cada AUTOSAVE
	segundos (si cambió), al salir, al cerrar el servidor y antes de un viaje, y nunca
	guarda encima de un perfil que no pudo cargar. Cada core lee y escribe solo su
	sección, desde la fachada de su dominio:

	  local quests = PlayerData.section(player, "quests")
	  local data = quests:get()                -- copia de solo lectura; nil si no está listo
	  local ok = quests:update(function(draft) -- false si no está listo o rompe el esquema
	      draft.completed[questId] = os.time()
	  end)

	API:
	  PlayerData.start()                           una vez, en Bootstrap, antes de Game.start
	  PlayerData.status(player)                    "loading" | "ready" | "unavailable" y el motivo
	  PlayerData.waitUntilReady(player, timeout?)  true si quedó listo
	  PlayerData.section(player, nombre)           get() y update(fn)
	  PlayerData.changed(nombre)                   Signal (player, copia) al cambiar esa sección
	  PlayerData.onLoaded / PlayerData.onReleased  Signal (player)
	  PlayerData.save(player)                      guarda ya si hay cambios (antes de un viaje)
	  PlayerData.grantPurchase(player, purchaseId, grant)   para ProcessReceipt
	  PlayerData.mode()                            "persistent" o "memory"

	El atributo DataStatus del jugador repite el estado para la UI ("Cargando tu
	progreso" o "Tu progreso no se puede guardar ahora").

	En Studio sin acceso a las APIs (Game Settings → Security), un esquema persistent
	usa memoria y avisa en el Output: el juego se puede probar, pero nada queda guardado.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))
local Migrations = require("./Migrations")
local Session = require("./Session")
local Store = require("./Store")

local Schema: any = require(script.Parent:WaitForChild("DataSchema"))

local AUTOSAVE = 180 -- segundos entre guardados de un jugador con cambios
local AUTOSAVE_CHECK = 5 -- cada cuánto se revisa a quién le toca
local MIN_BUDGET = 10 -- pedidos de UpdateAsync que se reservan para cargas y salidas
local CLOSE_TIMEOUT = 25 -- BindToClose tiene 30 segundos
local STUDIO_NO_API = { "StudioAccessToApisNotAllowed", "publish this place", "API Services", "API access" }

export type Section = {
	get: (self: Section) -> any,
	update: (self: Section, fn: (draft: any) -> ()) -> (boolean, string?),
}

local PlayerData = {}

PlayerData.onLoaded = Signal.new() :: Signal.Signal<Player>
PlayerData.onReleased = Signal.new() :: Signal.Signal<Player>

local session: any = nil
local store: any = nil
local mode = "memory"
local started = false
local nextSave: { [Player]: number } = {}
local signals: { [string]: Signal.Signal<Player, any> } = {}

local function log(message: string)
	warn("[PlayerData]", message)
end

local function studioWithoutApi(): boolean
	if not RunService:IsStudio() then
		return false
	end
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(Schema.document.store):GetAsync("__studio_probe")
	end)
	if ok then
		return false
	end
	for _, fragment in STUDIO_NO_API do
		if string.find(tostring(err), fragment, 1, true) then
			return true
		end
	end
	return false
end

local function setStatus(player: Player)
	local status = session:status(player.UserId)
	player:SetAttribute("DataStatus", status)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("DataStatus", "loading")
	local status, reason = session:load(player.UserId)
	if player.Parent ~= Players then
		session:release(player.UserId)
		return
	end
	setStatus(player)
	if status == "ready" then
		nextSave[player] = os.clock() + AUTOSAVE * (0.5 + math.random() * 0.5)
		PlayerData.onLoaded:Fire(player)
	else
		log(`el perfil de {player.Name} ({player.UserId}) no está disponible: {reason}`)
	end
end

local function onPlayerRemoving(player: Player)
	nextSave[player] = nil
	session:release(player.UserId)
	PlayerData.onReleased:Fire(player)
end

local function autosave()
	while true do
		task.wait(AUTOSAVE_CHECK)
		local now = os.clock()
		for player, at in nextSave do
			if now >= at and store:budget() > MIN_BUDGET then
				nextSave[player] = now + AUTOSAVE
				task.spawn(function()
					session:save(player.UserId)
					setStatus(player)
				end)
			end
		end
	end
end

local function onClose()
	local pending = 0
	for _, userId in session:players() do
		pending += 1
		task.spawn(function()
			session:release(userId)
			pending -= 1
		end)
	end
	local deadline = os.clock() + CLOSE_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function PlayerData.start()
	if started then
		return
	end
	started = true
	mode = Schema.document.persistence
	if mode == "persistent" and studioWithoutApi() then
		mode = "memory"
		warn("[PlayerData] Studio sin acceso a las APIs: los datos se guardan solo en memoria. "
			.. "Actívalo en Game Settings → Security para probar el guardado real.")
	end
	store = if mode == "persistent" then Store.dataStore(Schema.document.store) else Store.memory()
	session = Session.new({
		store = store,
		schema = Schema,
		migrations = Migrations,
		jobId = (if game.JobId ~= "" then game.JobId else "studio") .. ":" .. HttpService:GenerateGUID(false),
		now = os.time,
		sleep = function(seconds: number)
			task.wait(seconds)
		end,
		log = log,
		encode = function(value: any): string
			return HttpService:JSONEncode(value)
		end,
	})
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(onClose)
	task.spawn(autosave)
end

function PlayerData.mode(): string
	return mode
end

function PlayerData.status(player: Player): (string?, string?)
	assert(session, "llama a PlayerData.start() en Bootstrap")
	return session:status(player.UserId)
end

-- Espera a que termine la carga. true si el perfil quedó listo.
function PlayerData.waitUntilReady(player: Player, timeout: number?): boolean
	assert(session, "llama a PlayerData.start() en Bootstrap")
	local deadline = os.clock() + (timeout or 60)
	while player.Parent == Players and os.clock() < deadline do
		local status = session:status(player.UserId)
		if status == "ready" then
			return true
		elseif status == "unavailable" then
			return false
		end
		task.wait(0.1)
	end
	return false
end

function PlayerData.changed(name: string): Signal.Signal<Player, any>
	assert(Schema.sections[name], `la sección {name} no existe en DataSchema`)
	local signal = signals[name]
	if not signal then
		signal = Signal.new() :: Signal.Signal<Player, any>
		signals[name] = signal
	end
	return signal
end

function PlayerData.section(player: Player, name: string): Section
	assert(session, "llama a PlayerData.start() en Bootstrap")
	assert(Schema.sections[name], `la sección {name} no existe en DataSchema`)
	local section = {}
	function section.get(_self: Section): any
		return session:get(player.UserId, name)
	end
	function section.update(_self: Section, fn: (draft: any) -> ()): (boolean, string?)
		local ok, err = session:update(player.UserId, name, fn)
		if ok then
			local signal = signals[name]
			if signal then
				signal:Fire(player, session:get(player.UserId, name))
			end
		end
		return ok, err
	end
	return section :: Section
end

function PlayerData.save(player: Player): boolean
	assert(session, "llama a PlayerData.start() en Bootstrap")
	local ok = session:save(player.UserId)
	setStatus(player)
	return ok
end

--[[
	Para el ProcessReceipt del módulo de Developer Products. grant aplica el beneficio con
	la API de los cores y devuelve true. El PurchaseId se registra en la misma escritura
	que el beneficio; si no se pudo guardar, Roblox reintenta y no se entrega dos veces.
]]
function PlayerData.grantPurchase(player: Player, purchaseId: string, grant: () -> boolean): Enum.ProductPurchaseDecision
	if not PlayerData.waitUntilReady(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local result = session:grantPurchase(player.UserId, purchaseId, grant)
	setStatus(player)
	return if result == "granted" then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Para DataDebug (solo Studio).
function PlayerData.debugSession(): any
	assert(RunService:IsStudio(), "DataDebug solo funciona en Studio")
	return session
end

return PlayerData
