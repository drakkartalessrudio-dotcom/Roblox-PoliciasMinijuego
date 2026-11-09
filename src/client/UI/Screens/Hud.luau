--[[
	Hud: lo que importa en cada momento, en los bordes de la pantalla.

	  top      estrellas de búsqueda y estado, nivel y barra de XP
	  right    Dinero, Botín (con su tope), Cerebros, distrito y velocidad
	  bottom   pista del tutorial para quien empieza

	Solo presenta el estado que publica el servidor en atributos del jugador (Stars,
	WantedState, Level, Xp, XpNeeded, Dinero, Botin, BotinCap, Cerebros, District, Speed y
	TutorialStep; ver "Estado para la UI" en el GDD).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Style = require(Shared:WaitForChild("Style"))
local Format = require(script.Parent.Parent:WaitForChild("Format"))

local Hud = {}

local MAX_STARS = 6

local HINTS = {
	graffiti = "Acércate al muro que brilla y pulsa E (en el celular, toca el aviso) para pintar.",
	escape = "¡Un policía te vio! Corre: el Patata es más lento que tú. Escóndete en el arbusto resaltado.",
	deposit = "Vuelve a una Guarida (zona cian) y mantén el aviso para depositar tu Botín.",
	upgrade = "Abre la Tienda y compra tus primeras Zapatillas para correr más rápido.",
}

local LOBBY_START = "Estás en La Guarida, la zona segura. Entra al portal amarillo (Barrio Papa) para empezar tus travesuras."
local LOBBY_PLOT = "Reclama una parcela libre: camina hasta un pedestal y pulsa E. Con H abres La Guarida (viajes, logros y jugadores)."

local function stars(count: number): string
	local text = ""
	for index = 1, MAX_STARS do
		text ..= if index <= count then "★" else "☆"
	end
	return text
end

function Hud.mount(Kit: any)
	local player = Players.LocalPlayer

	-- Arriba: estrellas, estado y nivel.
	local top = Kit.panel(Kit.slot("top"))
	local starLabel = Kit.label({ text = stars(0), kind = "heading", color = "hazard", parent = top, size = UDim2.fromOffset(320, 38) })
	local stateLabel = Kit.label({ text = "", kind = "label", color = "textMuted", parent = top, size = UDim2.fromOffset(320, 22) })
	local levelLabel = Kit.label({ text = "Nivel 1", kind = "number", parent = top, size = UDim2.fromOffset(320, 28) })
	local barBack = Instance.new("Frame")
	barBack.Name = "XpBar"
	barBack.BackgroundColor3 = Style.color("panelAlt")
	barBack.BorderSizePixel = 0
	barBack.Size = UDim2.fromOffset(320, 10)
	barBack.Parent = top
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BackgroundColor3 = Style.color("accent")
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.Parent = barBack
	for _, bar in { barBack, barFill } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = bar
	end

	local function renderStars()
		local count = player:GetAttribute("Stars")
		local state = player:GetAttribute("WantedState")
		count = if type(count) == "number" then count else 0
		starLabel.Text = stars(count)
		stateLabel.Text = if state == "seen" then "¡Te están viendo!" elseif state == "searching" then "Te buscan… sigue escondido" else ""
	end
	Kit.bindAttribute(player, "Stars", renderStars)
	Kit.bindAttribute(player, "WantedState", renderStars)

	-- Las estrellas parpadean mientras te buscan (salvo con movimiento reducido).
	task.spawn(function()
		while true do
			task.wait(0.4)
			if player:GetAttribute("WantedState") == "searching" and not GuiService.ReducedMotionEnabled then
				starLabel.TextTransparency = if starLabel.TextTransparency > 0.2 then 0 else 0.6
			else
				starLabel.TextTransparency = 0
			end
		end
	end)

	local function renderLevel()
		local level = player:GetAttribute("Level")
		local xp = player:GetAttribute("Xp")
		local needed = player:GetAttribute("XpNeeded")
		if type(level) ~= "number" then
			levelLabel.Text = "Cargando…"
			return
		end
		if type(needed) == "number" and needed > 0 and type(xp) == "number" then
			levelLabel.Text = `Nivel {level} · {Format.number(xp)}/{Format.number(needed)} XP`
			barFill.Size = UDim2.fromScale(math.clamp(xp / needed, 0, 1), 1)
		else
			levelLabel.Text = `Nivel {level} (máximo)`
			barFill.Size = UDim2.fromScale(1, 1)
		end
	end
	for _, attribute in { "Level", "Xp", "XpNeeded" } do
		Kit.bindAttribute(player, attribute, renderLevel)
	end

	-- Derecha: dinero, botín y datos del momento.
	local right = Kit.panel(Kit.slot("right"))
	local moneyLabel = Kit.label({ text = "$0", kind = "number", color = "reward", parent = right, size = UDim2.fromOffset(190, 30) })
	local lootLabel = Kit.label({ text = "Botín 0/0", kind = "number", parent = right, size = UDim2.fromOffset(190, 28) })
	local brainsLabel = Kit.label({ text = "🧠 0", kind = "label", color = "reward", parent = right, size = UDim2.fromOffset(190, 24) })
	local districtLabel = Kit.label({ text = "", kind = "label", color = "textMuted", parent = right, size = UDim2.fromOffset(190, 24) })
	local speedLabel = Kit.label({ text = "", kind = "label", color = "textMuted", parent = right, size = UDim2.fromOffset(190, 24) })

	Kit.bindAttribute(player, "Dinero", function(value)
		moneyLabel.Text = Format.money(if type(value) == "number" then value else 0)
	end)
	Kit.bindAttribute(player, "Cerebros", function(value)
		brainsLabel.Text = `🧠 {Format.number(if type(value) == "number" then value else 0)}`
	end)
	local function renderLoot()
		local loot = player:GetAttribute("Botin")
		local cap = player:GetAttribute("BotinCap")
		loot = if type(loot) == "number" then loot else 0
		cap = if type(cap) == "number" then cap else 0
		lootLabel.Text = `Botín {Format.number(loot)}/{Format.number(cap)}`
		lootLabel.TextColor3 = Style.color(if cap > 0 and loot >= cap then "danger" else "text")
	end
	Kit.bindAttribute(player, "Botin", renderLoot)
	Kit.bindAttribute(player, "BotinCap", renderLoot)
	Kit.bindAttribute(player, "District", function(value)
		local district = if type(value) == "string" then Catalog.districts[value] else nil
		districtLabel.Text = if district then district.name else ""
	end)
	Kit.bindAttribute(player, "Speed", function(value)
		speedLabel.Text = if type(value) == "number" then `Velocidad {value}` else ""
	end)

	-- Abajo: la pista del tutorial y, en el lobby, qué hacer allí.
	local hintPanel = Kit.panel(Kit.slot("bottom"))
	local hintLabel = Kit.label({ text = "", kind = "body", parent = hintPanel, size = UDim2.fromOffset(420, 52) })
	local function renderHint()
		local step = player:GetAttribute("TutorialStep")
		local inTutorial = type(step) == "string" and step ~= ""
		local text: string? = nil
		if player:GetAttribute("District") == "lobby" then
			if inTutorial then
				text = LOBBY_START
			elseif player:GetAttribute("PlotId") == "" then
				text = LOBBY_PLOT
			end
		elseif inTutorial then
			text = HINTS[step :: string]
		end
		hintPanel.Visible = text ~= nil
		hintLabel.Text = text or ""
		if text and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			hintLabel.Text = (text:gsub("pulsa E %(en el celular, toca el aviso%)", "toca el aviso"):gsub("pulsa E", "toca el aviso"):gsub("Con H abres", "Con el botón La Guarida abres"))
		end
	end
	for _, attribute in { "TutorialStep", "District", "PlotId" } do
		Kit.bindAttribute(player, attribute, renderHint)
	end
end

return Hud
