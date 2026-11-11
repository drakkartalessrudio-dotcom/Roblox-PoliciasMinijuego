--[[
	LevelLoader · plantilla del contrato de la fábrica (roblox-game-builder).

	Construye en Workspace los niveles de ReplicatedStorage.Shared.Levels
	(src/shared/Levels.json, escrito por roblox-level-designer) y aplica la física
	declarada. No contiene reglas del juego: etiqueta cada pieza con CollectionService,
	le pone atributos y devuelve las piezas organizadas por nivel para que los
	sistemas del juego conecten su lógica.

	Formato de los datos: references/level-format.md del level designer.
	Uso y semántica de cada tipo de pieza: references/hooks.md del builder.
]]

local CollectionService = game:GetService("CollectionService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local LevelLoader = {}

-- Etiqueta de CollectionService por tipo de pieza.
LevelLoader.Tags = table.freeze({
	spawn = "LevelSpawn",
	platform = "LevelPlatform",
	checkpoint = "Checkpoint",
	goal = "Goal",
	truss = "LevelTruss",
	wall = "LevelWall",
	hazard = "Hazard",
	collectible = "Collectible",
	zone = "Zone",
	prop = "LevelProp",
})

export type BuiltLevel = {
	index: number,
	id: string,
	name: string,
	data: { [string]: any },
	folder: Folder,
	start: BasePart?,
	pieces: { [string]: BasePart },
	byKind: { [string]: { BasePart } },
	checkpoints: { BasePart }, -- ordenados por el atributo Order
}

export type Built = {
	folder: Folder,
	levels: { BuiltLevel },
	byId: { [string]: BuiltLevel },
}

local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic
local DEFAULT_COLOR = Color3.fromRGB(163, 162, 165)
local SERVO_FORCE = 1e6 -- fuerza del servo de las plataformas móviles
local MOTOR_TORQUE = 1e7 -- torque del motor de las piezas giratorias
local NOT_COLLIDING = { collectible = true, zone = true }

local function toVector(value: any, fallback: Vector3): Vector3
	if type(value) ~= "table" then
		return fallback
	end
	return Vector3.new(tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 0)
end

local function toEnum(enum: any, name: any): any
	if type(name) ~= "string" then
		return nil
	end
	local ok, item = pcall(function()
		return enum[name]
	end)
	return if ok then item else nil
end

local function toMaterial(name: any, fallback: Enum.Material): Enum.Material
	if name == nil then
		return fallback
	end
	local material = toEnum(Enum.Material, name)
	if material then
		return material
	end
	warn(`[LevelLoader] Material desconocido "{name}"; se usa {fallback.Name}`)
	return fallback
end

local function toColor(hex: any, fallback: Color3): Color3
	if type(hex) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, hex)
	if ok then
		return color
	end
	warn(`[LevelLoader] Color inválido "{hex}"`)
	return fallback
end

-- Marco cuyo eje X apunta en la dirección dada: es el eje que usan los constraints.
local function axisFrame(axis: Vector3): CFrame
	local reference = if math.abs(axis.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local secondary = (reference - axis * axis:Dot(reference)).Unit
	return CFrame.fromMatrix(Vector3.zero, axis, secondary)
end

local function createAnchor(part: BasePart, folder: Instance): Part
	local anchor = Instance.new("Part")
	anchor.Name = part.Name .. "_Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = part.CFrame
	anchor.Parent = folder
	return anchor
end

local function attachPair(anchor: BasePart, part: BasePart, worldAxis: Vector3): (Attachment, Attachment)
	local attachment0 = Instance.new("Attachment")
	attachment0.CFrame = axisFrame(anchor.CFrame:VectorToObjectSpace(worldAxis))
	attachment0.Parent = anchor
	local attachment1 = Instance.new("Attachment")
	attachment1.CFrame = axisFrame(part.CFrame:VectorToObjectSpace(worldAxis))
	attachment1.Parent = part
	return attachment0, attachment1
end

-- Mueve la pieza con física: deja de estar anclada y un constraint la desplaza, así
-- arrastra a los personajes que están encima. Devuelve true si la pieza quedó móvil.
local function addMotion(part: BasePart, motion: any, folder: Instance): boolean
	if type(motion) ~= "table" then
		return false
	end
	if motion.type == "linear" then
		local offset = toVector(motion.offset, Vector3.zero)
		local distance = offset.Magnitude
		if distance < 0.01 then
			return false
		end
		local halfPeriod = math.max(tonumber(motion.period) or 4, 0.5) / 2
		local anchor = createAnchor(part, folder)
		local attachment0, attachment1 = attachPair(anchor, part, offset.Unit)
		local prismatic = Instance.new("PrismaticConstraint")
		prismatic.Attachment0 = attachment0
		prismatic.Attachment1 = attachment1
		prismatic.ActuatorType = Enum.ActuatorType.Servo
		prismatic.ServoMaxForce = SERVO_FORCE
		prismatic.Speed = distance / halfPeriod
		prismatic.LimitsEnabled = true
		prismatic.LowerLimit = 0
		prismatic.UpperLimit = distance
		prismatic.TargetPosition = 0
		prismatic.Parent = part
		part.Anchored = false
		task.spawn(function()
			local outbound = true
			while part.Parent do
				prismatic.TargetPosition = if outbound then distance else 0
				outbound = not outbound
				task.wait(halfPeriod)
			end
		end)
		return true
	elseif motion.type == "spin" then
		local worldAxis = if motion.axis == "X" then Vector3.xAxis elseif motion.axis == "Z" then Vector3.zAxis else Vector3.yAxis
		local anchor = createAnchor(part, folder)
		local attachment0, attachment1 = attachPair(anchor, part, worldAxis)
		local hinge = Instance.new("HingeConstraint")
		hinge.Attachment0 = attachment0
		hinge.Attachment1 = attachment1
		hinge.ActuatorType = Enum.ActuatorType.Motor
		hinge.AngularVelocity = (tonumber(motion.rpm) or 10) * 2 * math.pi / 60
		hinge.MotorMaxTorque = MOTOR_TORQUE
		hinge.Parent = part
		part.Anchored = false
		return true
	end
	warn(`[LevelLoader] Movimiento desconocido en {part.Name}`)
	return false
end

local function createPart(kind: string, piece: any): BasePart
	if kind == "spawn" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Neutral = true
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0 -- sin ForceField al aparecer
		spawn.Enabled = piece.enabled ~= false
		return spawn
	elseif kind == "truss" then
		return Instance.new("TrussPart")
	end
	local part = Instance.new("Part")
	local shape = toEnum(Enum.PartType, piece.shape)
	if shape then
		part.Shape = shape
	end
	return part
end

type Defaults = { material: Enum.Material, color: Color3 }

local function buildPiece(piece: any, level: BuiltLevel, origin: Vector3, defaults: Defaults, moving: { BasePart }): BasePart?
	local kind = piece.kind
	local tag = LevelLoader.Tags[kind]
	if type(piece.id) ~= "string" or not tag then
		warn(`[LevelLoader] Pieza inválida en el nivel {level.id}: {piece.id}`)
		return nil
	end
	local part = createPart(kind, piece)
	part.Name = piece.id
	part.Anchored = true
	local size = toVector(piece.size, Vector3.new(4, 1, 4))
	part.Size = size
	if (part.Size - size).Magnitude > 0.01 then
		-- Roblox ajusta algunos tamaños (un TrussPart mide 2 x 2 x N): avisa para no construir otro nivel.
		warn(`[LevelLoader] {level.id}/{piece.id}: el tamaño {size} quedó en {part.Size}`)
	end
	local rotation = toVector(piece.rotation, Vector3.zero)
	part.CFrame = CFrame.new(origin + toVector(piece.position, Vector3.zero))
		* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	part.Material = toMaterial(piece.material, defaults.material)
	part.Color = toColor(piece.color, defaults.color)
	part.Transparency = tonumber(piece.transparency) or (if kind == "zone" then 1 else 0)
	if type(piece.collide) == "boolean" then
		part.CanCollide = piece.collide
	else
		part.CanCollide = not NOT_COLLIDING[kind]
	end
	if kind == "zone" then
		part.CanQuery = false
		part.CastShadow = false
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("PieceId", piece.id)
	part:SetAttribute("LevelId", level.id)
	part:SetAttribute("LevelIndex", level.index)
	if kind == "checkpoint" then
		part:SetAttribute("Order", tonumber(piece.order) or 0)
	elseif kind == "hazard" and tonumber(piece.damage) then
		part:SetAttribute("Damage", tonumber(piece.damage))
	elseif kind == "collectible" then
		part:SetAttribute("Value", tonumber(piece.value) or 1)
	elseif kind == "zone" then
		part:SetAttribute("ZoneName", tostring(piece.name))
		if type(piece.post) == "string" then
			-- Punto de ruta de una guardia (zona guard_post): a qué puesto pertenece, en qué orden y quién vigila.
			part:SetAttribute("Post", piece.post)
			part:SetAttribute("Order", tonumber(piece.order) or 0)
			if type(piece.cop) == "string" then
				part:SetAttribute("CopType", piece.cop)
			end
		end
		if type(piece.hideKind) == "string" then
			part:SetAttribute("HideKind", piece.hideKind) -- tipo de una zona "hide": "bush" (por defecto) o "container"
		end
		if type(piece.target) == "string" then
			part:SetAttribute("Target", piece.target) -- a dónde lleva una zona "portal" (id de Destinations)
		end
	end
	CollectionService:AddTag(part, tag)
	part.Parent = level.folder
	if piece.motion ~= nil and addMotion(part, piece.motion, level.folder) then
		table.insert(moving, part)
	end
	return part
end

export type BuildOptions = {
	-- Ids de los niveles a construir, por ejemplo Place.levels(Levels) en un juego con
	-- varios places o el mapa de la ronda actual. Sin "only" se construyen todos.
	only: { string }?,
}

-- Construye los niveles bajo una carpeta "Levels" (en Workspace por defecto). Con
-- options.only construye solo esos; `index` queda en el orden de Levels.json entre los
-- construidos. Para descargar lo construido: built.folder:Destroy().
function LevelLoader.build(data: any, parent: Instance?, options: BuildOptions?): Built
	assert(type(data) == "table" and type(data.levels) == "table" and #data.levels > 0, "[LevelLoader] Levels no tiene niveles en 'levels'")
	if data.schemaVersion ~= 1 then
		warn(`[LevelLoader] schemaVersion {data.schemaVersion} no es 1; se intenta construir igual`)
	end
	local wanted: { [string]: boolean }? = nil
	if options and options.only then
		local set = {}
		for _, id in options.only do
			set[id] = true
		end
		wanted = set
	end
	local defaultsData = if type(data.defaults) == "table" then data.defaults else {}
	local defaults: Defaults = {
		material = toMaterial(defaultsData.material, DEFAULT_MATERIAL),
		color = toColor(defaultsData.color, DEFAULT_COLOR),
	}
	local root = Instance.new("Folder")
	root.Name = "Levels"
	local built: Built = { folder = root, levels = {}, byId = {} }
	local moving: { BasePart } = {}

	local index = 0
	for _, levelData in ipairs(data.levels) do
		if wanted and not wanted[tostring(levelData.id)] then
			continue
		end
		index += 1
		local folder = Instance.new("Folder")
		folder.Name = string.format("%02d_%s", index, tostring(levelData.id))
		folder.Parent = root
		local level: BuiltLevel = {
			index = index,
			id = tostring(levelData.id),
			name = tostring(levelData.name or levelData.id),
			data = levelData,
			folder = folder,
			start = nil,
			pieces = {},
			byKind = {},
			checkpoints = {},
		}
		local origin = toVector(levelData.origin, Vector3.zero)
		for _, piece in ipairs(levelData.pieces or {}) do
			local part = buildPiece(piece, level, origin, defaults, moving)
			if part then
				level.pieces[piece.id] = part
				local list = level.byKind[piece.kind]
				if not list then
					list = {}
					level.byKind[piece.kind] = list
				end
				table.insert(list, part)
			end
		end
		level.start = if type(levelData.start) == "string" then level.pieces[levelData.start] else nil
		if not level.start then
			-- Sin start el juego no sabe dónde poner al jugador: mejor fallar en la primera prueba.
			error(`[LevelLoader] El nivel {level.id} no tiene una pieza start válida; revisa Levels.json con validate_levels.py`)
		end
		local checkpoints = table.clone(level.byKind.checkpoint or {})
		table.sort(checkpoints, function(a, b)
			return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
		end)
		level.checkpoints = checkpoints
		table.insert(built.levels, level)
		built.byId[level.id] = level
	end

	root.Parent = parent or Workspace
	-- El servidor simula las piezas móviles para que ningún cliente controle su física.
	for _, part in moving do
		local ok, err = pcall(function()
			part:SetNetworkOwner(nil)
		end)
		if not ok then
			warn(`[LevelLoader] No se pudo fijar el dueño de red de {part:GetFullName()}: {err}`)
		end
	end
	return built
end

-- Aplica la física de Levels.physics a los personajes que aparezcan desde ahora.
function LevelLoader.applyPhysics(physics: any)
	if type(physics) ~= "table" then
		return
	end
	if type(physics.gravity) == "number" then
		Workspace.Gravity = physics.gravity
	end
	if type(physics.walkSpeed) == "number" then
		StarterPlayer.CharacterWalkSpeed = physics.walkSpeed
	end
	if type(physics.jumpHeight) == "number" then
		StarterPlayer.CharacterUseJumpPower = false
		StarterPlayer.CharacterJumpHeight = physics.jumpHeight
	end
end

-- Aplica la misma física a un Humanoid que ya existe (por ejemplo, en CharacterAdded).
function LevelLoader.applyToHumanoid(humanoid: Humanoid, physics: any)
	if type(physics) ~= "table" then
		return
	end
	if type(physics.walkSpeed) == "number" then
		humanoid.WalkSpeed = physics.walkSpeed
	end
	if type(physics.jumpHeight) == "number" then
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = physics.jumpHeight
	end
end

-- CFrame para colocar un personaje parado sobre el centro de la cara superior de una
-- pieza, aunque esté rotada, mirando en la orientación inicial (-Z).
function LevelLoader.standCFrame(part: BasePart, height: number?): CFrame
	local top = part.CFrame:PointToWorldSpace(Vector3.new(0, part.Size.Y / 2, 0))
	return CFrame.new(top + Vector3.new(0, height or 3, 0))
end

return LevelLoader
