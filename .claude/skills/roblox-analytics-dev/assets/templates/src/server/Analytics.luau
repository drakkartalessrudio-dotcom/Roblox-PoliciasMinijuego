--[[
	Analytics · plantilla de roblox-analytics-dev.

	Implementa la API de Telemetry (mismos nombres y argumentos) con AnalyticsService.
	Telemetry valida los argumentos y reenvía aquí cada evento; este módulo aplica el
	esquema del juego (AnalyticsSchema.json), el presupuesto de frecuencia y las reglas
	de la plataforma:

	  - AnalyticsService solo registra eventos enviados desde el servidor en experiencias
	    publicadas. En Studio no se envía nada; con el atributo Debug en true se imprime
	    lo que se enviaría.
	  - El límite global es 120 + 20 × CCU solicitudes por minuto. Cada servidor gasta
	    como máximo budgetPerPlayerPerMinute (20) por jugador presente, así la suma de
	    todos los servidores queda dentro del límite.
	  - Solo se envían nombres declarados en el esquema: protege los límites de 100
	    eventos propios, 10 funnels y 10 monedas, y evita errores de tipeo silenciosos.

	Cópialo tal cual; lo propio de cada juego va en AnalyticsSchema.json.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Schema: any = require(script.Parent:WaitForChild("AnalyticsSchema"))

local Analytics = {}

local IS_STUDIO = RunService:IsStudio()
local PER_PLAYER_PER_MINUTE = tonumber(Schema.budgetPerPlayerPerMinute) or 20

local function toSet(list: any): { [string]: boolean }
	local set = {}
	if type(list) == "table" then
		for _, name in list do
			set[name] = true
		end
	end
	return set
end

local currencies = toSet(Schema.currencies)
local funnels = toSet(Schema.funnels)
local progressionPaths = toSet(Schema.progressionPaths)
local customEvents = toSet(Schema.customEvents)

-- El esquema guarda ranura → dimensión ("CustomField01": "level"); el código necesita lo inverso.
local slotForDimension: { [string]: string } = {}
if type(Schema.customFields) == "table" then
	for slot, dimension in Schema.customFields do
		slotForDimension[dimension] = slot
	end
end

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[Analytics] {message}`)
	end
end

local function declared(set: { [string]: boolean }, kind: string, name: string): boolean
	if set[name] then
		return true
	end
	warnOnce(`{kind}:{name}`, `{kind} "{name}" no está en AnalyticsSchema.json; se descarta`)
	return false
end

local windowStart = os.clock()
local sentInWindow = 0
local droppedInWindow = 0

local function withinBudget(): boolean
	local now = os.clock()
	if now - windowStart >= 60 then
		if droppedInWindow > 0 then
			warn(`[Analytics] {droppedInWindow} eventos descartados por el presupuesto del último minuto`)
		end
		windowStart = now
		sentInWindow = 0
		droppedInWindow = 0
	end
	local budget = math.max(#Players:GetPlayers(), 1) * PER_PLAYER_PER_MINUTE
	if sentInWindow >= budget then
		droppedInWindow += 1
		return false
	end
	sentInWindow += 1
	return true
end

local function send(label: string, log: () -> ())
	if script:GetAttribute("Debug") == true then
		print("[Analytics]", label)
	end
	if IS_STUDIO or not withinBudget() then
		return
	end
	local ok, err = pcall(log)
	if not ok then
		warn(`[Analytics] {label} falló: {err}`)
	end
end

local function toCustomFields(fields: { [string]: any }?): { [string]: string }?
	if type(fields) ~= "table" then
		return nil
	end
	local result = {}
	for dimension, value in fields do
		local slot = slotForDimension[dimension]
		if slot then
			result[slot] = tostring(value)
		else
			warnOnce(`campo:{dimension}`, `el campo "{dimension}" no tiene ranura en AnalyticsSchema.json; se ignora`)
		end
	end
	return if next(result) then result else nil
end

function Analytics.onboarding(player: Player, step: number, stepName: string)
	send(`onboarding {step} {stepName}`, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

function Analytics.funnel(player: Player, funnelName: string, step: number, stepName: string, sessionId: string?)
	if not declared(funnels, "funnel", funnelName) then
		return
	end
	send(`funnel {funnelName} {step} {stepName}`, function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName)
	end)
end

function Analytics.progressionStart(player: Player, pathName: string, level: number, levelName: string?)
	if not declared(progressionPaths, "camino", pathName) then
		return
	end
	send(`progressionStart {pathName} {level}`, function()
		AnalyticsService:LogProgressionStartEvent(player, pathName, level, levelName)
	end)
end

function Analytics.progressionComplete(player: Player, pathName: string, level: number, levelName: string?)
	if not declared(progressionPaths, "camino", pathName) then
		return
	end
	send(`progressionComplete {pathName} {level}`, function()
		AnalyticsService:LogProgressionCompleteEvent(player, pathName, level, levelName)
	end)
end

function Analytics.progressionFail(player: Player, pathName: string, level: number, levelName: string?)
	if not declared(progressionPaths, "camino", pathName) then
		return
	end
	send(`progressionFail {pathName} {level}`, function()
		AnalyticsService:LogProgressionFailEvent(player, pathName, level, levelName)
	end)
end

function Analytics.economy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?
)
	if not declared(currencies, "moneda", currency) then
		return
	end
	local flowType = if flow == "source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	send(`economy {flow} {amount} {currency} {transactionType}`, function()
		AnalyticsService:LogEconomyEvent(player, flowType, currency, amount, endingBalance, transactionType, itemSku)
	end)
end

function Analytics.custom(player: Player, eventName: string, value: number?, fields: { [string]: string }?)
	if not declared(customEvents, "evento", eventName) then
		return
	end
	local customFields = toCustomFields(fields)
	send(`custom {eventName} {value or 1}`, function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
	end)
end

return Analytics
