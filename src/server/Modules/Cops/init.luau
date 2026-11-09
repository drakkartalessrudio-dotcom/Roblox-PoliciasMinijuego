--[[
	Cops · módulo core: los policías brainrot. Patrullan, detectan, persiguen, agarran,
	se dejan derribar y tienen sus habilidades. Todo es estado de sesión del servidor.

	Detección: cada policía tiene un cono de visión y un alcance (con Sigilo y la
	dificultad de la ciudad). Estar en el cono con línea de vista llena una barra
	(Detect.FillSecondsNear/Far); al llenarse el policía te persigue. Pero un policía
	de patrulla solo mira a quien `canEngage` deja: sin estrellas y sin una travesura en
	curso, un jugador puede pasar delante de la patrulla sin que lo persigan. El ruido de
	una travesura alerta a los policías cercanos hacia ese punto (Cops.alert).

	Persecución: se mueve hacia el jugador (o hacia su última posición, o hacia un
	señuelo), con salto ante obstáculos y PathfindingService solo si se atasca. Agarra si
	se mantiene a GrabDistance durante GrabTime y publica `caught`. Un jugador más rápido
	que él no se deja agarrar: la velocidad es defensa real.

	Habilidades: Tiburón (salto-embestida con aviso), Cafetera (vapor que ralentiza),
	Helicóptero (foco y red desde el aire, no se derriba) y Comisario (grito, jefe que cae
	con un combo de 3 trampas).

	No sabe de estrellas ni de economía: Cops_Wanted conecta lo que ve con el calor, y Game
	decide qué hace cada evento. Qué aspecto tiene cada tipo lo pasa Game en `build`.

	API:
	  Cops.init(options)
	  Cops.start()
	  Cops.summon(tipo, posición, jugador, velocidad?) -> Cop?  un perseguidor para ese jugador (tutorial)
	  Cops.alert(position, radius, source?)       los policías cercanos van a ese punto
	  Cops.witnessed(player, position, radius)    -> boolean ¿algún policía lo vería o lo oiría?
	  Cops.within(position, radius)               -> { Cop } policías (no volando) cerca de un punto
	  Cops.knockdown(cop, seconds, attacker?)     ragdoll; publica knockedDown
	  Cops.stun(cop, seconds, kind?)              aturde (kind "tarta" o "banana"); suma al combo del jefe
	  Cops.blind(position, radius, seconds)       los policías pierden la vista
	  Cops.decoy(position, seconds)               los policías persiguen el señuelo
	  Cops.dismiss(player)                        retira a los perseguidores de un jugador
	  Cops.chaserCount(player)                    -> number
	  Cops.seenBy(player)                         -> boolean
	  Cops.sightChanged                           Signal (player, visto)
	  Cops.caught                                 Signal (player, cop)
	  Cops.knockedDown                            Signal (cop, attacker?)
	  Cops.abilityHit                             Signal (player, kind, cop)  kind: "vapor" | "red" | "grito"
	  Cops.bossDefeated                           Signal (cop, attacker?)
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

export type TypeDef = {
	id: string,
	configKey: string, -- clave en Config.Cops (Patata, Capibara…)
	name: string,
	flying: boolean?,
	boss: boolean?,
	build: () -> Model, -- Model con HumanoidRootPart (PrimaryPart) y Humanoid; el helicóptero sin Humanoid
}

export type Cop = {
	id: string,
	def: TypeDef,
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	owner: Player?, -- a quién persigue
	state: string, -- patrol | suspicious | chase | search
	detect: { [Player]: number },
	grabTimer: number,
	knockedUntil: number,
	stunUntil: number,
	blindUntil: number,
	slowUntil: number,
	searchUntil: number,
	lastSeen: Vector3?,
	sawTargetAt: number,
	destination: Vector3?,
	nextPatrolAt: number,
	abilityAt: number,
	telegraphUntil: number,
	lungeUntil: number,
	hits: number,
	lastMoveAt: number,
	lastPosition: Vector3,
	path: { Vector3 }?,
	pathAt: number,
	spawnedAt: number,
	ambient: boolean,
	alertBox: TextLabel?,
	align: AlignPosition?,
	speedOverride: number?, -- velocidad fija (policía guionado del tutorial)
}

export type Options = {
	types: { [string]: TypeDef },
	spawnPoints: { BasePart }, -- zonas cop_spawn
	heliPoints: { BasePart }, -- zonas heli_spawn
	bossPoints: { BasePart }, -- zonas comisario_spawn
	rosterFor: (player: Player) -> { { string | number } }, -- { { tipo, cantidad } } según las estrellas del jugador
	patrolType: (player: Player) -> string, -- tipo de la patrulla ambiental según el nivel
	maxFor: (player: Player) -> number, -- tope de perseguidores de un jugador
	isProtected: (player: Player) -> boolean, -- Guarida u otro lugar seguro
	canEngage: (player: Player) -> boolean, -- ¿la patrulla puede detectarlo? (con estrellas o haciendo una travesura)
	isCovered: (player: Player) -> boolean, -- bajo una cubierta (el helicóptero no ve)
	sigiloFor: (player: Player) -> number, -- 0 a 1: reducción de visión y ruido
	difficultyFor: (player: Player) -> number, -- aumento por Ascensión (0 a DifficultyCap)
	speedMultAt: (position: Vector3) -> number, -- arena y similares
	collisionGroup: string?,
}

local Cops = {}

Cops.sightChanged = Signal.new() :: Signal.Signal<Player, boolean>
Cops.caught = Signal.new() :: Signal.Signal<Player, Cop>
Cops.knockedDown = Signal.new() :: Signal.Signal<Cop, Player?>
Cops.abilityHit = Signal.new() :: Signal.Signal<Player, string, Cop>
Cops.bossDefeated = Signal.new() :: Signal.Signal<Cop, Player?>

local options: Options? = nil
local folder: Folder
local cops: { [Model]: Cop } = {}
local sight: { [Player]: boolean } = {}
local decoy: { position: Vector3, until_: number }? = nil
local nextSpawnAt: { [Player]: number } = {}
local bossCooldown: { [Player]: number } = {}
local serial = 0
local random = Random.new()

local STUCK_SECONDS = 1.6
local PATH_COOLDOWN = 3
local CHASE_FORGET = 2.5 -- segundos sin ver al jugador antes de buscar su última posición

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function def(cop: Cop): { [string]: any }
	return Tuning.get(`Cops.{cop.def.configKey}`)
end

local function difficulty(cop: Cop): number
	assert(options)
	local scale = 0
	if cop.owner then
		scale = options.difficultyFor(cop.owner)
	end
	return scale
end

local function speedOf(cop: Cop, now: number): number
	assert(options)
	local base = (cop.speedOverride or def(cop).Speed) * (1 + difficulty(cop))
	if cop.state == "patrol" or cop.state == "suspicious" then
		base *= 0.5
	end
	if not cop.def.flying then
		base *= options.speedMultAt(cop.root.Position)
	end
	if now < cop.slowUntil then
		base *= Tuning.get("Cops.CafeteraSlow")
	end
	if now < cop.lungeUntil then
		base *= 2.6
	end
	return base
end

local function setAlert(cop: Cop, text: string)
	if cop.alertBox then
		cop.alertBox.Text = text
	end
end

local function raycastParams(cop: Cop, player: Player): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, cop.model, player.Character }
	params.RespectCanCollide = true
	return params
end

local function lineOfSight(cop: Cop, player: Player, from: Vector3, to: Vector3): boolean
	local hit = Workspace:Raycast(from, to - from, raycastParams(cop, player))
	return hit == nil
end

-- ¿Este policía ve al jugador ahora mismo (sin contar la barra de detección)?
local function canSee(cop: Cop, player: Player, root: BasePart): (boolean, number)
	assert(options)
	if options.isProtected(player) then
		return false, math.huge
	end
	local config = def(cop)
	local range = config.VisionRange * (1 + difficulty(cop)) * (1 - math.clamp(options.sigiloFor(player), 0, 0.8))
	local offset = root.Position - cop.root.Position
	local distance = offset.Magnitude
	if distance > range then
		return false, distance
	end
	if cop.def.flying then
		if options.isCovered(player) then
			return false, distance
		end
		return flat(offset).Magnitude <= range, distance
	end
	if distance > 8 then
		local look = flat(cop.root.CFrame.LookVector)
		local direction = flat(offset)
		if direction.Magnitude > 0.1 and look.Magnitude > 0.1 then
			local cosine = look.Unit:Dot(direction.Unit)
			if cosine < math.cos(math.rad(Tuning.get("Detect.ConeDegrees") / 2)) then
				return false, distance
			end
		end
	end
	if options.isCovered(player) and distance > 12 then
		return false, distance
	end
	local eye = cop.root.Position + Vector3.new(0, 2, 0)
	return lineOfSight(cop, player, eye, root.Position), distance
end

local function nearestPlayer(position: Vector3, maxDistance: number): (Player?, number)
	local best, bestDistance = nil, maxDistance
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best, bestDistance
end

local function groundAt(position: Vector3): Vector3?
	local hit = Workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0))
	return if hit then hit.Position + Vector3.new(0, 3, 0) else nil
end

local function applyGroup(model: Model)
	assert(options)
	if not options.collisionGroup then
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = options.collisionGroup
		end
	end
end

local function spawnCop(typeId: string, position: Vector3, owner: Player?, ambient: boolean): Cop?
	assert(options)
	local typeDef = options.types[typeId]
	if not typeDef then
		return nil
	end
	local model = typeDef.build()
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	serial += 1
	model.Name = `{typeDef.name}_{serial}`
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if typeDef.flying then
		position += Vector3.new(0, Tuning.get("Cops.FlyHeight"), 0)
	end
	model:PivotTo(CFrame.new(position))
	model.Parent = folder
	applyGroup(model)
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local now = os.clock()
	local cop: Cop = {
		id = `cop{serial}`,
		def = typeDef,
		model = model,
		root = root,
		humanoid = humanoid,
		owner = owner,
		state = if owner and not ambient then "chase" else "patrol",
		detect = {},
		grabTimer = 0,
		knockedUntil = 0,
		stunUntil = 0,
		blindUntil = 0,
		slowUntil = 0,
		searchUntil = 0,
		lastSeen = nil,
		sawTargetAt = now,
		destination = nil,
		nextPatrolAt = now + random:NextNumber(0.5, 2),
		abilityAt = now + random:NextNumber(3, 6),
		telegraphUntil = 0,
		lungeUntil = 0,
		hits = 0,
		lastMoveAt = now,
		lastPosition = root.Position,
		path = nil,
		pathAt = 0,
		spawnedAt = now,
		ambient = ambient,
		alertBox = model:FindFirstChild("Alert", true) :: TextLabel?,
		align = nil,
	}
	if typeDef.flying then
		local attachment = root:FindFirstChildOfClass("Attachment") or Instance.new("Attachment")
		attachment.Parent = root
		local align = Instance.new("AlignPosition")
		align.Attachment0 = attachment
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.MaxForce = 1e6
		align.Responsiveness = 12
		align.MaxVelocity = Tuning.get(`Cops.{typeDef.configKey}`).Speed
		align.Position = root.Position
		align.Parent = root
		cop.align = align
		root.CanCollide = false
	end
	if humanoid then
		humanoid.WalkSpeed = speedOf(cop, now)
		humanoid.AutoRotate = true
	end
	cops[model] = cop
	setAlert(cop, if cop.state == "chase" then "!" else "")
	return cop
end

local function removeCop(cop: Cop)
	cops[cop.model] = nil
	cop.model:Destroy()
end

local function chasersOf(player: Player): { Cop }
	local list = {}
	for _, cop in cops do
		if cop.owner == player and cop.state ~= "patrol" then
			table.insert(list, cop)
		end
	end
	return list
end

local function setSight(player: Player, seen: boolean)
	if sight[player] ~= seen then
		sight[player] = seen
		Cops.sightChanged:Fire(player, seen)
	end
end

local function moveTo(cop: Cop, goal: Vector3, now: number)
	local humanoid = cop.humanoid
	if cop.def.flying then
		if cop.align then
			cop.align.Position = goal
			cop.align.MaxVelocity = speedOf(cop, now)
		end
		return
	end
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = speedOf(cop, now)
	-- Atasco: si casi no avanza, se calcula una ruta (como mucho cada PATH_COOLDOWN).
	if (cop.root.Position - cop.lastPosition).Magnitude > 1.2 then
		cop.lastPosition = cop.root.Position
		cop.lastMoveAt = now
		cop.path = nil
	elseif now - cop.lastMoveAt > STUCK_SECONDS and now - cop.pathAt > PATH_COOLDOWN then
		cop.pathAt = now
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(cop.root.Position, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
			cop.path = points
		end
	end
	local target = goal
	if cop.path and #cop.path > 0 then
		while #cop.path > 1 and (cop.path[1] - cop.root.Position).Magnitude < 4 do
			table.remove(cop.path, 1)
		end
		target = cop.path[1]
	end
	humanoid:MoveTo(target)
	-- Salta obstáculos bajos.
	local forward = flat(target - cop.root.Position)
	if forward.Magnitude > 1 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { folder }
		params.RespectCanCollide = true
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(params.FilterDescendantsInstances, player.Character)
			end
		end
		local hit = Workspace:Raycast(cop.root.Position - Vector3.new(0, 1.5, 0), forward.Unit * 4, params)
		if hit and hit.Instance.CanCollide and hit.Instance.Size.Y < 9 then
			humanoid.Jump = true
		end
	end
end

local function pickPatrolPoint(cop: Cop): Vector3?
	assert(options)
	local candidates = {}
	for _, part in options.spawnPoints do
		local distance = (part.Position - cop.root.Position).Magnitude
		if distance > 25 and distance < 220 then
			table.insert(candidates, part.Position)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[random:NextInteger(1, #candidates)]
end

local function knock(cop: Cop, seconds: number, attacker: Player?)
	local now = os.clock()
	cop.knockedUntil = now + seconds
	cop.state = if cop.owner then "chase" else "patrol"
	if cop.humanoid then
		cop.humanoid.PlatformStand = true
		cop.root.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-20, 20), 40, random:NextNumber(-20, 20))
	end
	setAlert(cop, "×")
	Cops.knockedDown:Fire(cop, attacker)
end

-- Una pasada de decisión de un policía.
local function think(cop: Cop, now: number, tick: number)
	assert(options)
	local humanoid = cop.humanoid
	if not cop.model.Parent or (humanoid and humanoid.Health <= 0) then
		removeCop(cop)
		return
	end
	if now < cop.knockedUntil then
		return
	elseif humanoid and humanoid.PlatformStand and cop.knockedUntil > 0 then
		humanoid.PlatformStand = false
		cop.knockedUntil = 0
		cop.root.CFrame = CFrame.new(cop.root.Position + Vector3.new(0, 3, 0))
		setAlert(cop, if cop.state == "chase" then "!" else "")
	end
	if now < cop.stunUntil then
		if humanoid then
			humanoid.WalkSpeed = 0
		end
		return
	end
	local config = def(cop)

	-- Detección: cada jugador cercano llena o vacía su barra.
	local seenTarget = false
	local visibleTo: { Player } = {}
	if now >= cop.blindUntil then
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root then
				-- La patrulla ignora a quien no está buscado ni haciendo una travesura; quien ya persigue a su dueño no pierde la vista.
				local visible, distance = false, math.huge
				if cop.owner == player or options.canEngage(player) then
					visible, distance = canSee(cop, player, root)
				end
				if visible then
					local range = config.VisionRange * (1 + difficulty(cop))
					local fill = Tuning.get("Detect.FillSecondsNear")
						+ (Tuning.get("Detect.FillSecondsFar") - Tuning.get("Detect.FillSecondsNear")) * math.clamp(distance / range, 0, 1)
					local value = (cop.detect[player] or 0) + tick / fill
					cop.detect[player] = value
					if value >= 1 then
						table.insert(visibleTo, player)
						if cop.owner == player or cop.owner == nil then
							seenTarget = seenTarget or cop.owner == player
						end
					end
				else
					cop.detect[player] = math.max(0, (cop.detect[player] or 0) - tick * 1.5)
				end
			end
		end
	end

	-- Un policía de patrulla que detecta a alguien lo persigue.
	if cop.state == "patrol" or cop.state == "suspicious" or cop.state == "search" then
		local target = visibleTo[1]
		if target then
			cop.owner = target
			cop.ambient = false
			cop.state = "chase"
			cop.sawTargetAt = now
			setAlert(cop, "!")
		end
	end

	if cop.state == "chase" and cop.owner then
		local owner = cop.owner
		local root = rootOf(owner)
		if not root then
			cop.state = "search"
			cop.searchUntil = now + Tuning.get("Cops.SearchSeconds")
			setAlert(cop, "?")
			return
		end
		local visible = table.find(visibleTo, owner) ~= nil
		if visible then
			cop.sawTargetAt = now
			cop.lastSeen = root.Position
		end
		-- Señuelo: tiene prioridad mientras dure.
		local goal = cop.lastSeen or root.Position
		if decoy and now < decoy.until_ and (decoy.position - cop.root.Position).Magnitude < 100 then
			goal = decoy.position
			visible = false
		elseif visible then
			goal = root.Position
		end
		if not visible and now - cop.sawTargetAt > CHASE_FORGET then
			cop.state = "search"
			cop.searchUntil = now + Tuning.get("Cops.SearchSeconds")
			setAlert(cop, "?")
		end

		-- Habilidades.
		local toTarget = root.Position - cop.root.Position
		if cop.def.id == "tiburon" and visible and now >= cop.abilityAt and toTarget.Magnitude < 28 and toTarget.Magnitude > 6 then
			if cop.telegraphUntil == 0 then
				cop.telegraphUntil = now + Tuning.get("Cops.TiburonLungeWarn")
				cop.model:SetAttribute("Telegraph", true)
			elseif now >= cop.telegraphUntil then
				cop.telegraphUntil = 0
				cop.model:SetAttribute("Telegraph", false)
				cop.lungeUntil = now + 0.5
				cop.abilityAt = now + Tuning.get("Cops.TiburonLungeSeconds")
			end
		elseif cop.def.id == "cafetera" and visible and now >= cop.abilityAt and toTarget.Magnitude < 32 then
			if cop.telegraphUntil == 0 then
				cop.telegraphUntil = now + 0.6
				cop.model:SetAttribute("Telegraph", true)
			elseif now >= cop.telegraphUntil then
				cop.telegraphUntil = 0
				cop.model:SetAttribute("Telegraph", false)
				cop.abilityAt = now + 8
				if toTarget.Magnitude < 34 then
					Cops.abilityHit:Fire(owner, "vapor", cop)
				end
			end
		elseif cop.def.id == "helicoptero" and visible and now >= cop.abilityAt and flat(toTarget).Magnitude < 30 then
			cop.abilityAt = now + 10
			Cops.abilityHit:Fire(owner, "red", cop)
		elseif cop.def.id == "comisario" and visible and now >= cop.abilityAt and toTarget.Magnitude < 40 then
			if cop.telegraphUntil == 0 then
				cop.telegraphUntil = now + 1
				cop.model:SetAttribute("Telegraph", true)
			elseif now >= cop.telegraphUntil then
				cop.telegraphUntil = 0
				cop.model:SetAttribute("Telegraph", false)
				cop.abilityAt = now + 12
				if toTarget.Magnitude < 40 then
					Cops.abilityHit:Fire(owner, "grito", cop)
				end
			end
		end
		if cop.def.flying then
			local goalAir = Vector3.new(goal.X, root.Position.Y + Tuning.get("Cops.FlyHeight"), goal.Z)
			moveTo(cop, goalAir, now)
		else
			moveTo(cop, goal, now)
		end

		-- Agarre: solo policías de tierra, en cercanía sostenida.
		if not cop.def.flying and visible and (root.Position - cop.root.Position).Magnitude <= Tuning.get("Cops.GrabDistance") then
			cop.grabTimer += tick
			if cop.grabTimer >= Tuning.get("Cops.GrabTime") and not options.isProtected(owner) then
				cop.grabTimer = 0
				Cops.caught:Fire(owner, cop)
			end
		else
			cop.grabTimer = math.max(0, cop.grabTimer - tick)
		end
		return
	end

	if cop.state == "search" then
		local goal = cop.lastSeen or cop.root.Position
		moveTo(cop, goal, now)
		if now >= cop.searchUntil or (cop.root.Position - goal).Magnitude < 4 then
			if now >= cop.searchUntil then
				cop.state = "patrol"
				cop.owner = nil
				cop.ambient = true
				setAlert(cop, "")
			end
		end
		return
	end

	if cop.state == "suspicious" then
		moveTo(cop, cop.destination or cop.root.Position, now)
		if cop.destination and (cop.root.Position - cop.destination).Magnitude < 5 or now > cop.searchUntil then
			cop.state = "patrol"
			setAlert(cop, "")
		end
		return
	end

	-- Patrulla: va de un punto a otro con pausas.
	if cop.def.flying then
		return
	end
	if not cop.destination or (cop.root.Position - cop.destination).Magnitude < 5 then
		if now >= cop.nextPatrolAt then
			cop.destination = pickPatrolPoint(cop)
			cop.nextPatrolAt = now + random:NextNumber(1, 4)
		end
	end
	if cop.destination then
		moveTo(cop, cop.destination, now)
	end
end

-- Mantiene la plantilla de perseguidores y la patrulla de cada jugador.
local function manage(now: number)
	assert(options)
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if not root then
			continue
		end
		local want = options.rosterFor(player)
		local have: { [string]: number } = {}
		local total = 0
		for _, cop in chasersOf(player) do
			have[cop.def.id] = (have[cop.def.id] or 0) + 1
			total += 1
		end
		if #want == 0 then
			-- Sin estrellas: los perseguidores que quedan se retiran (volverán a patrullar o desaparecen).
			for _, cop in chasersOf(player) do
				if cop.state ~= "search" and now - cop.sawTargetAt > 1.5 then
					cop.state = "search"
					cop.searchUntil = now + 2
					setAlert(cop, "?")
				end
			end
		elseif now >= (nextSpawnAt[player] or 0) then
			local cap = options.maxFor(player)
			for _, entry in want do
				local typeId, count = entry[1] :: string, entry[2] :: number
				if (have[typeId] or 0) < count and total < cap then
					local typeDef = options.types[typeId]
					if typeDef and typeDef.boss and now < (bossCooldown[player] or 0) then
						continue
					end
					local position
					local pool = if typeDef and typeDef.flying then options.heliPoints elseif typeDef and typeDef.boss then options.bossPoints else options.spawnPoints
					local candidates = {}
					for _, part in pool do
						local distance = (part.Position - root.Position).Magnitude
						if distance >= Tuning.get("Cops.SpawnMinDistance") and distance <= Tuning.get("Cops.SpawnMaxDistance") then
							table.insert(candidates, part.Position)
						end
					end
					if #candidates > 0 then
						position = candidates[random:NextInteger(1, #candidates)]
					else
						local angle = random:NextNumber(0, math.pi * 2)
						local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Tuning.get("Cops.SpawnMinDistance") * 1.3
						position = groundAt(root.Position + offset)
					end
					if position then
						local cop = spawnCop(typeId, position, player, false)
						if cop then
							cop.lastSeen = root.Position
							total += 1
							nextSpawnAt[player] = now + 0.4
							break
						end
					end
				end
			end
		end
		-- Patrulla ambiental cerca del jugador (solo con el nivel que la permita).
		local patrolNear = 0
		for _, cop in cops do
			if cop.ambient and (cop.root.Position - root.Position).Magnitude < Tuning.get("Cops.PatrolRadius") then
				patrolNear += 1
			end
		end
		if patrolNear < Tuning.get("Cops.PatrolPerPlayer") and #options.spawnPoints > 0 and not options.isProtected(player) then
			local candidates = {}
			for _, part in options.spawnPoints do
				local distance = (part.Position - root.Position).Magnitude
				if distance >= 110 and distance <= Tuning.get("Cops.PatrolRadius") then
					table.insert(candidates, part.Position)
				end
			end
			if #candidates > 0 then
				spawnCop(options.patrolType(player), candidates[random:NextInteger(1, #candidates)], nil, true)
			end
		end
	end
	-- Retira lo que quedó lejos de todos o a quien ya no existe.
	for _, cop in cops do
		local near = nearestPlayer(cop.root.Position, Tuning.get("Cops.DespawnDistance"))
		if not near or (cop.owner and cop.owner.Parent ~= Players) then
			removeCop(cop)
		elseif cop.state == "search" and cop.owner and Tuning.get("Cops.SearchSeconds") and now > cop.searchUntil + 6 then
			cop.owner = nil
			cop.ambient = true
			cop.state = "patrol"
		end
	end
	-- Visibilidad por jugador (para Wanted).
	for _, player in Players:GetPlayers() do
		local seen = false
		for _, cop in cops do
			if cop.owner == player and cop.state == "chase" and now - cop.sawTargetAt < 0.5 and now >= cop.knockedUntil then
				seen = true
				break
			end
		end
		setSight(player, seen)
	end
end

function Cops.init(opts: Options)
	options = opts
	folder = Workspace:FindFirstChild("Cops") :: Folder? or Instance.new("Folder")
	folder.Name = "Cops"
	folder.Parent = Workspace
end

function Cops.start()
	Players.PlayerRemoving:Connect(function(player)
		Cops.dismiss(player)
		sight[player] = nil
		nextSpawnAt[player] = nil
		bossCooldown[player] = nil
	end)
	local tickElapsed, manageElapsed = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		tickElapsed += dt
		manageElapsed += dt
		local tickSeconds = Tuning.get("Detect.TickSeconds")
		if tickElapsed >= tickSeconds then
			local step = tickElapsed
			tickElapsed = 0
			local now = os.clock()
			for _, cop in cops do
				local ok, err = pcall(think, cop, now, step)
				if not ok then
					warn(`[Cops] {cop.id}: {err}`)
				end
			end
		end
		if manageElapsed >= 0.5 then
			manageElapsed = 0
			local ok, err = pcall(manage, os.clock())
			if not ok then
				warn(`[Cops] manage: {err}`)
			end
		end
	end)
end

-- Hace aparecer un perseguidor para un jugador en un punto (el policía guionado del tutorial).
function Cops.summon(typeId: string, position: Vector3, target: Player, speed: number?): Cop?
	local cop = spawnCop(typeId, position, target, false)
	if cop then
		cop.speedOverride = speed
		local root = rootOf(target)
		cop.lastSeen = if root then root.Position else nil
	end
	return cop
end

function Cops.alert(position: Vector3, radius: number, source: Player?)
	local now = os.clock()
	for _, cop in cops do
		if (cop.state == "patrol" or cop.state == "search") and now >= cop.blindUntil and not cop.def.flying then
			if (cop.root.Position - position).Magnitude <= radius * Tuning.get("Detect.HearingScale") then
				cop.state = "suspicious"
				cop.destination = position
				cop.searchUntil = now + Tuning.get("Cops.SearchSeconds")
				setAlert(cop, "?")
			end
		end
	end
end

function Cops.witnessed(player: Player, position: Vector3, radius: number): boolean
	assert(options)
	if options.isProtected(player) then
		return false
	end
	local root = rootOf(player)
	if not root then
		return false
	end
	local now = os.clock()
	for _, cop in cops do
		if now >= cop.blindUntil and now >= cop.knockedUntil then
			local distance = (cop.root.Position - root.Position).Magnitude
			if distance <= radius * Tuning.get("Detect.HearingScale") * (1 - math.clamp(options.sigiloFor(player), 0, 0.8)) then
				return true
			end
			local visible = canSee(cop, player, root)
			if visible then
				return true
			end
		end
	end
	return false
end

function Cops.within(position: Vector3, radius: number): { Cop }
	local list = {}
	for _, cop in cops do
		if not cop.def.flying and (cop.root.Position - position).Magnitude <= radius then
			table.insert(list, cop)
		end
	end
	return list
end

function Cops.knockdown(cop: Cop, seconds: number, attacker: Player?)
	if cops[cop.model] then
		knock(cop, seconds, attacker)
	end
end

function Cops.stun(cop: Cop, seconds: number, kind: string?)
	if not cops[cop.model] or cop.def.flying then
		return
	end
	cop.stunUntil = os.clock() + seconds
	setAlert(cop, "★")
	if cop.def.boss then
		cop.hits += 1
		if cop.hits >= 3 then
			cop.hits = 0
			local attacker = cop.owner
			knock(cop, 6, attacker)
			Cops.bossDefeated:Fire(cop, attacker)
			if attacker then
				bossCooldown[attacker] = os.clock() + 60
			end
			task.delay(3, function()
				if cops[cop.model] then
					removeCop(cop)
				end
			end)
		end
	end
end

function Cops.blind(position: Vector3, radius: number, seconds: number)
	local now = os.clock()
	for _, cop in cops do
		if (cop.root.Position - position).Magnitude <= radius then
			cop.blindUntil = now + seconds
			cop.detect = {}
			if cop.state == "chase" then
				cop.sawTargetAt = math.min(cop.sawTargetAt, now - CHASE_FORGET - 0.1)
			end
		end
	end
end

function Cops.decoy(position: Vector3, seconds: number)
	decoy = { position = position, until_ = os.clock() + seconds }
end

function Cops.dismiss(player: Player)
	for _, cop in cops do
		if cop.owner == player and not cop.ambient then
			removeCop(cop)
		end
	end
end

function Cops.chaserCount(player: Player): number
	return #chasersOf(player)
end

function Cops.seenBy(player: Player): boolean
	return sight[player] == true
end

return Cops
