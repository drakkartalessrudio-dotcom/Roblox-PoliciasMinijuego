--[[
	PlayerStats · cálculos de TravesurasBrainrot que mezclan varios cores: velocidad, poder
	de embestida, sigilo, capacidad de Botín, pérdida al arresto y bonos de Dinero y XP.
	Es lógica del juego (no de un core), por eso vive en Game.

	Regla de apilamiento (GDD, Estado y economía): los bonos permanentes y de evento se
	SUMAN y tienen un tope; el premio de riesgo (estrellas) multiplica aparte.

	  bono total = 1 + Ascensión + pase ×2 Dinero + banda (tope Economy.BonusCap)
	  velocidad  = base + nivel + Zapatillas + perk, tope MaxSpeed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Ascension = require(ServerScriptService.Server.Modules.Ascension)
local Band = require(ServerScriptService.Server.Modules.Band)
local Progress = require(ServerScriptService.Server.Modules.Progress)
local Shop = require(ServerScriptService.Server.Modules.Shop)
local Upgrades = require(ServerScriptService.Server.Modules.Upgrades)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)

local PlayerStats = {}

-- Clave del pase de Dinero ×2 y del alijo extendido en el catálogo de Shop.
PlayerStats.PASS_MONEY = "money2x"
PlayerStats.PASS_STASH = "stash_extended"

function PlayerStats.level(player: Player): number
	return Progress.level(player)
end

-- Velocidad de marcha antes de arena, herramientas y efectos de los policías.
function PlayerStats.baseSpeed(player: Player): number
	local speed = Tuning.get("Player.BaseWalkSpeed")
		+ Tuning.get("Player.SpeedPerLevel") * (Progress.level(player) - 1)
		+ Tuning.get("Upgrades.Zapatillas.SpeedPerLevel") * Upgrades.levelOf(player, "zapatillas")
		+ Tuning.get("Perks.PiesDeRayo.SpeedPerLevel") * Ascension.perkLevel(player, "pies_de_rayo")
	return math.min(speed, Tuning.get("Player.MaxSpeed"))
end

-- Poder de embestida: velocidad × (1 + 8 % × Fortachón).
function PlayerStats.power(player: Player): number
	return PlayerStats.baseSpeed(player) * (1 + Tuning.get("Upgrades.Fortachon.PowerPerLevel") * Upgrades.levelOf(player, "fortachon"))
end

-- Reducción de visión y ruido (0 a 0,8).
function PlayerStats.sigilo(player: Player): number
	local value = Tuning.get("Upgrades.Sigilo.ReductionPerLevel") * Upgrades.levelOf(player, "sigilo")
		+ Tuning.get("Perks.SigiloInnato.ReductionPerLevel") * Ascension.perkLevel(player, "sigilo_innato")
	return math.clamp(value, 0, 0.8)
end

-- Factor de duración de los minijuegos (Manos rápidas).
function PlayerStats.durationScale(player: Player): number
	return math.max(0.4, 1 - Tuning.get("Upgrades.Manos.TimeReductionPerLevel") * Upgrades.levelOf(player, "manos"))
end

function PlayerStats.decayBonus(player: Player): number
	return Tuning.get("Perks.SangreFria.DecayBonusPerLevel") * Ascension.perkLevel(player, "sangre_fria")
end

function PlayerStats.carryCap(player: Player): number
	return Tuning.get("Carry.BaseCap")
		+ Tuning.get("Carry.CapPerLevel") * Progress.level(player)
		+ Tuning.get("Carry.CapPerPocketLevel") * Upgrades.levelOf(player, "bolsillos")
end

-- Fracción del Botín que se pierde al ser arrestado con `stars` estrellas.
function PlayerStats.lossFraction(player: Player, stars: number): number
	local base = if stars >= 5 then Tuning.get("Arrest.LossPercentHighHeat") else Tuning.get("Arrest.LossPercent")
	return math.max(Tuning.get("Arrest.LossMin"), base - Tuning.get("Upgrades.Bolsillos.LossReductionPerLevel") * Upgrades.levelOf(player, "bolsillos"))
end

function PlayerStats.difficulty(player: Player): number
	return math.min(Tuning.get("Cops.DifficultyCap"), Tuning.get("Cops.DifficultyPerAscension") * Ascension.count(player))
end

-- Bono aditivo de Dinero. withBand = false para la Sala AFK (no recibe bono de banda).
function PlayerStats.moneyBonus(player: Player, withBand: boolean): number
	local total = 1 + Catalog.ascensionBonus(Ascension.count(player))
	if Shop.owns(player, PlayerStats.PASS_MONEY) then
		total += Tuning.get("Economy.PassMoneyBonus")
	end
	if withBand then
		total += Band.bonus(player)
	end
	return math.min(total, Tuning.get("Economy.BonusCap"))
end

-- Bono aditivo de XP: igual que el de Dinero, sin el pase.
function PlayerStats.xpBonus(player: Player, withBand: boolean): number
	local total = 1 + Catalog.ascensionBonus(Ascension.count(player))
	if withBand then
		total += Band.bonus(player)
	end
	return math.min(total, Tuning.get("Economy.BonusCap"))
end

-- Premio de riesgo: ×(1 + 0,4 × estrellas).
function PlayerStats.risk(player: Player): number
	return 1 + Tuning.get("Heat.RiskPayoutPerStar") * Wanted.stars(player)
end

function PlayerStats.starCap(player: Player): number
	return Catalog.starCap(Progress.level(player))
end

return PlayerStats
