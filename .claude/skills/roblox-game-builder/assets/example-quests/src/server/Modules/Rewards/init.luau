--[[
	Rewards · módulo core: entrega recompensas y lleva la racha de la recompensa
	diaria (sección "rewards" del perfil, con RewardData).

	Una recompensa es un dato ({ currency = { coins = 20 } }): este core no sabe qué es
	una moneda. Publica granted y el puente Rewards_Economy la convierte en saldo. La
	recompensa diaria se cobra sola al cargar el perfil, una vez por día UTC, con la
	hora del servidor; la racha sigue si la anterior fue hace menos de
	Rewards.StreakWindowHours.

	API:
	  Rewards.init(options)              recompensas diarias por día de racha, antes de start
	  Rewards.start()                    cobra la diaria al cargar cada perfil
	  Rewards.grant(player, reward, source)
	  Rewards.claimDaily(player)         -> boolean
	  Rewards.granted                    Signal (player, reward, source)
	  Rewards.dailyClaimed               Signal (player, racha)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local RewardData = require(script.RewardData)

export type Reward = {
	currency: { [string]: number }?, -- moneda → cantidad
}
export type Options = {
	daily: { Reward }, -- recompensa del día 1, 2, 3…; desde el último se repite
}

local Rewards = {}

Rewards.granted = Signal.new() :: Signal.Signal<Player, Reward, string>
Rewards.dailyClaimed = Signal.new() :: Signal.Signal<Player, number>

local daily: { Reward } = {}

local function utcDay(timestamp: number): number
	return math.floor(timestamp / 86400)
end

function Rewards.init(options: Options)
	daily = options.daily
end

function Rewards.grant(player: Player, reward: Reward, source: string)
	Rewards.granted:Fire(player, reward, source)
end

function Rewards.claimDaily(player: Player): boolean
	local streak, lastClaimAt = RewardData.daily(player)
	if streak == nil or #daily == 0 then
		return false
	end
	local now = os.time()
	if lastClaimAt > 0 and utcDay(now) == utcDay(lastClaimAt) then
		return false -- ya la cobró hoy
	end
	local window = Tuning.get("Rewards.StreakWindowHours") * 3600
	local newStreak = if lastClaimAt > 0 and now - lastClaimAt <= window then streak + 1 else 1
	if not RewardData.setDaily(player, newStreak, now) then
		return false
	end
	player:SetAttribute("DailyStreak", newStreak)
	Rewards.dailyClaimed:Fire(player, newStreak)
	Rewards.grant(player, daily[math.min(newStreak, #daily)], "daily")
	return true
end

function Rewards.start()
	local function onPlayerAdded(player: Player)
		if RewardData.waitUntilReady(player) then
			local streak = RewardData.daily(player)
			player:SetAttribute("DailyStreak", streak or 0)
			Rewards.claimDaily(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Rewards
