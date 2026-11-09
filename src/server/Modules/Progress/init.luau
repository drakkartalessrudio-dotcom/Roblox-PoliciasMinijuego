--[[
	Progress · módulo core: nivel (1 a MaxLevel), XP hacia el siguiente nivel y banderas
	con fecha de hitos y onboarding. Guarda en la sección "progress" (ProgressData) y
	publica el estado para la UI en atributos del jugador.

	No sabe por qué se gana XP: lo deciden los puentes y Game.

	API:
	  Progress.init()
	  Progress.start()                       publica nivel y XP al cargar cada perfil
	  Progress.addXp(player, amount)         -> number? nivel nuevo (nil si el perfil no está listo)
	  Progress.level(player)                 -> number
	  Progress.xpNeeded(player)              -> number XP para el siguiente nivel
	  Progress.setFlag(player, id)           -> boolean true si es nueva
	  Progress.hasFlag(player, id)           -> boolean
	  Progress.reset(player)                 vuelve al nivel 1 (Ascensión)
	  Progress.leveledUp                     Signal (player, nivelNuevo)
	  Progress.loaded                        Signal (player) cuando el perfil quedó listo
	  Progress.flagSet                       Signal (player, flagId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local ProgressData = require(script.ProgressData)

local Progress = {}

Progress.leveledUp = Signal.new() :: Signal.Signal<Player, number>
Progress.loaded = Signal.new() :: Signal.Signal<Player>
Progress.flagSet = Signal.new() :: Signal.Signal<Player, string>

local ready: { [Player]: boolean } = {}

local function publish(player: Player)
	local level = ProgressData.level(player)
	player:SetAttribute("Level", level)
	player:SetAttribute("Xp", ProgressData.xp(player))
	player:SetAttribute("XpNeeded", if level >= Tuning.get("Progress.MaxLevel") then 0 else Catalog.xpToNext(level))
end

function Progress.init() end

function Progress.start()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("Level", 1)
		player:SetAttribute("Xp", 0)
		player:SetAttribute("XpNeeded", Catalog.xpToNext(1))
		if ProgressData.waitUntilReady(player) then
			ready[player] = true
			publish(player)
			Progress.loaded:Fire(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function Progress.level(player: Player): number
	return ProgressData.level(player)
end

function Progress.xpNeeded(player: Player): number
	local level = ProgressData.level(player)
	return if level >= Tuning.get("Progress.MaxLevel") then 0 else Catalog.xpToNext(level)
end

function Progress.addXp(player: Player, amount: number): number?
	if amount ~= amount or amount <= 0 then
		return nil
	end
	local before = ProgressData.level(player)
	local level, gained = ProgressData.addXp(player, math.floor(amount), Tuning.get("Progress.MaxLevel"), Catalog.xpToNext)
	if not level then
		return nil
	end
	publish(player)
	if gained > 0 and level > before then
		Progress.leveledUp:Fire(player, level)
	end
	return level
end

function Progress.setFlag(player: Player, flagId: string): boolean
	local created = ProgressData.setFlag(player, flagId)
	if created then
		Progress.flagSet:Fire(player, flagId)
	end
	return created
end

function Progress.hasFlag(player: Player, flagId: string): boolean
	return ProgressData.hasFlag(player, flagId)
end

function Progress.reset(player: Player)
	if ProgressData.reset(player) then
		publish(player)
	end
end

return Progress
