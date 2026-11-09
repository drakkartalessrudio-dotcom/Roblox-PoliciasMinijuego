-- Compras con Robux: la bolsa de monedas.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Tuning)
local DataService = require(script.Parent.DataService)
local Telemetry = require(script.Parent.Telemetry)

local store = DataStoreService:GetDataStore("Minas")
local COIN_PACK = 0 -- ID pendiente

local ShopService = {}

function ShopService.start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local profile = player and DataService.get(player)
		if not profile or receipt.ProductId ~= COIN_PACK then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local amount = Tuning.get("Shop.CoinPack")
		profile.coins += amount
		player:SetAttribute("Coins", profile.coins)
		-- Guardar ya, para que la compra no se pierda.
		local ok = pcall(function()
			store:UpdateAsync("Player_" .. receipt.PlayerId, function(old)
				old = old or { coins = 0, pickaxe = "wood" }
				old.coins += amount
				return old
			end)
		end)
		if not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		Telemetry.economy(player, "source", "coins", amount, profile.coins, "IAP", "coin_pack")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return ShopService
