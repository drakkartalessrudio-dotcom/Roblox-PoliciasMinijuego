--[[
	Shop: la tienda de la Guarida. Pestañas: Mejoras, Herramientas, Cosméticos y Robux.

	Solo muestra lo que decide el servidor (atributos Up_<id>, Tool_<id>, Owns_<id>,
	Equipped_<slot>, Pass_<key>, Dinero y Level) y envía intenciones (`buy_upgrade`,
	`buy_tool`, `buy_cosmetic`, `equip_cosmetic`, `unequip_cosmetic`, `shop_pass`,
	`shop_product`). El servidor valida que esté en una Guarida, el nivel y los fondos.

	El precio en Robux no se muestra aquí: lo muestra el aviso nativo de Roblox al comprar,
	con el precio regional del jugador. Las ofertas sin ID cargado salen como "Disponible
	pronto".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Net = require(Shared:WaitForChild("Net"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Format = require(script.Parent.Parent:WaitForChild("Format"))

local Shop = {}

local CELL = Vector2.new(190, 200)
local GRID_HEIGHT = 330

local PASSES = {
	{ key = "money2x", name = "Dinero ×2", description = "+100 % al bono de Dinero (se suma, no se multiplica)" },
	{ key = "aura_vip", name = "Aura Brainrot VIP", description = "Aura exclusiva y color de nombre" },
	{ key = "stash_extended", name = "Alijo extendido", description = "El alijo acumula hasta 240 min" },
	{ key = "phone", name = "Teléfono de Guarida", description = "Deposita a distancia si no te buscan" },
}
local PRODUCTS = {
	{ key = "pack_small", name = "Paquete chico", description = "Dinero para ≈ 30 min de juego" },
	{ key = "pack_medium", name = "Paquete mediano", description = "Dinero para ≈ 2 h de juego" },
	{ key = "pack_large", name = "Paquete grande", description = "Dinero para ≈ 8 h de juego" },
	{ key = "soborno", name = "Soborno", description = "Quita todas tus estrellas al instante" },
}

type Entry = { button: TextButton, status: TextLabel, update: () -> () }

function Shop.mount(Kit: any)
	local player = Players.LocalPlayer
	local modal = Kit.modal("Tienda")
	Kit.label({ text = "Las compras con Dinero se hacen en una Guarida", kind = "label", color = "textMuted", parent = modal.content, size = UDim2.fromOffset(560, 24) })
	local tabs = Kit.tabs(modal.content, { "Mejoras", "Herramientas", "Cosméticos", "Robux" })

	local entries: { Entry } = {}

	local function number(attribute: string): number
		local value = player:GetAttribute(attribute)
		return if type(value) == "number" then value else 0
	end

	local function card(grid: Instance, order: number, name: string, description: string): (TextLabel, TextButton)
		local frame = Kit.card(grid, order)
		Kit.label({ text = name, kind = "label", parent = frame, size = UDim2.new(1, 0, 0, 24) })
		Kit.label({ text = description, kind = "body", color = "textMuted", parent = frame, size = UDim2.new(1, 0, 0, 56) })
		local status = Kit.label({ text = "", kind = "number", color = "reward", parent = frame, size = UDim2.new(1, 0, 0, 24) })
		local button = Kit.button({ text = "…", variant = "primary", parent = frame, onActivated = function() end })
		button.Size = UDim2.new(1, 0, 0, 44)
		return status, button
	end

	-- Cada botón tiene una acción que cambia según el estado; solo se ejecuta si está habilitada.
	local handlers: { [TextButton]: () -> () } = {}

	local function setAction(button: TextButton, text: string, enabled: boolean, onActivated: () -> ())
		button.Text = text
		button.BackgroundTransparency = if enabled then 0 else 0.55
		if enabled then
			handlers[button] = onActivated
		else
			handlers[button] = nil
		end
	end

	local function connectAction(button: TextButton)
		button.Activated:Connect(function()
			local handler = handlers[button]
			if handler then
				handler()
			end
		end)
	end

	-- Mejoras.
	local upgradesGrid = Kit.grid(tabs.pages["Mejoras"], CELL, GRID_HEIGHT)
	for index, def in Catalog.upgrades do
		local status, button = card(upgradesGrid, index, def.name, def.description)
		connectAction(button)
		table.insert(entries, {
			button = button,
			status = status,
			update = function()
				local level = number(`Up_{def.id}`)
				local max = Catalog.upgradeMaxLevel(def.id)
				status.Text = `Nivel {level}/{max}`
				if level >= max then
					setAction(button, "Máximo", false, function() end)
				elseif def.group == "Sala" and number("Level") < Tuning.get("Afk.UnlockLevel") then
					setAction(button, `Desde el nivel {Tuning.get("Afk.UnlockLevel")}`, false, function() end)
				else
					local cost = Catalog.upgradeCost(def.id, level + 1)
					setAction(button, `Comprar {Format.money(cost)}`, number("Dinero") >= cost, function()
						Net.send("buy_upgrade", { id = def.id })
					end)
				end
			end,
		})
	end

	-- Herramientas.
	local toolsGrid = Kit.grid(tabs.pages["Herramientas"], CELL, GRID_HEIGHT)
	for index, def in Catalog.tools do
		local status, button = card(toolsGrid, index, def.name, def.description)
		connectAction(button)
		table.insert(entries, {
			button = button,
			status = status,
			update = function()
				local requiredLevel = Tuning.get(`Tools.{def.configKey}.Level`)
				local cost = Tuning.get(`Tools.{def.configKey}.Cost`)
				if player:GetAttribute(`Tool_{def.id}`) == true then
					status.Text = "Tuya"
					setAction(button, `Usar ({def.hotkey.Name})`, false, function() end)
				elseif number("Level") < requiredLevel then
					status.Text = `Nivel {requiredLevel}`
					setAction(button, "Bloqueada", false, function() end)
				else
					status.Text = Format.money(cost)
					setAction(button, "Comprar", number("Dinero") >= cost, function()
						Net.send("buy_tool", { id = def.id })
					end)
				end
			end,
		})
	end

	-- Cosméticos.
	local cosmeticsGrid = Kit.grid(tabs.pages["Cosméticos"], CELL, GRID_HEIGHT)
	for index, def in Catalog.cosmetics do
		local status, button = card(cosmeticsGrid, index, def.name, `Espacio: {def.slot}`)
		connectAction(button)
		table.insert(entries, {
			button = button,
			status = status,
			update = function()
				if player:GetAttribute(`Owns_{def.id}`) == true then
					if player:GetAttribute(`Equipped_{def.slot}`) == def.id then
						status.Text = "Puesto"
						setAction(button, "Quitar", true, function()
							Net.send("unequip_cosmetic", { slot = def.slot })
						end)
					else
						status.Text = "Tuyo"
						setAction(button, "Poner", true, function()
							Net.send("equip_cosmetic", { id = def.id })
						end)
					end
				elseif def.source == "shop" then
					status.Text = Format.money(def.cost)
					setAction(button, "Comprar", number("Dinero") >= def.cost, function()
						Net.send("buy_cosmetic", { id = def.id })
					end)
				elseif def.source == "gamepass" then
					status.Text = "Con el pase VIP"
					setAction(button, "Ver pases", true, function()
						tabs:select("Robux")
					end)
				else
					status.Text = "Con Ascensión"
					setAction(button, "Bloqueado", false, function() end)
				end
			end,
		})
	end

	-- Robux: pases y productos. Las ofertas sin ID dicen "Disponible pronto".
	local robuxGrid = Kit.grid(tabs.pages["Robux"], CELL, GRID_HEIGHT)
	local order = 0
	for _, offer in PASSES do
		order += 1
		local status, button = card(robuxGrid, order, offer.name, offer.description)
		connectAction(button)
		table.insert(entries, {
			button = button,
			status = status,
			update = function()
				if player:GetAttribute(`Pass_{offer.key}`) == true then
					status.Text = "Ya lo tienes"
					setAction(button, "Comprado", false, function() end)
				else
					status.Text = "Pase permanente"
					setAction(button, "Comprar", true, function()
						Net.send("shop_pass", { key = offer.key })
					end)
				end
			end,
		})
	end
	for _, offer in PRODUCTS do
		order += 1
		local status, button = card(robuxGrid, order, offer.name, offer.description)
		connectAction(button)
		table.insert(entries, {
			button = button,
			status = status,
			update = function()
				status.Text = "Se repite"
				setAction(button, "Comprar", number("Level") >= 1, function()
					Net.send("shop_product", { key = offer.key })
				end)
			end,
		})
	end
	Kit.status(tabs.pages["Robux"], "unavailable", "El precio se muestra al comprar. Las ofertas aún sin configurar dicen «Disponible pronto».")

	local dirty = false
	local function refresh()
		dirty = false
		for _, entry in entries do
			entry.update()
		end
	end
	player.AttributeChanged:Connect(function()
		if not dirty then
			dirty = true
			task.defer(refresh)
		end
	end)
	refresh()

	Kit.button({
		text = "Tienda",
		variant = "secondary",
		binding = { keyboard = Enum.KeyCode.B, gamepad = Enum.KeyCode.ButtonY },
		parent = Kit.slot("left"),
		onActivated = function()
			refresh()
			modal:open()
		end,
	})
end

return Shop
