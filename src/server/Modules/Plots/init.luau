--[[
	Plots · módulo core: las parcelas reclamables del lobby. Cada parcela es una zona
	"plot" de Levels.json; un jugador reclama una (como máximo Plots.MaxPerPlayer), la
	conserva mientras esté en el servidor y la suelta al irse o cuando quiere. Es estado
	de la sesión: no se guarda.

	No sabe qué se muestra en la parcela ni quién puede reclamarla desde dónde: Game crea
	los avisos de la parcela y llama a claim/release.

	Publica:
	  · atributo del jugador PlotId (id de la pieza, "" si no tiene)
	  · atributos de la pieza OwnerUserId (0 si está libre) y OwnerName

	API:
	  Plots.init(options)                 { parts } las zonas "plot" del mundo
	  Plots.start()
	  Plots.list()                        -> { BasePart }  todas las parcelas
	  Plots.claim(player, part)           -> (boolean, string?)  "taken", "already", "unknown"
	  Plots.release(player)               -> boolean
	  Plots.plotOf(player)                -> BasePart?
	  Plots.ownerOf(part)                 -> Player?
	  Plots.claimed / Plots.released      Signal (player, part)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

export type Options = {
	parts: { BasePart },
}

local Plots = {}

Plots.claimed = Signal.new() :: Signal.Signal<Player, BasePart>
Plots.released = Signal.new() :: Signal.Signal<Player, BasePart>

local parts: { BasePart } = {}
local isPlot: { [BasePart]: boolean } = {}
local owners: { [BasePart]: Player } = {}
local owned: { [Player]: { BasePart } } = {}

local function publishPlayer(player: Player)
	local list = owned[player]
	player:SetAttribute("PlotId", if list and list[1] then list[1].Name else "")
end

function Plots.init(opts: Options)
	parts = opts.parts
	isPlot = {}
	for _, part in parts do
		isPlot[part] = true
		part:SetAttribute("OwnerUserId", 0)
		part:SetAttribute("OwnerName", "")
	end
end

function Plots.start()
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("PlotId", "")
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("PlotId", "")
	end
	Players.PlayerRemoving:Connect(function(player)
		Plots.release(player)
		owned[player] = nil
	end)
end

function Plots.list(): { BasePart }
	return parts
end

function Plots.ownerOf(part: BasePart): Player?
	return owners[part]
end

function Plots.plotOf(player: Player): BasePart?
	local list = owned[player]
	return if list then list[1] else nil
end

function Plots.claim(player: Player, part: BasePart): (boolean, string?)
	if not isPlot[part] then
		return false, "unknown"
	end
	if owners[part] then
		return false, if owners[part] == player then "already" else "taken"
	end
	local list = owned[player]
	if not list then
		list = {}
		owned[player] = list
	end
	if #list >= Tuning.get("Plots.MaxPerPlayer") then
		return false, "already"
	end
	table.insert(list, part)
	owners[part] = player
	part:SetAttribute("OwnerUserId", player.UserId)
	part:SetAttribute("OwnerName", player.DisplayName)
	publishPlayer(player)
	Plots.claimed:Fire(player, part)
	return true, nil
end

function Plots.release(player: Player): boolean
	local list = owned[player]
	if not list or #list == 0 then
		return false
	end
	owned[player] = {}
	for _, part in list do
		owners[part] = nil
		part:SetAttribute("OwnerUserId", 0)
		part:SetAttribute("OwnerName", "")
		Plots.released:Fire(player, part)
	end
	publishPlayer(player)
	return true
end

return Plots
