--[[
	Telemetry · plantilla del contrato de la fábrica (roblox-game-builder).

	Fachada de eventos del juego. El código del servidor llama a estas funciones en
	los momentos que define references/hooks.md, con los nombres del GDD. Si existe
	el módulo Analytics (roblox-analytics-dev) en esta misma carpeta, cada llamada
	válida se reenvía a la función del mismo nombre; si no existe, no hace nada.
	Un error de analíticas nunca interrumpe el juego.

	Para ver los eventos en el Output de Studio, agrega a este ModuleScript el
	atributo booleano Debug con valor true.
]]

local Players = game:GetService("Players")

local Telemetry = {}

local analytics: any = nil
do
	local module = script.Parent:FindFirstChild("Analytics")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			analytics = result
		else
			warn("[Telemetry] No se pudo cargar Analytics:", result)
		end
	end
end

local function forward(name: string, ...: any)
	if script:GetAttribute("Debug") == true then
		print("[Telemetry]", name, ...)
	end
	if not analytics then
		return
	end
	local handler = analytics[name]
	if type(handler) ~= "function" then
		return
	end
	local ok, err = pcall(handler, ...)
	if not ok then
		warn(`[Telemetry] Analytics.{name} falló: {err}`)
	end
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function isText(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isStep(value: any): boolean
	return type(value) == "number" and value >= 1 and value % 1 == 0
end

local function reject(name: string, expected: string)
	warn(`[Telemetry] {name} descartado: se espera {expected}`)
end

local onboardingSent: { [Player]: { [number]: boolean } } = {}

Players.PlayerRemoving:Connect(function(player)
	onboardingSent[player] = nil
end)

-- Paso del funnel de onboarding del GDD. Se envía una sola vez por jugador y sesión,
-- aunque el momento se repita (por ejemplo, al reaparecer).
function Telemetry.onboarding(player: Player, step: number, stepName: string)
	if not (isPlayer(player) and isStep(step) and isText(stepName)) then
		reject("onboarding", "(player, paso entero >= 1, nombre)")
		return
	end
	local sent = onboardingSent[player]
	if not sent then
		sent = {}
		onboardingSent[player] = sent
	end
	if sent[step] then
		return
	end
	sent[step] = true
	forward("onboarding", player, step, stepName)
end

-- Paso de otro funnel del GDD (tienda, tutorial opcional, etc.).
function Telemetry.funnel(player: Player, funnelName: string, step: number, stepName: string, sessionId: string?)
	if not (isPlayer(player) and isText(funnelName) and isStep(step) and isText(stepName)) then
		reject("funnel", "(player, funnel, paso entero >= 1, nombre[, sesión])")
		return
	end
	forward("funnel", player, funnelName, step, stepName, sessionId)
end

local function progression(name: string, player: Player, pathName: string, level: number, levelName: string?)
	if not (isPlayer(player) and isText(pathName) and isStep(level)) then
		reject(name, "(player, camino, nivel entero >= 1[, nombre])")
		return
	end
	forward(name, player, pathName, level, levelName)
end

-- Inicio, final y fallo de un nivel o hito de un camino de progresión del GDD.
function Telemetry.progressionStart(player: Player, pathName: string, level: number, levelName: string?)
	progression("progressionStart", player, pathName, level, levelName)
end

function Telemetry.progressionComplete(player: Player, pathName: string, level: number, levelName: string?)
	progression("progressionComplete", player, pathName, level, levelName)
end

function Telemetry.progressionFail(player: Player, pathName: string, level: number, levelName: string?)
	progression("progressionFail", player, pathName, level, levelName)
end

-- Movimiento de moneda ya aplicado por el servidor: flow "source" (ganancia) o "sink" (gasto).
function Telemetry.economy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?
)
	local valid = isPlayer(player)
		and (flow == "source" or flow == "sink")
		and isText(currency)
		and type(amount) == "number"
		and amount > 0
		and type(endingBalance) == "number"
		and isText(transactionType)
	if not valid then
		reject("economy", '(player, "source" o "sink", moneda, cantidad > 0, saldo final, tipo[, sku])')
		return
	end
	forward("economy", player, flow, currency, amount, endingBalance, transactionType, itemSku)
end

-- Evento propio con nombre estable en snake_case y valor numérico opcional.
function Telemetry.custom(player: Player, eventName: string, value: number?, fields: { [string]: string }?)
	if not (isPlayer(player) and isText(eventName)) or (value ~= nil and type(value) ~= "number") then
		reject("custom", "(player, nombre[, valor numérico[, campos]])")
		return
	end
	forward("custom", player, eventName, value, fields)
end

return Telemetry
