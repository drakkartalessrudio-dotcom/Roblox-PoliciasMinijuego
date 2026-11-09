--[[
	Hud: interfaz mínima del builder (el juego no activa design.ui). Solo muestra el
	estado que publica el servidor en atributos del jugador: monedas, gemas, racha,
	misiones activas y el estado de los datos. No envía nada al servidor.

	Va arriba a la derecha, dentro de ScreenInsets.CoreUISafeInsets: no tapa el chat
	(arriba a la izquierda) ni los controles táctiles (abajo).
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local screen = Instance.new("ScreenGui")
screen.Name = "Hud"
screen.ResetOnSpawn = false
screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 12)
panel.Size = UDim2.fromOffset(280, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(30, 28, 24)
panel.BackgroundTransparency = 0.25
panel.Parent = screen

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = panel

local function label(order: number): TextLabel
	local text = Instance.new("TextLabel")
	text.LayoutOrder = order
	text.Size = UDim2.new(1, 0, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(245, 236, 220)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextWrapped = true
	text.TextSize = 18
	text.Parent = panel
	return text
end

local wallet = label(1)
local streak = label(2)
local quests = label(3)
local status = label(4)

local function render()
	wallet.Text = `Monedas: {player:GetAttribute("Coins") or 0}   Gemas: {player:GetAttribute("Gems") or 0}`
	streak.Text = `Racha diaria: {player:GetAttribute("DailyStreak") or 0}`
	quests.Text = tostring(player:GetAttribute("QuestSummary") or "Cargando misiones…")
	local dataStatus = player:GetAttribute("DataStatus")
	status.Visible = dataStatus ~= "ready"
	status.Text = if dataStatus == "unavailable"
		then "Tu progreso no se puede guardar ahora"
		else "Cargando tu progreso…"
end

for _, name in { "Coins", "Gems", "DailyStreak", "QuestSummary", "DataStatus" } do
	player:GetAttributeChangedSignal(name):Connect(render)
end
render()
screen.Parent = player:WaitForChild("PlayerGui")
