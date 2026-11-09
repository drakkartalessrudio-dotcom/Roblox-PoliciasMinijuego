--[[
	Ascension · módulo core: el prestigio. Al llegar al nivel máximo y pagar la cuota,
	el jugador suma una Ascensión (multiplicador permanente de XP y Dinero), gana
	Cerebros y reinicia nivel, Dinero y mejoras. Los perks se compran con Cerebros y no
	se reinician. Guarda en la sección "ascension" (AscensionData).

	El core solo lleva la cuenta y los perks. Reiniciar el nivel, el Dinero y las mejoras
	es de los otros cores: Game conecta `Ascension.ascended` a sus funciones de reinicio, y
	como el evento se publica en el mismo tick que el cobro, el guardado ve todo o nada.

	Publica atributos del jugador: AscensionCount, AscensionBonus, AscensionFee y Perk_<id>.

	API:
	  Ascension.init(options)               { level(player), charge(player, fee), grantCerebros(player, n) -> boolean,
	                                          spendCerebros(player, n) -> boolean }
	  Ascension.start()
	  Ascension.count(player)               -> number
	  Ascension.perkLevel(player, perkId)   -> number
	  Ascension.canAscend(player)           -> (boolean, string?)
	  Ascension.ascend(player)              -> (boolean, string?)
	  Ascension.buyPerk(player, perkId)     -> (boolean, string?)
	  Ascension.markSixStar(player)         llegó a 6 estrellas en la carrera actual
	  Ascension.ascended                    Signal (player, nuevaCuenta, cerebrosGanados)
	  Ascension.perkChanged                 Signal (player, perkId, nivel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local AscensionData = require(script.AscensionData)

export type Options = {
	level: (player: Player) -> number,
	charge: (player: Player, fee: number) -> boolean,
	grantCerebros: (player: Player, amount: number) -> boolean,
	spendCerebros: (player: Player, amount: number) -> boolean,
}

local Ascension = {}

Ascension.ascended = Signal.new() :: Signal.Signal<Player, number, number>
Ascension.perkChanged = Signal.new() :: Signal.Signal<Player, string, number>

local options: Options? = nil

local function publish(player: Player)
	local count = AscensionData.count(player)
	player:SetAttribute("AscensionCount", count)
	player:SetAttribute("AscensionBonus", Catalog.ascensionBonus(count))
	player:SetAttribute("AscensionFee", if count >= Tuning.get("Ascension.Max") then 0 else Catalog.ascensionFee(count))
	for _, perk in Catalog.perks do
		player:SetAttribute(`Perk_{perk.id}`, AscensionData.perkLevel(player, perk.id))
	end
end

function Ascension.init(opts: Options)
	options = opts
end

function Ascension.start()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("AscensionCount", 0)
		player:SetAttribute("AscensionBonus", 0)
		player:SetAttribute("AscensionFee", Catalog.ascensionFee(0))
		if AscensionData.waitUntilReady(player) then
			publish(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Ascension.count(player: Player): number
	return AscensionData.count(player)
end

function Ascension.perkLevel(player: Player, perkId: string): number
	return AscensionData.perkLevel(player, perkId)
end

function Ascension.canAscend(player: Player): (boolean, string?)
	assert(options, "Ascension.init no se llamó")
	local count = AscensionData.count(player)
	if count >= Tuning.get("Ascension.Max") then
		return false, "max"
	end
	if options.level(player) < Tuning.get("Ascension.MinLevel") then
		return false, "level"
	end
	return true, nil
end

function Ascension.markSixStar(player: Player)
	if not AscensionData.reachedSixStar(player) then
		AscensionData.markSixStar(player)
	end
end

function Ascension.ascend(player: Player): (boolean, string?)
	assert(options, "Ascension.init no se llamó")
	local can, reason = Ascension.canAscend(player)
	if not can then
		return false, reason
	end
	local count = AscensionData.count(player)
	local cerebros = Tuning.get("Ascension.CerebrosBase")
	if AscensionData.reachedSixStar(player) then
		cerebros += Tuning.get("Ascension.CerebrosSixStar")
	end
	if not options.charge(player, Catalog.ascensionFee(count)) then
		return false, "funds"
	end
	-- Desde aquí no hay esperas: la Ascensión se aplica entera en este tick.
	local newCount = AscensionData.advance(player, Tuning.get("Ascension.Max"))
	if not newCount then
		return false, "data"
	end
	options.grantCerebros(player, cerebros)
	publish(player)
	Ascension.ascended:Fire(player, newCount, cerebros)
	return true, nil
end

function Ascension.buyPerk(player: Player, perkId: string): (boolean, string?)
	assert(options, "Ascension.init no se llamó")
	if not Catalog.perkById[perkId] then
		return false, "unknown"
	end
	local current = AscensionData.perkLevel(player, perkId)
	local costs = Tuning.get("Perks.CostByLevel")
	if current >= #costs then
		return false, "max"
	end
	if not options.spendCerebros(player, costs[current + 1]) then
		return false, "funds"
	end
	if not AscensionData.setPerk(player, perkId, current + 1) then
		return false, "data"
	end
	publish(player)
	Ascension.perkChanged:Fire(player, perkId, current + 1)
	return true, nil
end

return Ascension
