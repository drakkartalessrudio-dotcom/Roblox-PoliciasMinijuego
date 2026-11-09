--[[
	Botón de compra rápida de vida extra. En PC funciona bien; en celular los
	jugadores dicen que "no se puede tocar" y que a veces compran sin querer al saltar.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local PRODUCT_ID = 0 -- pendiente: lo carga el usuario desde el Creator Hub

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "CompraRapida"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local buy = Instance.new("TextButton")
buy.Size = UDim2.fromOffset(120, 36)
buy.AnchorPoint = Vector2.new(1, 1)
buy.Position = UDim2.new(1, -20, 1, -40)
buy.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
buy.TextColor3 = Color3.fromRGB(255, 255, 255)
buy.Font = Enum.Font.Arial
buy.TextSize = 12
buy.Text = "+1 VIDA"
buy.Parent = gui

buy.MouseButton1Click:Connect(function()
	if PRODUCT_ID ~= 0 then
		MarketplaceService:PromptProductPurchase(player, PRODUCT_ID)
	end
end)
