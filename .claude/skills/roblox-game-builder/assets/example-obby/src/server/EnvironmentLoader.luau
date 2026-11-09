--[[
	EnvironmentLoader · plantilla del contrato de la fábrica (roblox-game-builder).

	Aplica el pase de arte de ReplicatedStorage.Shared.Environment
	(src/shared/Environment.json, escrito por roblox-environment-artist) sobre los
	niveles que construyó LevelLoader, sin cambiar lo jugable:

	  - aspecto de cada pieza por tipo: color, material, variante de material y
	    texturas. Cambiar el material no cambia la física: la pieza conserva las
	    propiedades físicas del material original;
	  - peligros, checkpoints, metas y coleccionables siempre con el color de su
	    rol del tema (hazard, interactive, goal y reward);
	  - adornos sin colisión: borde, guarda, baldosas, roca, pilar y base en las
	    piezas; zócalo, cornisa, franja y pilastras en los muros;
	  - props armados con Parts a partir de prefabs de datos, y modelos del usuario
	    (ServerStorage.EnvironmentAssets) con su animación;
	  - terreno, luces, sonidos, nubes, colores del terreno y el preset de
	    iluminación del tema.

	Nunca cambia posición, tamaño, forma, transparencia ni colisión de una pieza de
	nivel. Los assets del usuario llegan declarados en Environment.json; aquí no hay
	IDs. Formato: references/environment-format.md del environment artist.
	Uso: references/hooks.md del builder. La geometría de los adornos es la misma
	que calcula scripts/environment_scene.py del environment artist.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local EnvironmentLoader = {}

export type Dressed = {
	folder: Folder,
	props: { [string]: { [string]: Model } }, -- por id de nivel y de prop
	parts: number, -- piezas de decoración creadas (adornos y props)
	lights: number,
}

-- Tipos de pieza cuyo color es siempre el de su rol: el jugador los reconoce por él.
EnvironmentLoader.LockedRoles = table.freeze({
	hazard = "hazard",
	checkpoint = "interactive",
	goal = "goal",
	collectible = "reward",
})

local WALKABLE = { platform = true, spawn = true, checkpoint = true, goal = true }
local GENERAL = { platform = true, spawn = true, checkpoint = true, goal = true, wall = true, prop = true }
local WALLS = { wall = true, prop = true }
local DRESSING_KINDS = {
	trim = GENERAL,
	rock = GENERAL,
	pillar = GENERAL,
	base = GENERAL,
	border = WALKABLE,
	grid = WALKABLE,
	checker = WALKABLE,
	baseboard = WALLS,
	cornice = WALLS,
	band = WALLS,
	pilasters = WALLS,
}
local BLOCK_ONLY = {
	trim = true,
	border = true,
	grid = true,
	checker = true,
	base = true,
	baseboard = true,
	cornice = true,
	band = true,
	pilasters = true,
}
local ALL_FACES = { "Top", "Bottom", "Front", "Back", "Left", "Right" }
local SIDE_FACES = { "Front", "Back", "Left", "Right" }
local EDGE = 0.02 -- los adornos de superficie se separan de los bordes para no compartir plano con otras piezas
local DEFAULT_PILLAR_DEPTH = 20
local SHADOW_MIN_SIZE = 4 -- las piezas de decoración más chicas no proyectan sombra

type Box = { center: Vector3, size: Vector3, yaw: number }

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

local function angles(degrees: Vector3): CFrame
	return CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

-- Material por nombre de Enum.Material ("Slate") o por rol de Theme.materials ("surface").
local function toMaterial(reference: any): Enum.Material
	return toEnum(Enum.Material, reference) or Style.material(tostring(reference))
end

local function positive(value: any, default: number): number
	local number = tonumber(value)
	return if number and number > 0 then number else default
end

local function options(value: any): { [string]: any }
	return if type(value) == "table" then value else { color = value }
end

local function fileStem(path: any): string
	return string.match(tostring(path), "([^/\\]+)%.[^.]+$") or tostring(path)
end

-- Número estable entre -1 y 1 a partir de un texto (variación de color por pieza).
local function hashUnit(text: string): number
	local hash = 7
	for index = 1, #text do
		hash = (hash * 31 + string.byte(text, index)) % 1000003
	end
	return (hash % 2001) / 1000 - 1
end

local function vary(color: Color3, amount: number, key: string): Color3
	local hue, saturation, value = color:ToHSV()
	return Color3.fromHSV(hue, saturation, math.clamp(value * (1 + amount * hashUnit(key)), 0, 1))
end

local function merge(target: { [string]: any }, source: any)
	if type(source) == "table" then
		for key, value in source do
			target[key] = value
		end
	end
end

local function decorationPart(className: string?): BasePart
	local part = Instance.new(className or "Part") :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function finish(part: BasePart, folder: Instance, dressed: Dressed)
	part.CastShadow = math.max(part.Size.X, part.Size.Y, part.Size.Z) >= SHADOW_MIN_SIZE
	part.Parent = folder
	dressed.parts += 1
end

local function addLight(parent: Instance, spec: any, dressed: Dressed)
	local lightType = if spec.type == "Spot" or spec.type == "Surface" then spec.type else "Point"
	local light = Instance.new(lightType .. "Light") :: any
	light.Color = Style.color(spec.color or "text")
	light.Brightness = tonumber(spec.brightness) or 1
	light.Range = tonumber(spec.range) or 12
	light.Shadows = spec.shadows == true
	if lightType ~= "Point" then
		light.Angle = tonumber(spec.angle) or 90
		light.Face = toEnum(Enum.NormalId, spec.face) or Enum.NormalId.Bottom
	end
	light.Parent = parent
	dressed.lights += 1
end

-- Estilo final de una pieza: tipo global → tipo del nivel → "moving" (si se mueve) → pieza.
local function styleFor(environment: any, levelEnvironment: any, piece: any): { [string]: any }
	local style = {}
	local global = environment.pieces or {}
	local level = levelEnvironment.pieces or {}
	merge(style, global[piece.kind])
	merge(style, level[piece.kind])
	if piece.motion ~= nil and piece.kind ~= "hazard" then
		merge(style, global.moving)
		merge(style, level.moving)
	end
	merge(style, levelEnvironment.overrides and levelEnvironment.overrides[piece.id])
	return style
end

local function keepPhysics(part: BasePart)
	-- La física queda la del material original: el pase de arte no cambia el juego.
	if part.CustomPhysicalProperties == nil then
		part.CustomPhysicalProperties = PhysicalProperties.new(part.Material)
	end
end

local function applyTexture(part: BasePart, kind: string, value: any, assets: { [string]: any })
	local spec = if type(value) == "table" then value else { asset = value }
	local asset = assets[spec.asset]
	if type(asset) ~= "table" or asset.kind ~= "texture" then
		warn(`[EnvironmentLoader] {part.Name}: la textura "{spec.asset}" no está declarada en assets`)
		return
	end
	local tile = spec.studsPerTile or 8
	local tileU = if type(tile) == "table" then tonumber(tile[1]) or 8 else tonumber(tile) or 8
	local tileV = if type(tile) == "table" then tonumber(tile[2]) or 8 else tonumber(tile) or 8
	local faces = spec.faces or (if WALKABLE[kind] then { "Top" } elseif kind == "wall" then SIDE_FACES else ALL_FACES)
	for _, faceName in faces do
		local face = toEnum(Enum.NormalId, faceName)
		if face then
			local texture = Instance.new("Texture")
			texture.Name = "EnvironmentTexture_" .. faceName
			texture.Texture = asset.id
			texture.Face = face
			texture.StudsPerTileU = tileU
			texture.StudsPerTileV = tileV
			texture.Transparency = tonumber(spec.transparency) or 0
			if spec.color ~= nil then
				texture.Color3 = Style.color(spec.color)
			end
			texture.Parent = part
		end
	end
end

local function applyLook(part: BasePart, piece: any, style: { [string]: any }, key: string, assets: { [string]: any })
	if style.material ~= nil then
		keepPhysics(part)
		part.Material = toMaterial(style.material)
	end
	if style.materialVariant ~= nil then
		local asset = assets[style.materialVariant]
		if type(asset) == "table" and asset.kind == "materialVariant" then
			keepPhysics(part)
			part.Material = toMaterial(asset.base)
			part.MaterialVariant = asset.name or fileStem(asset.file)
		else
			warn(`[EnvironmentLoader] {key}: la variante "{style.materialVariant}" no está declarada en assets`)
		end
	end
	local locked = EnvironmentLoader.LockedRoles[piece.kind]
	if locked then
		part.Color = Style.color(locked)
	elseif style.color ~= nil then
		local color = Style.color(style.color)
		local amount = tonumber(style.variation)
		if amount and amount > 0 then
			color = vary(color, math.min(amount, 0.15), key)
		end
		part.Color = color
	end
	if style.texture ~= nil then
		applyTexture(part, piece.kind, style.texture, assets)
	end
end

local function dressingLook(value: any, part: BasePart): (Color3, Enum.Material)
	if type(value) == "table" then
		return Style.color(value.color or "surfaceAlt"), if value.material then toMaterial(value.material) else part.Material
	end
	return Style.color(tostring(value)), part.Material
end

-- Altura del peligro más alto que está debajo de la pieza, o nil.
local function floorBelow(part: BasePart, hazards: { BasePart }): number?
	local bottom = part.Position.Y - part.Size.Y / 2
	local best: number? = nil
	for _, hazard in hazards do
		local offset = part.Position - hazard.Position
		local top = hazard.Position.Y + hazard.Size.Y / 2
		if math.abs(offset.X) <= hazard.Size.X / 2 and math.abs(offset.Z) <= hazard.Size.Z / 2 and top < bottom then
			best = if best then math.max(best, top) else top
		end
	end
	return best
end

-- Caras laterales a adornar: eje normal, signo, largo, medio espesor y si se extiende en las esquinas.
local function wallFaces(sizeX: number, sizeZ: number): { { any } }
	if sizeX >= sizeZ * 2 then
		return { { "z", 1, sizeX, sizeZ / 2, false }, { "z", -1, sizeX, sizeZ / 2, false } }
	elseif sizeZ >= sizeX * 2 then
		return { { "x", 1, sizeZ, sizeX / 2, false }, { "x", -1, sizeZ, sizeX / 2, false } }
	end
	return {
		{ "x", 1, sizeZ, sizeX / 2, true },
		{ "x", -1, sizeZ, sizeX / 2, true },
		{ "z", 1, sizeX, sizeZ / 2, false },
		{ "z", -1, sizeX, sizeZ / 2, false },
	}
end

-- Tira pegada a una cara lateral, en coordenadas de la pieza.
local function faceBox(axis: string, sign: number, half: number, protrude: number, along: number, y: number, length: number, height: number): Box
	local offset = sign * (half + protrude / 2)
	if axis == "z" then
		return { center = Vector3.new(along, y, offset), size = Vector3.new(length, height, protrude), yaw = 0 }
	end
	return { center = Vector3.new(offset, y, along), size = Vector3.new(protrude, height, length), yaw = 0 }
end

-- Piezas de un adorno de bloque, en coordenadas de la pieza.
local function dressingBoxes(name: string, value: any, size: Vector3, dressings: { [string]: any }): { Box }
	local spec = options(value)
	local x, y, z = size.X, size.Y, size.Z
	local top, bottom = y / 2, -y / 2
	local boxes: { Box } = {}
	local function add(center: Vector3, boxSize: Vector3, yaw: number?)
		table.insert(boxes, { center = center, size = boxSize, yaw = yaw or 0 })
	end
	if name == "trim" then
		local width = positive(spec.width, math.clamp(math.min(x, z) * 0.08, 0.2, 0.5))
		local height = 0.1
		local level = top + height / 2
		add(Vector3.new(0, level, z / 2 - EDGE - width / 2), Vector3.new(x - 2 * EDGE, height, width))
		add(Vector3.new(0, level, -z / 2 + EDGE + width / 2), Vector3.new(x - 2 * EDGE, height, width))
		add(Vector3.new(x / 2 - EDGE - width / 2, level, 0), Vector3.new(width, height, z - 2 * EDGE - 2 * width))
		add(Vector3.new(-x / 2 + EDGE + width / 2, level, 0), Vector3.new(width, height, z - 2 * EDGE - 2 * width))
	elseif name == "border" then
		local inset = math.max(math.min(positive(spec.inset, 2), math.min(x, z) / 4), EDGE)
		local width = positive(spec.width, math.clamp(math.min(x, z) * 0.03, 0.4, 1.5))
		local height = 0.08
		local level = top + height / 2
		local halfX, halfZ = x / 2 - inset, z / 2 - inset
		if 2 * halfZ - 2 * width > 0 and 2 * halfX > 0 then
			add(Vector3.new(0, level, halfZ - width / 2), Vector3.new(2 * halfX, height, width))
			add(Vector3.new(0, level, -halfZ + width / 2), Vector3.new(2 * halfX, height, width))
			add(Vector3.new(halfX - width / 2, level, 0), Vector3.new(width, height, 2 * halfZ - 2 * width))
			add(Vector3.new(-halfX + width / 2, level, 0), Vector3.new(width, height, 2 * halfZ - 2 * width))
		end
	elseif name == "grid" then
		local spacing = math.max(positive(spec.spacing, 8), 2)
		local width = positive(spec.width, 0.15)
		local height = 0.05
		local level = top + height / 2
		for k = 1, math.max(0, math.ceil(x / spacing - 1e-9)) - 1 do
			add(Vector3.new(-x / 2 + k * spacing, level, 0), Vector3.new(width, height, z - 2 * EDGE))
		end
		for k = 1, math.max(0, math.ceil(z / spacing - 1e-9)) - 1 do
			add(Vector3.new(0, level, -z / 2 + k * spacing), Vector3.new(x - 2 * EDGE, height, width))
		end
	elseif name == "checker" then
		local spacing = math.max(positive(spec.spacing, 8), 2)
		local countX, countZ = math.max(1, math.floor(x / spacing)), math.max(1, math.floor(z / spacing))
		local tileX, tileZ = x / countX, z / countZ
		local height = 0.04
		for i = 0, countX - 1 do
			for j = 0, countZ - 1 do
				if (i + j) % 2 == 0 then
					add(
						Vector3.new(-x / 2 + tileX * (i + 0.5), top + height / 2, -z / 2 + tileZ * (j + 0.5)),
						Vector3.new(tileX - 2 * EDGE, height, tileZ - 2 * EDGE)
					)
				end
			end
		end
	elseif name == "base" then
		local depth = positive(spec.depth, 4)
		add(Vector3.new(0, bottom - depth / 2, 0), Vector3.new(math.max(x - 0.1, 0.05), depth, math.max(z - 0.1, 0.05)))
	elseif name == "rock" then
		local height = math.clamp(math.min(x, z) * 0.5, 1, 6)
		add(Vector3.new(0, bottom - height / 2, 0), Vector3.new(x * 0.85, height, z * 0.85))
		add(Vector3.new(0, bottom - height * 1.4, 0), Vector3.new(x * 0.55, height * 0.8, z * 0.55), 15)
	elseif name == "baseboard" or name == "cornice" or name == "band" then
		local protrude = if name == "baseboard" then 0.2 elseif name == "cornice" then 0.3 else 0.1
		local height, level
		if name == "baseboard" then
			height = positive(spec.height, math.clamp(y * 0.06, 0.4, 1.2))
			level = bottom + height / 2
		elseif name == "cornice" then
			height = positive(spec.height, 0.6)
			level = top - EDGE - height / 2
		else
			height = positive(spec.height, 0.5)
			local at = tonumber(spec.at)
			level = bottom + y * (if at and at > 0 and at < 1 then at else 0.62)
		end
		for _, face in wallFaces(x, z) do
			local length = if face[5] then face[3] + 2 * protrude else face[3] - 2 * EDGE
			table.insert(boxes, faceBox(face[1], face[2], face[4], protrude, 0, level, length, height))
		end
	elseif name == "pilasters" then
		local width = positive(spec.width, 1.2)
		local spacing = positive(spec.spacing, 12)
		local cap = if dressings.cornice ~= nil then positive(options(dressings.cornice).height, 0.6) else 0.05
		local low, high = bottom + 0.02, top - cap
		if high > low then
			for _, face in wallFaces(x, z) do
				local length = face[3]
				local spots = {}
				if length <= 2 * width + 0.1 then
					spots = { 0 }
				else
					local count = math.max(2, math.floor((length - width - 0.1) / spacing) + 1)
					local first, last = -length / 2 + width / 2 + 0.05, length / 2 - width / 2 - 0.05
					for k = 0, count - 1 do
						table.insert(spots, first + (last - first) * k / (count - 1))
					end
				end
				for _, along in spots do
					table.insert(boxes, faceBox(face[1], face[2], face[4], 0.25, along, (low + high) / 2, width, high - low))
				end
			end
		end
	end
	return boxes
end

local function dress(part: BasePart, piece: any, style: { [string]: any }, hazards: { BasePart }, folder: Instance, dressed: Dressed)
	local dressing = style.dressing
	if type(dressing) ~= "table" or piece.motion ~= nil then
		return
	end
	local isBlock = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block and piece.kind ~= "truss"
	for name, value in dressing do
		local kinds = DRESSING_KINDS[name]
		if not kinds or not kinds[piece.kind] or (BLOCK_ONLY[name] and not isBlock) then
			continue
		end
		local color, material = dressingLook(value, part)
		if name == "pillar" then
			local size = part.Size
			local bottom = part.Position.Y - size.Y / 2
			local floor = floorBelow(part, hazards)
			local depth = if floor then bottom - floor else DEFAULT_PILLAR_DEPTH
			if depth > 0.5 then
				local width = math.max(math.min(size.X, size.Z) * 0.3, 0.6)
				local pillar = decorationPart()
				pillar.Name = `{piece.id}_pillar`
				pillar.Size = Vector3.new(width, depth, width)
				pillar.CFrame = CFrame.new(part.Position.X, bottom - depth / 2, part.Position.Z)
				pillar.Color = color
				pillar.Material = material
				finish(pillar, folder, dressed)
			end
		else
			for index, box in dressingBoxes(name, value, part.Size, dressing) do
				local deco = decorationPart()
				deco.Name = `{piece.id}_{name}{index}`
				deco.Size = box.size
				deco.CFrame = part.CFrame * CFrame.new(box.center) * CFrame.Angles(0, math.rad(box.yaw), 0)
				deco.Color = color
				deco.Material = material
				finish(deco, folder, dressed)
			end
		end
	end
end

local function resolveColor(slot: any, prop: any, prefab: any): string
	local reference = (prop.colors and prop.colors[slot]) or (prefab.colors and prefab.colors[slot]) or slot
	return tostring(reference)
end

-- Arma un prop: cada parte del prefab ocupa una fracción de la caja del prop.
local function buildProp(prop: any, prefab: any, origin: Vector3, folder: Instance, dressed: Dressed): Model
	local model = Instance.new("Model")
	model.Name = tostring(prop.id)
	local box = toVector(prop.size, toVector(prefab.size, Vector3.new(4, 4, 4)))
	local frame = CFrame.new(origin + toVector(prop.position, Vector3.zero)) * CFrame.Angles(0, math.rad(tonumber(prop.yaw) or 0), 0)
	local collide = prop.collide == true
	for index, spec in prefab.parts or {} do
		local center = toVector(spec.center, Vector3.zero) * box
		local extent = toVector(spec.size, Vector3.one) * box
		local shape = spec.shape or "Block"
		local part = decorationPart(if shape == "Wedge" then "WedgePart" else "Part")
		part.Name = `{prop.id}_{index}`
		local orientation = CFrame.identity
		if shape == "Ball" then
			local diameter = math.min(extent.X, extent.Y, extent.Z)
			local shaped = part :: Part
			shaped.Shape = Enum.PartType.Ball
			part.Size = Vector3.new(diameter, diameter, diameter)
		elseif shape == "Cylinder" then
			-- El largo de un cilindro de Roblox va sobre su eje X: se gira hacia el eje pedido.
			local axis = spec.axis or "Y"
			local shaped = part :: Part
			shaped.Shape = Enum.PartType.Cylinder
			if axis == "X" then
				part.Size = Vector3.new(extent.X, math.min(extent.Y, extent.Z), math.min(extent.Y, extent.Z))
			elseif axis == "Z" then
				part.Size = Vector3.new(extent.Z, math.min(extent.X, extent.Y), math.min(extent.X, extent.Y))
				orientation = CFrame.Angles(0, math.rad(90), 0)
			else
				part.Size = Vector3.new(extent.Y, math.min(extent.X, extent.Z), math.min(extent.X, extent.Z))
				orientation = CFrame.Angles(0, 0, math.rad(90))
			end
		else
			part.Size = extent
		end
		part.CFrame = frame * CFrame.new(center) * angles(toVector(spec.rotation, Vector3.zero)) * orientation
		part.Color = Style.color(resolveColor(spec.color or "secondary", prop, prefab))
		part.Material = toMaterial(spec.material or "SmoothPlastic")
		part.Transparency = math.clamp(tonumber(spec.transparency) or 0, 0, 0.9)
		part.CanCollide = collide
		part.CanQuery = collide
		if type(spec.light) == "table" then
			local light = table.clone(spec.light)
			light.color = resolveColor(spec.light.color or "light", prop, prefab)
			addLight(part, light, dressed)
		end
		finish(part, model, dressed)
	end
	model.Parent = folder
	return model
end

local function playAnimation(model: Model, asset: any, key: string)
	local animator = model:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		local controller = model:FindFirstChildWhichIsA("AnimationController", true) or model:FindFirstChildWhichIsA("Humanoid", true)
		if controller then
			animator = Instance.new("Animator")
			animator.Parent = controller
		end
	end
	if not animator then
		warn(`[EnvironmentLoader] {key}: el modelo no tiene AnimationController ni Humanoid; no se puede animar`)
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = asset.id
	local ok, err = pcall(function()
		local track = (animator :: Animator):LoadAnimation(animation)
		track.Looped = true
		track:Play()
	end)
	if not ok then
		-- Suele ser un permiso: la animación debe ser del dueño de la experiencia.
		warn(`[EnvironmentLoader] {key}: no se pudo reproducir la animación: {err}`)
	end
end

-- Coloca un modelo del usuario (ServerStorage.EnvironmentAssets) dentro de la caja del prop.
local function buildModel(prop: any, asset: any, animation: any, origin: Vector3, folder: Instance, dressed: Dressed): Model?
	local library = ServerStorage:FindFirstChild("EnvironmentAssets")
	local source = library and library:FindFirstChild(fileStem(asset.file))
	if not source then
		warn(`[EnvironmentLoader] {prop.id}: falta ServerStorage.EnvironmentAssets.{fileStem(asset.file)}; revisa default.project.json`)
		return nil
	end
	local copy = source:Clone()
	local model: Model
	if copy:IsA("Model") then
		model = copy
	else
		model = Instance.new("Model")
		copy.Parent = model
	end
	model.Name = tostring(prop.id)
	-- Un adorno no necesita código: los modelos de terceros pueden traer scripts, y se borran.
	local removed = 0
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
			removed += 1
		end
	end
	if removed > 0 then
		warn(`[EnvironmentLoader] {prop.id}: se borraron {removed} scripts del modelo {fileStem(asset.file)}`)
	end
	local box = toVector(prop.size, toVector(asset.size, Vector3.new(4, 4, 4)))
	local extents = model:GetExtentsSize()
	local factor = math.min(box.X / math.max(extents.X, 1e-3), box.Y / math.max(extents.Y, 1e-3), box.Z / math.max(extents.Z, 1e-3))
	if factor > 0 and math.abs(factor - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * factor)
	end
	local bounds = model:GetBoundingBox()
	local offset = bounds:ToObjectSpace(model:GetPivot())
	local target = CFrame.new(origin + toVector(prop.position, Vector3.zero)) * CFrame.Angles(0, math.rad(tonumber(prop.yaw) or 0), 0)
	model:PivotTo(target * offset)
	local collide = prop.collide == true
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = collide
			item.CanTouch = false
			item.CanQuery = collide
			if animation == nil then
				item.Anchored = true
			end
			dressed.parts += 1
		end
	end
	if animation ~= nil then
		-- Un modelo animado se ancla solo por su raíz: el resto lo mueven sus articulaciones.
		if model.PrimaryPart then
			model.PrimaryPart.Anchored = true
		else
			warn(`[EnvironmentLoader] {prop.id}: un modelo animado necesita PrimaryPart`)
		end
	end
	model.Parent = folder
	if animation ~= nil then
		playAnimation(model, animation, tostring(prop.id))
	end
	return model
end

local function fillTerrain(spec: any, origin: Vector3)
	local terrain = Workspace.Terrain
	local material = toEnum(Enum.Material, spec.material)
	if not material then
		warn(`[EnvironmentLoader] Material de terreno desconocido "{spec.material}"`)
		return
	end
	local position = origin + toVector(spec.position, Vector3.zero)
	local frame = CFrame.new(position) * angles(toVector(spec.rotation, Vector3.zero))
	if spec.shape == "Ball" then
		terrain:FillBall(position, tonumber(spec.radius) or 8, material)
	elseif spec.shape == "Cylinder" then
		terrain:FillCylinder(frame, tonumber(spec.height) or 8, tonumber(spec.radius) or 8, material)
	elseif spec.shape == "Wedge" then
		terrain:FillWedge(frame, toVector(spec.size, Vector3.new(8, 8, 8)), material)
	else
		terrain:FillBlock(frame, toVector(spec.size, Vector3.new(8, 8, 8)), material)
	end
end

local function addSound(spec: any, asset: any, origin: Vector3, folder: Instance)
	local sound = Instance.new("Sound")
	sound.Name = tostring(spec.asset)
	sound.SoundId = asset.id
	sound.Looped = true
	sound.Volume = tonumber(spec.volume) or 0.5
	if type(spec.position) == "table" then
		local holder = decorationPart()
		holder.Name = `Sound_{spec.asset}`
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Transparency = 1
		holder.CastShadow = false
		holder.CFrame = CFrame.new(origin + toVector(spec.position, Vector3.zero))
		holder.Parent = folder
		sound.RollOffMaxDistance = tonumber(spec.range) or 60
		sound.Parent = holder
	else
		sound.Parent = folder -- sin posición se oye en todo el mapa
	end
	sound:Play()
end

-- Preset de iluminación: el del place actual si Environment.json lo define (lighting.places),
-- o el general. Cada place tiene su propio Lighting.
local function presetFor(lighting: any): string
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local placeModule = shared and shared:FindFirstChild("Place")
	if type(lighting.places) == "table" and placeModule and placeModule:IsA("ModuleScript") then
		local ok, Place = pcall(require, placeModule)
		local preset = if ok then lighting.places[(Place :: any).current()] else nil
		if type(preset) == "string" then
			return preset
		end
	end
	return lighting.preset or "default"
end

local function applyWorld(environment: any)
	local lighting = environment.lighting or {}
	Style.applyLighting(presetFor(lighting))
	local terrain = Workspace.Terrain
	if type(environment.terrainColors) == "table" then
		for materialName, reference in environment.terrainColors do
			local material = toEnum(Enum.Material, materialName)
			if material and material ~= Enum.Material.Water then
				terrain:SetMaterialColor(material, Style.color(reference))
			end
		end
	end
	if type(lighting.clouds) == "table" then
		local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Cover = math.clamp(tonumber(lighting.clouds.cover) or 0.5, 0, 1)
		clouds.Density = math.clamp(tonumber(lighting.clouds.density) or 0.5, 0, 1)
		clouds.Color = Style.color(lighting.clouds.color or "text")
		clouds.Enabled = true
		clouds.Parent = terrain
	end
end

-- Aplica el pase de arte sobre los niveles construidos (resultado de LevelLoader.build).
-- Se llama una vez en el servidor, después de LevelLoader.build y antes de dejar jugar.
function EnvironmentLoader.apply(built: any, environment: any): Dressed
	assert(type(built) == "table" and type(built.levels) == "table", "[EnvironmentLoader] apply necesita el resultado de LevelLoader.build")
	assert(type(environment) == "table", "[EnvironmentLoader] Environment no es una tabla")
	if environment.schemaVersion ~= 1 then
		warn(`[EnvironmentLoader] schemaVersion {environment.schemaVersion} no es 1; se intenta aplicar igual`)
	end
	applyWorld(environment)

	local root = Instance.new("Folder")
	root.Name = "Environment"
	local dressed: Dressed = { folder = root, props = {}, parts = 0, lights = 0 }
	local prefabs = environment.prefabs or {}
	local assets = environment.assets or {}
	for _, level in built.levels do
		local levelEnvironment = (environment.levels and environment.levels[level.id]) or {}
		local folder = Instance.new("Folder")
		folder.Name = level.folder.Name
		folder.Parent = root
		local origin = toVector(level.data.origin, Vector3.zero)
		local hazards = level.byKind.hazard or {}

		for _, piece in level.data.pieces or {} do
			local part = level.pieces[piece.id]
			if part then
				local style = styleFor(environment, levelEnvironment, piece)
				applyLook(part, piece, style, `{level.id}/{piece.id}`, assets)
				dress(part, piece, style, hazards, folder, dressed)
			end
		end

		for _, spec in levelEnvironment.terrain or {} do
			fillTerrain(spec, origin)
		end

		local props = {}
		for _, prop in levelEnvironment.props or {} do
			local asset = if prop.asset ~= nil then assets[prop.asset] else nil
			if type(asset) == "table" and asset.kind == "model" then
				local animation = if prop.animation ~= nil then assets[prop.animation] else nil
				props[prop.id] = buildModel(prop, asset, animation, origin, folder, dressed)
			elseif prefabs[prop.prefab] then
				props[prop.id] = buildProp(prop, prefabs[prop.prefab], origin, folder, dressed)
			else
				warn(`[EnvironmentLoader] {level.id}/{prop.id}: no existe el prefab "{prop.prefab}" ni el modelo "{prop.asset}"`)
			end
		end
		dressed.props[level.id] = props

		for _, spec in levelEnvironment.lights or {} do
			local holder = decorationPart()
			holder.Name = tostring(spec.id or "Light")
			holder.Size = Vector3.new(0.2, 0.2, 0.2)
			holder.Transparency = 1
			holder.CastShadow = false
			holder.CFrame = CFrame.new(origin + toVector(spec.position, Vector3.zero))
			holder.Parent = folder
			addLight(holder, spec, dressed)
		end

		for _, spec in levelEnvironment.sounds or {} do
			local asset = assets[spec.asset]
			if type(asset) == "table" and asset.kind == "sound" then
				addSound(spec, asset, origin, folder)
			else
				warn(`[EnvironmentLoader] {level.id}: el sonido "{spec.asset}" no está declarado en assets`)
			end
		end
	end
	root.Parent = Workspace
	return dressed
end

return EnvironmentLoader
