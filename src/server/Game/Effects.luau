--[[
	Effects · lo que hace cada acción y herramienta en el mundo, y cómo afectan los
	policías al jugador. Mezcla Tools, Cops y Movement, así que es de Game.

	  dash        Embestida: impulso + derriba a quien tenga menos resistencia que tu poder
	  push        Empujón: derriba a la Patata de frente
	  tarta       aturde al policía que está en la línea de tiro
	  banana      trampa en el suelo: el primer policía que la pisa resbala
	  humo        bomba de confeti: los policías cercanos pierden la vista
	  patineta    más velocidad unos segundos
	  senuelo     un muñeco que los policías persiguen

	El impulso del Dash lo aplica el cliente (es el dueño de la física de su personaje);
	el servidor solo mide enfriamiento, velocidad y a quién derriba.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Style = require(ReplicatedStorage.Shared.Style)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Cops = require(ServerScriptService.Server.Modules.Cops)
local Stats = require(ServerScriptService.Server.Modules.Stats)
local Tools = require(ServerScriptService.Server.Modules.Tools)
local Movement = require(script.Parent.Movement)
local PlayerStats = require(script.Parent.PlayerStats)

local Effects = {}

-- Dirección de apuntado que mandó el cliente con la última orden (la lee quien reacciona a Tools.used).
Effects.aim = {} :: { [Player]: Vector3 }

type Trap = { part: Part, owner: Player, expires: number }
local traps: { Trap } = {}

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function aimFor(player: Player, root: BasePart): Vector3
	local aim = Effects.aim[player]
	if aim and flat(aim).Magnitude > 0.05 then
		return flat(aim).Unit
	end
	return flat(root.CFrame.LookVector).Unit
end

local function resistanceOf(cop: Cops.Cop): number
	return Tuning.get(`Cops.{cop.def.configKey}.Resistance`)
end

local function knock(player: Player, cop: Cops.Cop)
	Cops.knockdown(cop, Tuning.get("Cops.KnockdownSeconds"), player)
	Stats.increment(player, "cop_knockdowns", 1)
end

local function dash(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local direction = aimFor(player, root)
	Movement.dash(player, Tuning.get("Player.DashSeconds"))
	Net.send(player, "dash", { direction = direction, speed = PlayerStats.baseSpeed(player) * Tuning.get("Player.DashSpeedMult") })
	local power = PlayerStats.power(player)
	task.spawn(function()
		local hit: { [Cops.Cop]: boolean } = {}
		local finish = os.clock() + Tuning.get("Player.DashSeconds") + 0.1
		while os.clock() < finish do
			local current = rootOf(player)
			if not current then
				return
			end
			for _, cop in Cops.within(current.Position + direction * 2, 6) do
				if not hit[cop] then
					hit[cop] = true
					if power >= resistanceOf(cop) then
						knock(player, cop)
					end
				end
			end
			task.wait(0.05)
		end
	end)
end

local function push(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local direction = aimFor(player, root)
	for _, cop in Cops.within(root.Position, Tuning.get("Player.PushRange")) do
		local toCop = flat(cop.root.Position - root.Position)
		if cop.def.id == "patata" and toCop.Magnitude > 0.1 and toCop.Unit:Dot(direction) > 0.2 then
			knock(player, cop)
		end
	end
end

local function projectile(from: Vector3, to: Vector3, color: Color3)
	local pie = Instance.new("Part")
	pie.Shape = Enum.PartType.Ball
	pie.Size = Vector3.new(1.6, 1.6, 1.6)
	pie.Color = color
	pie.Material = Enum.Material.SmoothPlastic
	pie.Anchored = true
	pie.CanCollide = false
	pie.CanQuery = false
	pie.Position = from
	pie.Parent = Workspace
	TweenService:Create(pie, TweenInfo.new(0.22), { Position = to }):Play()
	Debris:AddItem(pie, 0.4)
end

local function tarta(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local range = Tuning.get("Tools.Tarta.Range")
	local aim = Effects.aim[player]
	local direction = if aim and aim.Magnitude > 0.05 then aim.Unit else root.CFrame.LookVector
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local best, bestT = nil :: Cops.Cop?, math.huge
	for _, cop in Cops.within(origin + direction * (range / 2), range / 2 + 6) do
		local offset = cop.root.Position - origin
		local t = offset:Dot(direction)
		if t > 0 and t < range and t < bestT then
			local perpendicular = (offset - direction * t).Magnitude
			if perpendicular < 4 then
				best, bestT = cop, t
			end
		end
	end
	local reach = bestT
	if best then
		-- Una pared en el camino la frena.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character, best.model, Workspace:FindFirstChild("Cops") }
		params.RespectCanCollide = true
		if Workspace:Raycast(origin, direction * bestT, params) then
			best = nil
			reach = range
		end
	else
		reach = range
	end
	projectile(origin, origin + direction * math.min(reach, range), Color3.fromRGB(255, 215, 120))
	if best then
		Cops.stun(best, Tuning.get("Tools.Tarta.StunSeconds"), "tarta")
	end
end

local function banana(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Banana"
	part.Size = Vector3.new(3, 0.6, 1.4)
	part.Color = Color3.fromRGB(255, 225, 70)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.7, 0))
	part.Parent = Workspace
	table.insert(traps, { part = part, owner = player, expires = os.clock() + Tuning.get("Tools.Banana.Lifetime") })
end

local function humo(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	Cops.blind(root.Position, Tuning.get("Tools.Humo.Radius"), Tuning.get("Tools.Humo.BlindSeconds"))
	local puff = Instance.new("Part")
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.Transparency = 1
	puff.Size = Vector3.new(1, 1, 1)
	puff.Position = root.Position
	puff.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Style.color("accent")),
		ColorSequenceKeypoint.new(0.5, Style.color("goal")),
		ColorSequenceKeypoint.new(1, Style.color("reward")),
	})
	emitter.Size = NumberSequence.new(2.5)
	emitter.Lifetime = NumberRange.new(1.5, 3)
	emitter.Speed = NumberRange.new(12, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = puff
	emitter:Emit(90)
	Debris:AddItem(puff, Tuning.get("Tools.Humo.BlindSeconds"))
end

local function patineta(player: Player)
	local seconds = Tuning.get("Tools.Patineta.Seconds")
	Tools.setActive(player, "patineta", seconds)
	Movement.applySpeed(player)
	task.delay(seconds + 0.1, function()
		Movement.applySpeed(player)
	end)
end

local function senuelo(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local direction = aimFor(player, root)
	local position = root.Position + direction * 8
	local doll = Instance.new("Part")
	doll.Name = "Senuelo"
	doll.Size = Vector3.new(3, 5.5, 0.4)
	doll.Color = Color3.fromRGB(190, 150, 100)
	doll.Material = Enum.Material.Cardboard
	doll.Anchored = true
	doll.CanCollide = false
	doll.CFrame = CFrame.new(position.X, root.Position.Y, position.Z) * CFrame.Angles(0, math.atan2(-direction.X, -direction.Z), 0)
	doll.Parent = Workspace
	local seconds = Tuning.get("Tools.Senuelo.Seconds")
	Cops.decoy(doll.Position, seconds)
	Debris:AddItem(doll, seconds)
end

local handlers: { [string]: (Player) -> () } = {
	dash = dash,
	push = push,
	tarta = tarta,
	banana = banana,
	humo = humo,
	patineta = patineta,
	senuelo = senuelo,
}

function Effects.start()
	Tools.used:Connect(function(player, toolId)
		local handler = handlers[toolId]
		if handler then
			handler(player)
		end
	end)
	Cops.abilityHit:Connect(function(player, kind)
		if kind == "vapor" then
			Movement.slow(player, Tuning.get("Cops.CafeteraSlow"), Tuning.get("Cops.CafeteraSlowSeconds"))
		elseif kind == "red" then
			Movement.slow(player, 0.4, 2)
		elseif kind == "grito" then
			Movement.stun(player, 1)
		end
		Net.send(player, "notify", { kind = "ability", ability = kind })
	end)
	Players.PlayerRemoving:Connect(function(player)
		Effects.aim[player] = nil
		for index = #traps, 1, -1 do
			if traps[index].owner == player then
				traps[index].part:Destroy()
				table.remove(traps, index)
			end
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.15 then
			return
		end
		elapsed = 0
		local now = os.clock()
		for index = #traps, 1, -1 do
			local trap = traps[index]
			local expired = now > trap.expires
			if not expired then
				for _, cop in Cops.within(trap.part.Position, 4.5) do
					Cops.stun(cop, Tuning.get("Tools.Banana.SlipSeconds"), "banana")
					expired = true
					break
				end
			end
			if expired then
				trap.part:Destroy()
				table.remove(traps, index)
			end
		end
	end)
end

return Effects
