--[[
	HUD: nivel, checkpoint, mensaje inicial y botón de tienda (la tienda todavía no vende nada).
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(300, 40)
status.Position = UDim2.new(0.5, -150, 0, 6)
status.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
status.TextColor3 = Color3.fromRGB(200, 200, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 18
status.Text = "Nivel 1"
status.Parent = gui

local shopButton = Instance.new("TextButton")
shopButton.Size = UDim2.fromOffset(90, 30)
shopButton.Position = UDim2.fromOffset(10, 62)
shopButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
shopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
shopButton.Font = Enum.Font.Gotham
shopButton.TextSize = 14
shopButton.Text = "Tienda (B)"
shopButton.Parent = gui

local shop = Instance.new("Frame")
shop.Size = UDim2.fromOffset(400, 300)
shop.Position = UDim2.new(0.5, -200, 0.5, -150)
shop.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
shop.Visible = false
shop.Parent = gui

local soon = Instance.new("TextLabel")
soon.Size = UDim2.fromScale(1, 1)
soon.BackgroundTransparency = 1
soon.TextColor3 = Color3.fromRGB(120, 120, 120)
soon.Text = "Próximamente"
soon.Parent = shop

shopButton.MouseButton1Click:Connect(function()
	shop.Visible = not shop.Visible
end)

local function render()
	local level = player:GetAttribute("Level") or 1
	local count = player:GetAttribute("LevelCount") or 3
	status.Text = "Nivel " .. level .. "/" .. count .. " - Checkpoint " .. (player:GetAttribute("Checkpoint") or 0)
end
player:GetAttributeChangedSignal("Level"):Connect(render)
player:GetAttributeChangedSignal("Checkpoint"):Connect(render)
render()
