--[[
	Shop · módulo core: las compras con Robux. Un único ProcessReceipt para los Developer
	Products (paquetes de Dinero, Soborno, Fianza) y la propiedad de los Game Passes
	(Dinero ×2, Aura VIP, Alijo extendido, Teléfono de Guarida).

	Reglas (roblox-monetization-developer-products y roblox-monetization-game-passes):
	  · La entrega de un producto se confirma solo con ProcessReceipt, y el beneficio y el
	    PurchaseId se guardan juntos con PlayerData.grantPurchase (sección "purchases").
	  · El cliente pide una CLAVE de oferta; el servidor resuelve el catálogo. Nunca acepta
	    precio, cantidad ni confirmación de compra del cliente.
	  · La propiedad de un pase se consulta a Roblox con UserOwnsGamePassAsync (pcall,
	    reintentos y caché de sesión). Un fallo de red es "unavailable", no "not-owned".
	  · Una oferta con ID 0 está pendiente: no se puede comprar (no se inventan IDs).

	No sabe qué da cada compra: Game pasa el catálogo con una función `grant` por producto.

	API:
	  Shop.init(options)                     { products, passes }
	  Shop.start()
	  Shop.requestProduct(player, key)       -> (boolean, string?) abre el prompt nativo
	  Shop.requestPass(player, key)          -> (boolean, string?)
	  Shop.owns(player, passKey)             -> boolean
	  Shop.passState(player, passKey)        -> "loading" | "owned" | "not-owned" | "unavailable"
	  Shop.available(key)                    -> boolean (ID real cargado)
	  Shop.productGranted                    Signal (player, key)
	  Shop.passChanged                       Signal (player, key, owned)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)

export type Product = {
	productId: number, -- 0 = pendiente
	grant: (player: Player) -> boolean,
}
export type Pass = {
	passId: number, -- 0 = pendiente
}
export type Options = {
	products: { [string]: Product },
	passes: { [string]: Pass },
}

local Shop = {}

Shop.productGranted = Signal.new() :: Signal.Signal<Player, string>
Shop.passChanged = Signal.new() :: Signal.Signal<Player, string, boolean>

local products: { [string]: Product } = {}
local passes: { [string]: Pass } = {}
local productKeyById: { [number]: string } = {}
local passKeyById: { [number]: string } = {}
local states: { [Player]: { [string]: string } } = {}

local ATTEMPTS = 3

local function publish(player: Player, key: string)
	player:SetAttribute(`Pass_{key}`, states[player] and states[player][key] == "owned")
end

local function checkPass(player: Player, key: string)
	local pass = passes[key]
	if pass.passId == 0 then
		states[player][key] = "not-owned"
		publish(player, key)
		return
	end
	local state = "unavailable"
	for attempt = 1, ATTEMPTS do
		local ok, owned = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.passId)
		end)
		if ok then
			state = if owned then "owned" else "not-owned"
			break
		end
		if attempt < ATTEMPTS then
			task.wait(2 * attempt)
		end
	end
	if player.Parent ~= Players then
		return
	end
	local previous = states[player][key]
	states[player][key] = state
	publish(player, key)
	if (state == "owned") ~= (previous == "owned") then
		Shop.passChanged:Fire(player, key, state == "owned")
	end
end

function Shop.init(options: Options)
	products = options.products
	passes = options.passes
	productKeyById = {}
	passKeyById = {}
	for key, product in products do
		if product.productId ~= 0 then
			productKeyById[product.productId] = key
		end
	end
	for key, pass in passes do
		if pass.passId ~= 0 then
			passKeyById[pass.passId] = key
		end
	end
end

function Shop.start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local key = productKeyById[receipt.ProductId]
		if not key then
			warn(`[Shop] recibo de un producto desconocido ({receipt.ProductId}); queda pendiente`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local decision = PlayerData.grantPurchase(player, tostring(receipt.PurchaseId), function()
			return products[key].grant(player)
		end)
		if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
			Shop.productGranted:Fire(player, key)
		end
		return decision
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		local key = passKeyById[passId]
		if key and wasPurchased and states[player] then
			task.spawn(checkPass, player, key)
		end
	end)

	local function onPlayerAdded(player: Player)
		states[player] = {}
		for key in passes do
			states[player][key] = "loading"
			player:SetAttribute(`Pass_{key}`, false)
		end
		for key in passes do
			task.spawn(checkPass, player, key)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Shop.available(key: string): boolean
	local product, pass = products[key], passes[key]
	return (product ~= nil and product.productId ~= 0) or (pass ~= nil and pass.passId ~= 0)
end

function Shop.passState(player: Player, key: string): string
	return if states[player] then states[player][key] or "unavailable" else "unavailable"
end

function Shop.owns(player: Player, key: string): boolean
	return Shop.passState(player, key) == "owned"
end

function Shop.requestProduct(player: Player, key: string): (boolean, string?)
	local product = products[key]
	if not product then
		return false, "unknown"
	end
	if product.productId == 0 then
		return false, "pending"
	end
	if PlayerData.status(player) ~= "ready" then
		return false, "data" -- sin perfil guardable no se abren compras nuevas
	end
	MarketplaceService:PromptProductPurchase(player, product.productId)
	return true, nil
end

function Shop.requestPass(player: Player, key: string): (boolean, string?)
	local pass = passes[key]
	if not pass then
		return false, "unknown"
	end
	if pass.passId == 0 then
		return false, "pending"
	end
	if Shop.owns(player, key) then
		return false, "owned"
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.passId)
	return true, nil
end

return Shop
