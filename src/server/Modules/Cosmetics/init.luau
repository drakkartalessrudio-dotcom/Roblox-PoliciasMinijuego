--[[
	Cosmetics · módulo core: skins, auras, estelas, cintas y distintivos que el jugador
	desbloquea y equipa. Guarda en la sección "cosmetics" (CosmeticData). Publica el
	equipamiento en atributos del jugador: Equipped_<slot> y Owns_<id> (booleano).

	El módulo solo lleva la propiedad y lo equipado; qué se ve lo decide el cliente y
	Game. Cobrar un cosmético también es de Game (le pasa a `buy` una función para cobrar).

	API:
	  Cosmetics.init(options)                  { spend(player, amount, sku) -> boolean }
	  Cosmetics.start()
	  Cosmetics.owns(player, cosmeticId)       -> boolean
	  Cosmetics.grant(player, cosmeticId, source) -> boolean true si es nuevo
	  Cosmetics.buy(player, cosmeticId)        -> (boolean, string?)
	  Cosmetics.equip(player, cosmeticId)      -> boolean (nil lo deja vacío con unequip)
	  Cosmetics.unequip(player, slot)          -> boolean
	  Cosmetics.changed                        Signal (player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Signal = require(ReplicatedStorage.Shared.Signal)
local CosmeticData = require(script.CosmeticData)

local Cosmetics = {}

Cosmetics.changed = Signal.new() :: Signal.Signal<Player>

local spend: (Player, number, string) -> boolean = function()
	return false
end

local SLOTS = { "skin", "aura", "trail", "badge", "cinta" }

local function publish(player: Player)
	local data = CosmeticData.get(player)
	if not data then
		return
	end
	for _, def in Catalog.cosmetics do
		player:SetAttribute(`Owns_{def.id}`, data.owned[def.id] ~= nil)
	end
	for _, slot in SLOTS do
		player:SetAttribute(`Equipped_{slot}`, data.equipped[slot] or "")
	end
	Cosmetics.changed:Fire(player)
end

function Cosmetics.init(options: { spend: (Player, number, string) -> boolean })
	spend = options.spend
end

function Cosmetics.start()
	local function onPlayerAdded(player: Player)
		if CosmeticData.waitUntilReady(player) then
			publish(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Cosmetics.owns(player: Player, cosmeticId: string): boolean
	return CosmeticData.owns(player, cosmeticId)
end

function Cosmetics.grant(player: Player, cosmeticId: string, source: string): boolean
	if not Catalog.cosmeticById[cosmeticId] then
		return false
	end
	local created = CosmeticData.grant(player, cosmeticId, source)
	if created then
		publish(player)
	end
	return created
end

function Cosmetics.buy(player: Player, cosmeticId: string): (boolean, string?)
	local def = Catalog.cosmeticById[cosmeticId]
	if not def or def.source ~= "shop" or def.cost <= 0 then
		return false, "unknown"
	end
	if CosmeticData.owns(player, cosmeticId) then
		return false, "owned"
	end
	if not spend(player, def.cost, `cosmetic_{cosmeticId}`) then
		return false, "funds"
	end
	if not CosmeticData.grant(player, cosmeticId, "shop") then
		return false, "data"
	end
	publish(player)
	return true, nil
end

function Cosmetics.equip(player: Player, cosmeticId: string): boolean
	local def = Catalog.cosmeticById[cosmeticId]
	if not def or not CosmeticData.owns(player, cosmeticId) then
		return false
	end
	if CosmeticData.equip(player, def.slot, cosmeticId) then
		publish(player)
		return true
	end
	return false
end

function Cosmetics.unequip(player: Player, slot: string): boolean
	if not table.find(SLOTS, slot) then
		return false
	end
	if CosmeticData.equip(player, slot, nil) then
		publish(player)
		return true
	end
	return false
end

return Cosmetics
