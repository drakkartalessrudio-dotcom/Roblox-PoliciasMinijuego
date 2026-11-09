--[[
	Cops · módulo core: los policías brainrot. Patrullan, detectan, persiguen, agarran,
	se dejan derribar y tienen sus habilidades. Todo es estado de sesión del servidor.

	Detección: cada policía tiene un cono de visión y un alcance (con Sigilo y la
	dificultad de la ciudad). Estar en el cono con línea de vista llena una barra
	(Detect.FillSecondsNear/Far); al llenarse el policía te persigue. Visión, velocidad y
	tiempo de detección crecen con las estrellas del jugador (Cops.Alert*ByStar): un Patata
	de ★1 ve poco y corre lento. Un policía de patrulla solo mira a quien `canEngage` deja:
	sin estrellas y sin una travesura en curso, un jugador puede pasar delante de la patrulla
	sin que lo persigan. El ruido de una travesura alerta a los policías cercanos hacia ese
	punto (Cops.alert).

	Tres clases de policía de la ciudad:
	  · Guardias: viven en un puesto de la ciudad (zonas `guard_post` de Levels.json, con un
	    `Post`, un `Order` y un `CopType`). Van a un punto, esperan, miran de derecha a izquierda
	    (Guard.ScanDegrees) y pasan al siguiente. Si ven al jugador en plena travesura (o buscado)
	    lo persiguen; cuando lo pierden vuelven a su último punto y, si no llegan en
	    Guard.ReturnSeconds, se teletransportan. Aparecen cuando hay un jugador cerca.
	  · Caminantes: la patrulla ambiental aparece en un punto cop_spawn, camina hasta otro y
	    desaparece (si nadie los mira).
	  · Perseguidores: los de la plantilla de estrellas. Los cazadores (TypeDef.hunter) eligen al
	    jugador con más estrellas, no al más cercano.

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
	hunter: boolean?, -- elige al jugador con más estrellas (no al más cercano)
	build: () -> Model, -- Model con HumanoidRootPart (PrimaryPart) y Humanoid; el helicóptero sin Humanoid
}

export type Post = {
	id: string,
	points: { BasePart }, -- zonas guard_post por Order; su CFrame dice hacia dónde mira la guardia
	copType: string,
	cop: Cop?,
	respawnAt: number,
}

export type Cop = {
	id: string,
	def: TypeDef,
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	owner: Player?, -- a quién persigue
	state: string, -- patrol | suspicious | chase | search | return (la guardia vuelve a su puesto)
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
	post: Post?, -- puesto que vigila (guardias)
	postIndex: number, -- punto de la ruta donde está o hacia donde va
	phase: string, -- guardia en patrulla: walk | wait | scan
	phaseAt: number,
	phaseUntil: number,
	returnAt: number, -- límite para llegar al punto antes de teletransportarse
	walker: boolean, -- caminante: va de un lugar a otro y desaparece
	walkerUntil: number,
	rosterFor: Player?, -- para quién se invocó (un cazador puede perseguir a otro jugador)
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
	starsFor: (player: Player) -> number, -- estrellas de búsqueda actuales (la alerta de los policías crece con ellas)
	speedMultAt: (position: Vector3) -> number, -- arena y similares
	collisionGroup: string?,
	guardPosts: { BasePart }?, -- zonas guard_post
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
local nextWalkerAt: { [Player]: number } = {}
local posts: { Post } = {}
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

-- Progresión de alerta (Cops.Alert*ByStar): multiplicador según las estrellas del jugador;
-- sin estrellas (p. ej. en plena travesura) vale el de ★1.
local function alertOf(player: Player?, key: string): number
	assert(options)
	local list = Tuning.get(`Cops.{key}`)
	local stars = if player then options.starsFor(player) else 0
	return list[math.clamp(stars, 1, #list)]
end

-- Alcance de visión de un policía contra un jugador, sin Sigilo.
local function visionRange(cop: Cop, player: Player): number
	return def(cop).VisionRange * alertOf(player, "AlertVisionByStar") * (1 + difficulty(cop))
end

local function speedOf(cop: Cop, now: number): number
	assert(options)
	local base = (cop.speedOverride or def(cop).Speed * alertOf(cop.owner, "AlertSpeedByStar")) * (1 + difficulty(cop))
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
	local range = visionRange(cop, player) * (1 - math.clamp(options.sigiloFor(player), 0, 0.8))
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
		post = nil,
		postIndex = 1,
		phase = "wait",
		phaseAt = now,
		phaseUntil = now,
		returnAt = 0,
		walker = false,
		walkerUntil = 0,
		rosterFor = nil,
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
	local post = cop.post
	if post and post.cop == cop then
		post.cop = nil
		post.respawnAt = os.clock() + Tuning.get("Guard.RespawnSeconds")
	end
	cop.model:Destroy()
end

-- Deja de perseguir. La guardia vuelve a su puesto; el resto pasa a caminar hacia otro lugar y se va
-- (los voladores se retiran sin más).
local function standDown(cop: Cop, now: number)
	cop.owner = nil
	cop.rosterFor = nil
	cop.detect = {}
	setAlert(cop, "")
	if cop.post then
		cop.ambient = false
		cop.state = "return"
		cop.returnAt = now + Tuning.get("Guard.ReturnSeconds")
	elseif cop.def.flying or cop.def.boss then
		removeCop(cop)
	else
		cop.ambient = true
		cop.state = "patrol"
		cop.walker = true
		cop.walkerUntil = now + Tuning.get("Cops.WalkerMaxSeconds")
		cop.destination = nil
	end
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

-- Destino de un caminante: otro punto cop_spawn a una distancia razonable.
local function pickWalkerGoal(from: Vector3): Vector3?
	assert(options)
	local candidates = {}
	for _, part in options.spawnPoints do
		local distance = flat(part.Position - from).Magnitude
		if distance >= Tuning.get("Cops.WalkerMinTrip") and distance <= Tuning.get("Cops.WalkerMaxTrip") then
			table.insert(candidates, part.Position)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[random:NextInteger(1, #candidates)]
end

local function playerWithin(position: Vector3, distance: number): boolean
	return (nearestPlayer(position, distance)) ~= nil
end

-- Entre varios jugadores a la vista, el más buscado (a igualdad, el primero): la prioridad son las estrellas.
local function mostWanted(list: { Player }): Player?
	assert(options)
	local best, bestStars = nil, -1
	for _, player in list do
		local stars = options.starsFor(player)
		if stars > bestStars then
			best, bestStars = player, stars
		end
	end
	return best
end

-- El jugador con más estrellas que un cazador puede perseguir (no el más cercano).
local function topWanted(from: Vector3): Player?
	assert(options)
	local best, bestStars, bestDistance = nil, 0, math.huge
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and not options.isProtected(player) then
			local stars = options.starsFor(player)
			local distance = (root.Position - from).Magnitude
			if stars > 0 and distance <= Tuning.get("Cops.HunterRange") and (stars > bestStars or (stars == bestStars and distance < bestDistance)) then
				best, bestStars, bestDistance = player, stars, distance
			end
		end
	end
	return best
end

-- Policías de la plantilla de estrellas de un jugador (un cazador sigue contando para quien lo invocó).
local function rosterCops(player: Player): { Cop }
	local list = {}
	for _, cop in cops do
		if cop.state ~= "patrol" and (cop.rosterFor or cop.owner) == player then
			table.insert(list, cop)
		end
	end
	return list
end

-- Guardias: giro suave hacia un ángulo (radianes alrededor de Y) para que el cono de visión barra.
local function turnToward(cop: Cop, targetYaw: number, tick: number)
	local look = cop.root.CFrame.LookVector
	local current = math.atan2(-look.X, -look.Z)
	local delta = (targetYaw - current + math.pi) % (2 * math.pi) - math.pi
	local limit = math.rad(Tuning.get("Guard.TurnDegreesPerSecond")) * tick
	cop.root.CFrame = CFrame.new(cop.root.Position) * CFrame.Angles(0, current + math.clamp(delta, -limit, limit), 0)
	cop.root.AssemblyAngularVelocity = Vector3.zero
end

local function pointYaw(point: BasePart): number
	local look = point.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function arriveAtPoint(cop: Cop, now: number)
	cop.state = "patrol"
	cop.phase = "wait"
	cop.phaseAt = now
	cop.phaseUntil = now + Tuning.get("Guard.WaitSeconds")
	if cop.humanoid then
		cop.humanoid:MoveTo(cop.root.Position)
	end
end

-- Se teletransporta a su punto de guardia (se perdió o no llegó a tiempo).
local function teleportToPoint(cop: Cop, now: number)
	local post = cop.post
	if not post then
		return
	end
	local point = post.points[cop.postIndex]
	cop.model:PivotTo(CFrame.new(point.Position + Vector3.new(0, 1.5, 0)) * point.CFrame.Rotation)
	cop.root.AssemblyLinearVelocity = Vector3.zero
	cop.path = nil
	cop.lastPosition = cop.root.Position
	cop.lastMoveAt = now
	arriveAtPoint(cop, now)
end

local function spawnGuard(post: Post, now: number)
	local point = post.points[1]
	local cop = spawnCop(post.copType, point.Position + Vector3.new(0, 1.5, 0), nil, false)
	if not cop then
		post.respawnAt = now + Tuning.get("Guard.RespawnSeconds")
		return
	end
	cop.post = post
	cop.postIndex = 1
	post.cop = cop
	cop.model:PivotTo(CFrame.new(point.Position + Vector3.new(0, 1.5, 0)) * point.CFrame.Rotation)
	arriveAtPoint(cop, now)
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
	-- La guardia parada no gira sola: mira donde le toca.
	if cop.post and humanoid then
		humanoid.AutoRotate = cop.state ~= "patrol" or cop.phase == "walk"
	end
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
					local range = visionRange(cop, player)
					local fill = (
						Tuning.get("Detect.FillSecondsNear")
						+ (Tuning.get("Detect.FillSecondsFar") - Tuning.get("Detect.FillSecondsNear")) * math.clamp(distance / range, 0, 1)
					) * alertOf(player, "AlertFillByStar")
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

	-- Un policía de patrulla que detecta a alguien lo persigue: al más buscado, no al primero que ve.
	if cop.state == "patrol" or cop.state == "suspicious" or cop.state == "search" or cop.state == "return" then
		local target = mostWanted(visibleTo)
		if target then
			cop.owner = target
			cop.ambient = false
			cop.walker = false
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
				standDown(cop, now)
			end
		end
		return
	end

	if cop.state == "suspicious" then
		moveTo(cop, cop.destination or cop.root.Position, now)
		if cop.destination and (cop.root.Position - cop.destination).Magnitude < 5 or now > cop.searchUntil then
			setAlert(cop, "")
			if cop.post then
				cop.state = "return"
				cop.returnAt = now + Tuning.get("Guard.ReturnSeconds")
			else
				cop.state = "patrol"
				cop.destination = nil
			end
		end
		return
	end

	-- Guardia que perdió al jugador (o oyó algo): vuelve a su último punto; si tarda, se teletransporta.
	if cop.state == "return" and cop.post then
		local point = cop.post.points[cop.postIndex]
		moveTo(cop, point.Position, now)
		if flat(point.Position - cop.root.Position).Magnitude < Tuning.get("Guard.ArriveRadius") then
			arriveAtPoint(cop, now)
		elseif now >= cop.returnAt then
			teleportToPoint(cop, now)
		end
		return
	end

	if cop.def.flying then
		return
	end

	-- Guardia de patrulla: llega a un punto, espera, mira de derecha a izquierda y pasa al siguiente.
	local post = cop.post
	if post then
		local point = post.points[cop.postIndex]
		if cop.phase == "walk" then
			moveTo(cop, point.Position, now)
			if flat(point.Position - cop.root.Position).Magnitude < Tuning.get("Guard.ArriveRadius") then
				arriveAtPoint(cop, now)
			elseif now - cop.phaseAt > Tuning.get("Guard.WalkTimeoutSeconds") then
				teleportToPoint(cop, now)
			end
			return
		end
		if humanoid then
			humanoid:MoveTo(cop.root.Position)
		end
		local half = math.rad(Tuning.get("Guard.ScanDegrees")) / 2
		local base = pointYaw(point)
		if cop.phase == "wait" then
			turnToward(cop, base - half, tick) -- se pone a mirar al extremo derecho
			if now >= cop.phaseUntil then
				cop.phase = "scan"
				cop.phaseAt = now
			end
		else
			local progress = math.clamp((now - cop.phaseAt) / Tuning.get("Guard.ScanSeconds"), 0, 1)
			turnToward(cop, base - half + 2 * half * progress, tick) -- barre hasta el extremo izquierdo
			if progress >= 1 then
				if #post.points > 1 then
					cop.postIndex = cop.postIndex % #post.points + 1
					cop.phase = "walk"
					cop.phaseAt = now
				else
					cop.phase = "wait"
					cop.phaseUntil = now + Tuning.get("Guard.WaitSeconds")
				end
			end
		end
		return
	end

	-- Caminante: va hasta otro punto de la ciudad y desaparece si nadie lo está mirando.
	if cop.walker then
		if not cop.destination then
			cop.destination = pickWalkerGoal(cop.root.Position)
			if not cop.destination then
				removeCop(cop)
				return
			end
		end
		local arrived = flat(cop.destination - cop.root.Position).Magnitude < 6
		if arrived or now > cop.walkerUntil then
			if not playerWithin(cop.root.Position, Tuning.get("Cops.WalkerVanishDistance")) then
				removeCop(cop)
				return
			end
			-- Hay alguien cerca: sigue de largo hasta otro punto en vez de esfumarse a la vista.
			cop.destination = pickWalkerGoal(cop.root.Position)
			cop.walkerUntil = now + 20
		end
		if cop.destination then
			moveTo(cop, cop.destination, now)
		end
		return
	end

	-- Patrulla antigua: va de un punto a otro con pausas.
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
		for _, cop in rosterCops(player) do
			have[cop.def.id] = (have[cop.def.id] or 0) + 1
			total += 1
		end
		if #want == 0 then
			-- Sin estrellas: los perseguidores que quedan se retiran (volverán a patrullar o desaparecen).
			for _, cop in rosterCops(player) do
				if cop.owner ~= player then
					-- Un cazador que ahora persigue a otro jugador buscado pasa a contar para ese jugador.
					cop.rosterFor = cop.owner
				elseif cop.state ~= "search" and now - cop.sawTargetAt > 1.5 then
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
							cop.rosterFor = player
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
		if
			patrolNear < Tuning.get("Cops.PatrolPerPlayer")
			and #options.spawnPoints > 0
			and not options.isProtected(player)
			and now >= (nextWalkerAt[player] or 0)
		then
			local candidates = {}
			for _, part in options.spawnPoints do
				local distance = (part.Position - root.Position).Magnitude
				if distance >= 110 and distance <= Tuning.get("Cops.PatrolRadius") then
					table.insert(candidates, part.Position)
				end
			end
			if #candidates > 0 then
				local start = candidates[random:NextInteger(1, #candidates)]
				local goal = pickWalkerGoal(start)
				local walker = if goal then spawnCop(options.patrolType(player), start, nil, true) else nil
				if walker then
					walker.walker = true
					walker.destination = goal
					walker.walkerUntil = now + Tuning.get("Cops.WalkerMaxSeconds")
					nextWalkerAt[player] = now + random:NextNumber(Tuning.get("Cops.WalkerSpawnMin"), Tuning.get("Cops.WalkerSpawnMax"))
				end
			end
		end
	end
	-- Guardias: cada puesto tiene a su policía mientras haya un jugador cerca.
	for _, post in posts do
		if not post.cop and now >= post.respawnAt and nearestPlayer(post.points[1].Position, Tuning.get("Guard.ActivateRadius")) then
			spawnGuard(post, now)
		end
	end
	-- Cazadores: van a por el jugador con más estrellas, no al más cercano.
	for _, cop in cops do
		if cop.def.hunter and cop.owner and cop.state ~= "patrol" and now >= cop.knockedUntil then
			local best = topWanted(cop.root.Position)
			if best and best ~= cop.owner and options.starsFor(best) > options.starsFor(cop.owner) then
				local target = rootOf(best)
				cop.owner = best
				cop.state = "chase"
				cop.lastSeen = if target then target.Position else cop.lastSeen
				cop.sawTargetAt = now
				cop.grabTimer = 0
				setAlert(cop, "!")
			end
		end
	end
	-- Retira lo que quedó lejos de todos o a quien ya no existe.
	for _, cop in cops do
		local near = nearestPlayer(cop.root.Position, Tuning.get("Cops.DespawnDistance"))
		if not near or (not cop.post and cop.owner and cop.owner.Parent ~= Players) then
			removeCop(cop)
		elseif cop.post and cop.owner and cop.owner.Parent ~= Players then
			standDown(cop, now)
		elseif cop.state == "search" and cop.owner and Tuning.get("Cops.SearchSeconds") and now > cop.searchUntil + 6 then
			standDown(cop, now)
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
	posts = {}
	local byId: { [string]: Post } = {}
	for _, part in opts.guardPosts or {} do
		local id = part:GetAttribute("Post")
		if type(id) == "string" then
			local post = byId[id]
			if not post then
				local copType = part:GetAttribute("CopType")
				post = { id = id, points = {}, copType = if type(copType) == "string" then copType else "patata", cop = nil, respawnAt = 0 }
				byId[id] = post
				table.insert(posts, post)
			end
			table.insert(post.points, part)
		end
	end
	for _, post in posts do
		table.sort(post.points, function(a, b)
			return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
		end)
	end
	folder = Workspace:FindFirstChild("Cops") :: Folder? or Instance.new("Folder")
	folder.Name = "Cops"
	folder.Parent = Workspace
end

function Cops.start()
	Players.PlayerRemoving:Connect(function(player)
		Cops.dismiss(player)
		sight[player] = nil
		nextSpawnAt[player] = nil
		nextWalkerAt[player] = nil
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
			if cop.post then
				standDown(cop, os.clock()) -- la guardia no se pierde: vuelve a su puesto
			else
				removeCop(cop)
			end
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
