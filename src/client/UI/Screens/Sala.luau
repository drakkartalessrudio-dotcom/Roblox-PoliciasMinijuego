--[[
	Sala: el estado de la Sala de Entrenamiento (AFK activo) y el reto de check-in.

	Mientras el jugador entrena muestra el tiempo pagado de hoy y cuánto falta para el
	próximo check-in. El reto ("¿Sigues ahí?") pide tocar un ícono entre varios, en lugares
	que cambian cada vez: un clic automático en un punto fijo no lo resuelve. El servidor
	valida la respuesta y el tiempo; esta pantalla solo la muestra y la envía.

	Estado del jugador: AfkActive, AfkPaused, AfkReason, AfkUsed, AfkCap y AfkNextCheckIn.
	Mensajes: `afk_challenge` (del servidor) y `afk_answer` (intención).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(script.Parent.Parent:WaitForChild("Format"))

local Sala = {}

local CHOICES: { [string]: string } = {
	patata = "🥔 Patata",
	capibara = "🐹 Capibara",
	tiburon = "🦈 Tiburón",
	cafetera = "☕ Cafetera",
	banana = "🍌 Banana",
	estrella = "⭐ Estrella",
	helicoptero = "🚁 Helicóptero",
}

local REASONS: { [string]: string } = {
	checkin = "Responde el reto para seguir ganando",
	locked = "En pausa por errores: espera unos minutos",
	cap = "Tope diario alcanzado: puedes quedarte, pero ya no paga",
}

function Sala.mount(Kit: any)
	local player = Players.LocalPlayer

	local panel = Kit.panel(Kit.slot("bottom"))
	panel.Visible = false
	local label = Kit.label({ text = "", kind = "body", parent = panel, size = UDim2.fromOffset(420, 44) })

	local function render()
		local active = player:GetAttribute("AfkActive") == true
		local reason = player:GetAttribute("AfkReason")
		local used = player:GetAttribute("AfkUsed")
		local cap = player:GetAttribute("AfkCap")
		local nextCheck = player:GetAttribute("AfkNextCheckIn")
		used = if type(used) == "number" then used else 0
		cap = if type(cap) == "number" then cap else 0
		panel.Visible = active
		if not active then
			return
		end
		local progress = `{Format.minutes(used)} de {Format.minutes(cap)} hoy`
		if type(reason) == "string" and REASONS[reason] then
			label.Text = `Entrenando · {progress}\n{REASONS[reason]}`
		else
			label.Text = `Entrenando · {progress}\nPróximo check-in en {Format.clock(if type(nextCheck) == "number" then nextCheck else 0)}`
		end
	end
	for _, attribute in { "AfkActive", "AfkReason", "AfkUsed", "AfkCap", "AfkNextCheckIn" } do
		Kit.bindAttribute(player, attribute, render)
	end

	local modal = Kit.modal("¿Sigues ahí?")
	local prompt = Kit.label({ text = "", kind = "heading", parent = modal.content, size = UDim2.fromOffset(300, 36) })
	local field = Instance.new("Frame")
	field.Name = "Reto"
	field.BackgroundTransparency = 1
	field.Size = UDim2.fromOffset(280, 216)
	field.Parent = modal.content

	Net.on("afk_challenge", function(spec)
		if type(spec) ~= "table" or type(spec.options) ~= "table" then
			return
		end
		for _, child in field:GetChildren() do
			child:Destroy()
		end
		prompt.Text = `Toca: {CHOICES[spec.target] or spec.target}`
		-- Lugares al azar: dos columnas por cuatro filas.
		local slots = {}
		for slot = 0, 7 do
			table.insert(slots, slot)
		end
		for index = #slots, 2, -1 do
			local pick = math.random(1, index)
			slots[index], slots[pick] = slots[pick], slots[index]
		end
		for index, choice in spec.options do
			local slot = slots[index]
			local button = Kit.button({
				text = CHOICES[choice] or choice,
				variant = "secondary",
				parent = field,
				onActivated = function()
					Net.send("afk_answer", { id = spec.id, choice = choice })
					modal:close()
				end,
			})
			button.Size = UDim2.fromOffset(134, 48)
			button.Position = UDim2.fromOffset((slot % 2) * 144, (slot // 2) * 54)
		end
		modal:open()
	end)
end

return Sala
