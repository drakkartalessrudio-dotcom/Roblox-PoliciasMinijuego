--[[
	Achievements · módulo core: los logros. No guarda nada propio: cada logro es una meta
	sobre una métrica que otro módulo ya guarda (contadores de Stats, nivel más alto,
	Ascensiones, álbum). Por eso no cambia el esquema de datos y un logro nunca se pierde
	ni se duplica: si la métrica llega a la meta, está logrado.

	El core no sabe de dónde sale cada métrica: Game pasa `metric(jugador, id)`.

	Se calcula al cargar el perfil (en silencio) y cada Achievements.RefreshSeconds; un
	logro que se cruza durante la sesión publica `unlocked` una sola vez.

	Publica atributos del jugador: Ach_<id> (progreso, sin pasar de la meta) y AchCount.

	API:
	  Achievements.init(options)            { defs, metric(player, metricId) -> number }
	  Achievements.start()
	  Achievements.sync(player)             calcula en silencio (el perfil ya cargó): empieza a vigilarlo
	  Achievements.refresh(player)          recalcula y avisa de los logros nuevos
	  Achievements.count(player)            -> number logrados
	  Achievements.isDone(player, id)       -> boolean
	  Achievements.progress(player, id)     -> (number, number) valor y meta
	  Achievements.unlocked                 Signal (player, def)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

export type Def = {
	id: string,
	name: string,
	description: string,
	metric: string,
	goal: number,
}

export type Options = {
	defs: { Def },
	metric: (player: Player, metricId: string) -> number,
}

local Achievements = {}

Achievements.unlocked = Signal.new() :: Signal.Signal<Player, Def>

local options: Options? = nil
local done: { [Player]: { [string]: boolean } } = {}
local values: { [Player]: { [string]: number } } = {}

function Achievements.init(opts: Options)
	options = opts
end

local function evaluate(player: Player, announce: boolean)
	assert(options)
	local doneFor = done[player]
	local valuesFor = values[player]
	if not doneFor or not valuesFor then
		return
	end
	local count = 0
	for _, def in options.defs do
		local value = options.metric(player, def.metric)
		valuesFor[def.id] = value
		player:SetAttribute(`Ach_{def.id}`, math.min(value, def.goal))
		if value >= def.goal then
			count += 1
			if not doneFor[def.id] then
				doneFor[def.id] = true
				if announce then
					Achievements.unlocked:Fire(player, def)
				end
			end
		end
	end
	player:SetAttribute("AchCount", count)
end

function Achievements.sync(player: Player)
	done[player] = {}
	values[player] = {}
	evaluate(player, false)
end

function Achievements.refresh(player: Player)
	evaluate(player, true)
end

function Achievements.count(player: Player): number
	local count = 0
	local doneFor = done[player]
	if doneFor then
		for _ in doneFor do
			count += 1
		end
	end
	return count
end

function Achievements.isDone(player: Player, id: string): boolean
	local doneFor = done[player]
	return doneFor ~= nil and doneFor[id] == true
end

function Achievements.progress(player: Player, id: string): (number, number)
	assert(options)
	for _, def in options.defs do
		if def.id == id then
			local valuesFor = values[player]
			return if valuesFor then valuesFor[id] or 0 else 0, def.goal
		end
	end
	return 0, 0
end

function Achievements.start()
	Players.PlayerRemoving:Connect(function(player)
		done[player], values[player] = nil, nil
	end)
	task.spawn(function()
		while true do
			task.wait(Tuning.get("Achievements.RefreshSeconds"))
			for _, player in Players:GetPlayers() do
				if done[player] then
					local ok, err = pcall(evaluate, player, true)
					if not ok then
						warn(`[Achievements] {player.Name}: {err}`)
					end
				end
			end
		end
	end)
end

return Achievements
