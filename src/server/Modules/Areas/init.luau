--[[
	Areas · módulo core: sabe qué jugadores están dentro de cada zona (pieza kind "zone"
	de Levels.json) y lo publica. A diferencia de una zona de una sola vez, aquí importa
	estar adentro: Guarida, escondite, arena, Sala de Entrenamiento, distrito.

	No sabe qué significa cada zona: lo deciden los puentes y Game por su nombre
	(ZoneName). Las zonas son cajas sin rotar o rotadas; se prueba con el espacio local.

	API:
	  Areas.init(options)                  { built, names } (nombres de zona a vigilar; todas si falta)
	  Areas.start()                        empieza a vigilar a los jugadores
	  Areas.parts(name)                    -> { BasePart } zonas con ese nombre
	  Areas.inside(player, name)           -> BasePart? la primera zona de ese nombre que lo contiene
	  Areas.containing(position, name)     -> BasePart? la zona de ese nombre que contiene el punto
	  Areas.nearest(name, position, maxDistance?) -> (BasePart?, number) la más cercana
	  Areas.entered / Areas.left           Signal (player, name, part)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Signal)

export type Options = {
	built: { levels: { { byKind: { [string]: { BasePart } } } } },
	names: { string }?,
}

local Areas = {}

Areas.entered = Signal.new() :: Signal.Signal<Player, string, BasePart>
Areas.left = Signal.new() :: Signal.Signal<Player, string, BasePart>

local TICK = 0.2

local byName: { [string]: { BasePart } } = {}
local watched: { [string]: boolean } = {}
local presence: { [Player]: { [BasePart]: boolean } } = {}

local function contains(part: BasePart, position: Vector3): boolean
	local local_ = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(local_.X) <= half.X and math.abs(local_.Y) <= half.Y and math.abs(local_.Z) <= half.Z
end

function Areas.init(options: Options)
	byName = {}
	watched = {}
	if options.names then
		for _, name in options.names do
			watched[name] = true
		end
	end
	for _, level in options.built.levels do
		for _, part in level.byKind.zone or {} do
			local name = part:GetAttribute("ZoneName")
			if type(name) == "string" and (not options.names or watched[name]) then
				local list = byName[name]
				if not list then
					list = {}
					byName[name] = list
				end
				table.insert(list, part)
			end
		end
	end
end

function Areas.parts(name: string): { BasePart }
	return byName[name] or {}
end

function Areas.containing(position: Vector3, name: string): BasePart?
	local list = byName[name]
	if list then
		for _, part in list do
			if contains(part, position) then
				return part
			end
		end
	end
	return nil
end

function Areas.inside(player: Player, name: string): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return Areas.containing(root.Position, name)
end

function Areas.nearest(name: string, position: Vector3, maxDistance: number?): (BasePart?, number)
	local best, bestDistance = nil, maxDistance or math.huge
	local list = byName[name]
	if list then
		for _, part in list do
			local distance = (part.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best, bestDistance
end

local function step()
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local current = presence[player]
		if not current then
			current = {}
			presence[player] = current
		end
		local now: { [BasePart]: boolean } = {}
		if root and root:IsA("BasePart") then
			local position = root.Position
			for name, parts in byName do
				for _, part in parts do
					if contains(part, position) then
						now[part] = true
						if not current[part] then
							Areas.entered:Fire(player, name, part)
						end
					end
				end
			end
		end
		for part in current do
			if not now[part] then
				Areas.left:Fire(player, part:GetAttribute("ZoneName"), part)
			end
		end
		presence[player] = now
	end
end

function Areas.start()
	Players.PlayerRemoving:Connect(function(player)
		presence[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= TICK then
			elapsed = 0
			step()
		end
	end)
end

return Areas
