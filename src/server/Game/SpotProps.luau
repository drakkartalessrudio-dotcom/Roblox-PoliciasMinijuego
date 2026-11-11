--[[
	SpotProps · los objetos que hacen visibles los puntos de travesura. Cada punto de
	Levels.json es una zona invisible con un ProximityPrompt: sin esto, el jugador no sabe
	dónde pintar ni dónde tocar. Aquí se construye, con Parts, lo que se ve en cada uno
	y cómo reacciona cuando alguien hace la travesura. Mezcla Areas, Mischief y Net, así que es de Game.

	  Graffiti / Mural Gigante   muro de dos caras con un lienzo a medio pintar (manchas,
	                             goteras, latas y un charco), esquinas de neón que lo marcan y un cartel.
	                             Al completarlo, el mural aparece pintado y estalla confeti
	                             de pintura; vuelve a su estado a medio pintar al pasar el
	                             enfriamiento del punto (Mischief.SpotCooldown).
	  Timbrazo                   fachada de casa con puerta y un timbre luminoso junto a ella. Al
	                             tocarlo el botón se hunde, parpadea, se encienden las ventanas
	                             y todos los clientes cercanos oyen el timbre (Net "spot_fx").

	Todo es decoración: sin colisión ni consulta de rayos, así que no cambia la visión de los
	policías, el ruido, las guardias ni las rutas. El timbre se oye en SpotFeedback.client.luau.
	Un punto de otra travesura sin constructor no se toca (el prompt sigue igual).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Net = require(ReplicatedStorage.Shared.Net)
local Style = require(ReplicatedStorage.Shared.Style)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local Mischief = require(ServerScriptService.Server.Modules.Mischief)

local SpotProps = {}

type Spot = {
	key: string,
	part: BasePart,
	def: Catalog.MischiefDef,
	center: Vector3, -- centro XZ del nivel (respaldo para orientar si no hay un edificio cerca)
	level: any, -- LevelLoader.BuiltLevel del punto
}

-- La cara de edificio más cercana a un punto: hacia dónde mirar y dónde pegarse.
type Facade = {
	part: BasePart,
	normal: Vector3, -- sale del edificio hacia la calle
	tangent: Vector3, -- a lo largo de la fachada
	distance: number, -- studs del punto al plano de la fachada
	limit: number, -- mitad del largo de la fachada
}

-- Lo que el resto del juego puede disparar sobre un punto.
type Prop = {
	started: (() -> ())?, -- alguien arrancó la travesura aquí
	completed: (() -> ())?, -- alguien la completó
}

type Builder = { model: Model, root: CFrame }

local props: { [string]: Prop } = {}
local folder: Folder? = nil

-- Los discos de Roblox (Cylinder) tienen su eje en X: estos giros lo llevan a Z (mirar al frente) o a Y (de pie).
local FACE_Z = CFrame.Angles(0, math.rad(90), 0)
local STAND_Y = CFrame.Angles(0, 0, math.rad(90))

local function paint(name: string): Color3
	return Style.color(name)
end

local function pastel(tint: Color3, amount: number): Color3
	return tint:Lerp(Style.color("snow"), amount)
end

local function shade(tint: Color3, amount: number): Color3
	return tint:Lerp(Style.color("ink"), amount)
end

local function hashOf(text: string): number
	local hash = 7
	for index = 1, #text do
		hash = (hash * 31 + string.byte(text, index)) % 1000003
	end
	return hash
end

-- Altura y material del suelo bajo un punto (nil si no hay nada debajo).
local function groundAt(position: Vector3): (number?, Enum.Material?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if folder then { folder } else {}
	local hit = Workspace:Raycast(position, Vector3.new(0, -40, 0), params)
	if hit then
		return hit.Position.Y, hit.Material
	end
	return nil, nil
end

-- Dirección cardinal (X o Z) hacia el centro del nivel: hacia dónde mira el frente de un prop.
local function facingToCenter(spot: Spot): Vector3
	local offset = Vector3.new(spot.center.X - spot.part.Position.X, 0, spot.center.Z - spot.part.Position.Z)
	if offset.Magnitude < 1 then
		return Vector3.zAxis
	end
	if math.abs(offset.X) > math.abs(offset.Z) then
		return Vector3.new(math.sign(offset.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(offset.Z))
end

local MAX_FACADE_DISTANCE = 14

-- Edificio (prop o muro alto y visible) cuya cara está más cerca del punto, o nil si no hay uno a mano.
local function nearestFacade(spot: Spot): Facade?
	if not spot.level then
		return nil
	end
	local position = spot.part.Position
	local best: Facade? = nil
	for _, kind in { "prop", "wall" } do
		for _, part in spot.level.byKind[kind] or {} do
			if part.Size.Y < 8 or part.Transparency > 0.9 then
				continue
			end
			local localPoint = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			local overX, overZ = math.abs(localPoint.X) - half.X, math.abs(localPoint.Z) - half.Z
			local alongX = overX >= overZ
			local distance = if alongX then overX else overZ
			local lateral = if alongX then overZ else overX
			-- Fuera del edificio, cerca, y frente a la cara (no en una esquina).
			if distance > 0.5 and distance <= MAX_FACADE_DISTANCE and lateral <= 2 and (best == nil or distance < best.distance) then
				local axis = if alongX then part.CFrame.RightVector * math.sign(localPoint.X) else part.CFrame.LookVector * math.sign(localPoint.Z)
				local normal = Vector3.new(axis.X, 0, axis.Z).Unit
				best = {
					part = part,
					normal = normal,
					tangent = normal:Cross(Vector3.yAxis),
					distance = distance,
					limit = if alongX then half.Z else half.X,
				}
			end
		end
	end
	return best
end

-- Lleva `base` hasta dejar `gap` studs entre ella y la fachada, sin que un objeto de `width` studs se pase de la esquina.
local function flushAgainst(facade: Facade, base: Vector3, gap: number, width: number): Vector3
	local moved = base - facade.normal * (facade.distance - gap)
	local lateral = (moved - facade.part.Position):Dot(facade.tangent)
	local room = facade.limit - width / 2 - 0.5
	if room > 0 and math.abs(lateral) > room then
		moved -= facade.tangent * (lateral - math.clamp(lateral, -room, room))
	end
	return moved
end

-- El prompt de la travesura sale del centro de la zona; se lleva hasta el objeto para que se entienda qué se toca.
local function movePrompt(spot: Spot, target: BasePart, offset: Vector3)
	local prompt = spot.part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		local anchor = Instance.new("Attachment")
		anchor.Name = "PromptAnchor"
		anchor.Position = offset
		anchor.Parent = target
		prompt.Parent = anchor
	end
end

-- Una pieza decorativa. `offset` está en el marco local del prop (+Z es el frente).
local function add(
	builder: Builder,
	name: string,
	size: Vector3,
	offset: CFrame,
	tint: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = math.max(size.X, size.Y, size.Z) >= 3
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or Enum.Material.SmoothPlastic
	part.Color = tint
	part.Size = size
	part.CFrame = builder.root * offset
	part.Parent = builder.model
	return part
end

-- Disco que mira al frente (+Z) del marco dado.
local function disc(builder: Builder, name: string, diameter: number, thickness: number, offset: CFrame, tint: Color3, material: Enum.Material?): Part
	return add(builder, name, Vector3.new(thickness, diameter, diameter), offset * FACE_Z, tint, material, Enum.PartType.Cylinder)
end

-- Cilindro de pie (latas, macetas, charcos planos).
local function standing(builder: Builder, name: string, diameter: number, height: number, offset: CFrame, tint: Color3, material: Enum.Material?): Part
	return add(builder, name, Vector3.new(height, diameter, diameter), offset * STAND_Y, tint, material, Enum.PartType.Cylinder)
end

-- Cartel flotante sobre el punto: se ve de lejos y dice qué se hace aquí.
local function addSign(adornee: BasePart, text: string, lift: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpotSign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(200, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	gui.MaxDistance = Tuning.get("SpotFx.SignDistance")
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Style.color("panel")
	frame.BackgroundTransparency = Style.metric("panelTransparency")
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Style.metric("cornerRadius"))
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Style.color("interactive")
	stroke.Thickness = Style.metric("strokeThickness")
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = Style.color("text")
	label.FontFace = Style.font("heading")
	label.TextSize = 24
	label.Parent = frame
	gui.Parent = adornee
end

-- ─── Graffiti ──────────────────────────────────────────────────────────────────

-- Manchas del lienzo a medio pintar: forma, centro (fracción del lienzo), tamaño, giro y color.
local HALF_PAINTED = {
	{ "box", -0.30, 0.24, 0.34, 0.14, 10, "coral" },
	{ "box", -0.21, 0.03, 0.27, 0.12, -7, "cyan" },
	{ "disc", -0.36, -0.22, 0.24, 0, 0, "violet" },
	{ "box", -0.10, -0.26, 0.2, 0.1, 6, "sunny" },
	{ "box", -0.41, 0.02, 0.1, 0.34, 0, "mint" },
}
-- Goteras bajo las manchas: centro X, borde de arriba (fracción del lienzo), largo y color.
local DRIPS = {
	{ -0.37, 0.18, 0.2, "coral" },
	{ -0.15, -0.04, 0.16, "cyan" },
	{ -0.28, -0.3, 0.14, "violet" },
}
-- Mural terminado: lo mismo, pero cubriendo el lienzo entero.
local FULL_MURAL = {
	{ "box", 0, 0, 0.96, 0.94, 0, "skyBlue" },
	{ "disc", 0.27, 0.2, 0.3, 0, 0, "sunny" },
	{ "box", 0, -0.34, 0.96, 0.26, 0, "mint" },
	{ "box", -0.2, 0.12, 0.5, 0.14, 12, "coral" },
	{ "disc", -0.3, -0.14, 0.26, 0, 0, "violet" },
	{ "box", 0.2, -0.12, 0.4, 0.1, -10, "orange" },
	{ "box", 0.3, 0.2, 0.08, 0.34, 0, "snow" },
	{ "box", 0.3, 0.2, 0.34, 0.08, 0, "snow" },
	{ "box", -0.05, 0.3, 0.3, 0.06, -5, "cyan" },
}

local function buildGraffiti(spot: Spot, ground: number): Prop
	local coop = spot.def.coop == true
	local width = if coop then math.max(spot.part.Size.X, spot.part.Size.Z) else 12
	local height = if coop then 10 else 8
	local thickness = 1.2
	local base = Vector3.new(spot.part.Position.X, ground, spot.part.Position.Z)
	local facade = nearestFacade(spot)
	local root: CFrame
	if facade then
		-- Paralelo al edificio, con la espalda a medio stud de la fachada y el frente hacia la calle.
		local flush = flushAgainst(facade, base, 0.5 + thickness / 2, width)
		root = CFrame.lookAt(flush, flush - facade.normal)
	elseif coop then
		root = CFrame.new(base)
	else
		root = CFrame.lookAt(base, base - facingToCenter(spot))
	end
	local model = Instance.new("Model")
	model.Name = spot.key
	local builder: Builder = { model = model, root = root }

	-- Muro, base y remate.
	local wall = add(builder, "Wall", Vector3.new(width, height, thickness), CFrame.new(0, height / 2, 0), Style.color("surfaceAlt"), Enum.Material.Concrete)
	movePrompt(spot, wall, Vector3.new(0, 3 - height / 2, thickness / 2 + 1))
	add(builder, "Footing", Vector3.new(width + 0.4, 0.4, thickness + 0.4), CFrame.new(0, 0.2, 0), Style.color("panel"), Enum.Material.Concrete)
	local coping = add(builder, "Coping", Vector3.new(width + 0.6, 0.5, thickness + 0.6), CFrame.new(0, height + 0.25, 0), Style.color("panelAlt"), Enum.Material.Concrete)

	local canvasW = width - 2.4
	local canvasH = height - 2.8
	local canvasY = height / 2 - 0.1
	local mural: { Part } = {}
	local neon = Style.material("interactive")

	for _, side in { 1, -1 } do
		-- Marco de la cara: +Z sale del muro hacia quien lo mira.
		local face = CFrame.Angles(0, if side == 1 then 0 else math.pi, 0) * CFrame.new(0, 0, thickness / 2)
		local function on(x: number, y: number, layer: number): CFrame
			return face * CFrame.new(x, y, layer)
		end

		add(builder, "Canvas", Vector3.new(canvasW, canvasH, 0.06), on(0, canvasY, 0.03), Style.color("text"))

		-- Esquinas de neón: marcan el lienzo como lo interactivo del mapa.
		for _, sx in { 1, -1 } do
			for _, sy in { 1, -1 } do
				add(builder, "Corner", Vector3.new(1.6, 0.16, 0.05), on(sx * (canvasW / 2 - 0.8), canvasY + sy * canvasH / 2, 0.06), Style.color("interactive"), neon)
				add(builder, "Corner", Vector3.new(0.16, 1.6, 0.05), on(sx * canvasW / 2, canvasY + sy * (canvasH / 2 - 0.8), 0.06), Style.color("interactive"), neon)
			end
		end

		-- A medio pintar: manchas a la izquierda, el resto del lienzo en blanco.
		for index, spec in HALF_PAINTED do
			local kind, fx, fy, fw, fh, rotation, tint = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7]
			local layer = 0.07 + index * 0.012
			local offset = on(fx * canvasW, canvasY + fy * canvasH, layer)
			if kind == "disc" then
				disc(builder, "Splash", fw * canvasW, 0.05, offset, paint(tint))
			else
				add(builder, "Stroke", Vector3.new(fw * canvasW, fh * canvasH, 0.05), offset * CFrame.Angles(0, 0, math.rad(rotation)), paint(tint))
			end
		end
		for index, drip in DRIPS do
			local length = drip[3] * canvasH
			add(builder, "Drip", Vector3.new(0.16, length, 0.05), on(drip[1] * canvasW, canvasY + drip[2] * canvasH - length / 2, 0.075 + index * 0.012), paint(drip[4]))
		end

		-- Mural completo: escondido hasta que alguien termina el graffiti.
		for index, spec in FULL_MURAL do
			local kind, fx, fy, fw, fh, rotation, tint = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7]
			local offset = on(fx * canvasW, canvasY + fy * canvasH, 0.2 + index * 0.012)
			local piece: Part
			if kind == "disc" then
				piece = disc(builder, "Mural", fw * canvasW, 0.05, offset, paint(tint))
			else
				piece = add(builder, "Mural", Vector3.new(fw * canvasW, fh * canvasH, 0.05), offset * CFrame.Angles(0, 0, math.rad(rotation)), paint(tint))
			end
			piece.Transparency = 1
			table.insert(mural, piece)
		end
	end

	-- Latas de aerosol y charcos de pintura al pie del frente; un charco más detrás.
	local front = thickness / 2
	local function can(name: string, x: number, z: number, tint: Color3, lying: boolean)
		local tilt = if lying then CFrame.Angles(0, math.rad(35), math.rad(90)) else CFrame.identity
		local lift = if lying then 0.4 else 0.8
		local offset = CFrame.new(x, lift, z) * tilt
		standing(builder, name, 0.8, 1.6, offset, tint)
		standing(builder, name .. "Label", 0.84, 0.5, offset, Style.color("text"))
		standing(builder, name .. "Cap", 0.4, 0.5, offset * CFrame.new(0, 0.95, 0), Style.color("textOnAccent"))
	end
	can("CanA", -width / 2 + 1.6, front + 1.4, paint("coral"), false)
	can("CanB", -width / 2 + 2.9, front + 2.2, paint("cyan"), true)
	standing(builder, "Puddle", 2.6, 0.06, CFrame.new(-width / 2 + 1.2, 0.03, front + 3.2), paint("coral"))
	standing(builder, "Puddle", 2.2, 0.06, CFrame.new(width / 2 - 1.6, 0.03, -front - 1.8), paint("violet"))

	addSign(coping, if coop then "MURAL EN BANDA" else "PINTA AQUÍ", 2.6)

	-- Estallido de confeti de pintura al terminar.
	local burst = Instance.new("Attachment")
	burst.Position = Vector3.new(0, height / 2, 0)
	burst.Parent = coping
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.5)
	emitter.Speed = NumberRange.new(14, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -34, 0)
	emitter.Size = NumberSequence.new(0.7, 0.2)
	emitter.LightEmission = 0.3
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, paint("coral")),
		ColorSequenceKeypoint.new(0.25, paint("sunny")),
		ColorSequenceKeypoint.new(0.5, paint("mint")),
		ColorSequenceKeypoint.new(0.75, paint("cyan")),
		ColorSequenceKeypoint.new(1, paint("violet")),
	})
	emitter.Parent = burst

	model.Parent = folder

	local token = 0
	local function fade(target: number)
		local info = TweenInfo.new(Tuning.get("SpotFx.MuralFade"))
		for index, piece in mural do
			task.delay((index % #FULL_MURAL) * 0.04, function()
				if piece.Parent then
					TweenService:Create(piece, info, { Transparency = target }):Play()
				end
			end)
		end
	end

	return {
		completed = function()
			token += 1
			local mine = token
			emitter:Emit(46)
			fade(0)
			task.delay(Tuning.get("Mischief.SpotCooldown"), function()
				if token == mine then
					fade(1)
				end
			end)
		end,
	}
end

-- ─── Timbrazo ──────────────────────────────────────────────────────────────────

local HOUSE_COLORS = { "coral", "mint", "cyan", "violet", "sunny", "orange" }

local function buildDoorbell(spot: Spot, ground: number): Prop
	local pos = spot.part.Position
	local facade = nearestFacade(spot)
	local facing = if facade then facade.normal else facingToCenter(spot)
	if not facade then
		-- Sin edificio cerca: la casa se apoya en la acera; si lo de atrás es asfalto y lo de delante no, se da la vuelta.
		local _, behind = groundAt(pos - facing * 3 + Vector3.new(0, 4, 0))
		local _, ahead = groundAt(pos + facing * 3 + Vector3.new(0, 4, 0))
		if behind == Enum.Material.Asphalt and ahead ~= Enum.Material.Asphalt then
			facing = -facing
		end
	end

	local seed = hashOf(spot.key)
	local wallColor = pastel(paint(HOUSE_COLORS[seed % #HOUSE_COLORS + 1]), 0.62)
	local doorColor = paint(HOUSE_COLORS[(seed + 2) % #HOUSE_COLORS + 1])

	-- El timbre queda justo en el punto (donde sale el prompt): se corre la fachada para eso.
	local bellX = 3.5
	local base = Vector3.new(pos.X, ground, pos.Z)
	if facade then
		-- Pegada al edificio: la espalda de la fachada a 0,15 studs de la pared.
		base = flushAgainst(facade, base, 1.75, 16)
	end
	local root = CFrame.lookAt(base, base - facing) * CFrame.new(-bellX, 0, 0)
	local model = Instance.new("Model")
	model.Name = spot.key
	local builder: Builder = { model = model, root = root }

	local width, height, depth = 16, 10, 1.6
	local doorW, doorH, doorBase = 4.2, 7.2, 0.5

	-- Cuerpo, zócalo, cornisa y escalón.
	add(builder, "Facade", Vector3.new(width, height, depth), CFrame.new(0, height / 2, -depth / 2), wallColor, Enum.Material.Concrete)
	add(builder, "Plinth", Vector3.new(width + 0.2, 0.9, depth + 0.2), CFrame.new(0, 0.45, -depth / 2), Style.color("panelAlt"), Enum.Material.Concrete)
	local cornice = add(builder, "Cornice", Vector3.new(width + 1.4, 0.8, depth + 1.6), CFrame.new(0, height + 0.4, -depth / 2 + 0.4), Style.color("panel"), Enum.Material.Concrete)
	add(builder, "Step", Vector3.new(doorW + 1.8, doorBase, 1.8), CFrame.new(0, doorBase / 2, 0.9), Style.color("surfaceAlt"), Enum.Material.Concrete)

	-- Puerta con marco, tableros, ventanita, pomo y toldo de rayas.
	local doorY = doorBase + doorH / 2
	add(builder, "DoorFrame", Vector3.new(doorW + 0.8, doorH + 0.5, 0.3), CFrame.new(0, doorY + 0.25, 0.12), Style.color("text"))
	add(builder, "Door", Vector3.new(doorW, doorH, 0.3), CFrame.new(0, doorY, 0.3), doorColor)
	add(builder, "DoorPanelLow", Vector3.new(doorW - 1.2, 2.6, 0.06), CFrame.new(0, doorBase + doorH * 0.3, 0.48), shade(doorColor, 0.18))
	add(builder, "DoorPanelHigh", Vector3.new(doorW - 1.6, 1.8, 0.06), CFrame.new(0, doorBase + doorH * 0.73, 0.48), pastel(paint("skyBlue"), 0.25), Enum.Material.Glass)
	add(builder, "Knob", Vector3.new(0.45, 0.45, 0.45), CFrame.new(doorW / 2 - 0.7, doorBase + doorH * 0.46, 0.62), paint("sunny"), nil, Enum.PartType.Ball)
	local awningW = doorW + 2.6
	for index = 1, 5 do
		local stripe = awningW / 5
		add(
			builder,
			"Awning",
			Vector3.new(stripe, 0.35, 2.6),
			CFrame.new(-awningW / 2 + stripe * (index - 0.5), doorBase + doorH + 0.9, 1.1),
			if index % 2 == 1 then doorColor else Style.color("text")
		)
	end

	-- Ventanas a cada lado: el cristal tapa una luz que se enciende cuando suena el timbre.
	local panes: { Part } = {}
	for _, side in { -1, 1 } do
		local x = side * 6.1 -- el timbre queda entre la puerta y la ventana de ese lado
		add(builder, "WindowFrame", Vector3.new(3.6, 4.2, 0.2), CFrame.new(x, 5.8, 0.1), Style.color("text"))
		add(builder, "Sill", Vector3.new(3.8, 0.3, 0.7), CFrame.new(x, 3.55, 0.35), Style.color("surfaceAlt"), Enum.Material.Concrete)
		local light = add(builder, "WindowLight", Vector3.new(3, 3.6, 0.04), CFrame.new(x, 5.8, 0.21), paint("sunny"), Style.material("interactive"))
		light.Transparency = 1
		table.insert(panes, light)
		local glass = add(builder, "WindowGlass", Vector3.new(3, 3.6, 0.06), CFrame.new(x, 5.8, 0.25), pastel(paint("skyBlue"), 0.2), Enum.Material.Glass)
		glass.Transparency = 0.35
	end

	-- Placa, número de casa y el botón del timbre.
	add(builder, "BellPlate", Vector3.new(1.1, 2.1, 0.25), CFrame.new(bellX, 3.9, 0.125), Style.color("textOnAccent"))
	add(builder, "BellRing", Vector3.new(0.12, 1, 1), CFrame.new(bellX, 3.2, 0.3) * FACE_Z, Style.color("text"), nil, Enum.PartType.Cylinder)
	local buttonRest = CFrame.new(bellX, 3.2, 0.36)
	local button = disc(builder, "BellButton", 0.8, 0.3, buttonRest, Style.color("interactive"), Style.material("interactive"))
	movePrompt(spot, button, Vector3.new(-0.9, 0, 0)) -- el eje del disco apunta al frente en su -X
	local glow = Instance.new("PointLight")
	glow.Color = Style.color("interactive")
	glow.Brightness = 0.8
	glow.Range = 9
	glow.Parent = button
	local number = add(builder, "HouseNumber", Vector3.new(0.9, 0.6, 0.06), CFrame.new(bellX, 4.7, 0.28), Style.color("text"))
	local numberGui = Instance.new("SurfaceGui")
	numberGui.Face = Enum.NormalId.Front
	numberGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	numberGui.PixelsPerStud = 80
	numberGui.Parent = number
	local numberLabel = Instance.new("TextLabel")
	numberLabel.Size = UDim2.fromScale(1, 1)
	numberLabel.BackgroundTransparency = 1
	numberLabel.Text = tostring(10 + seed % 90)
	numberLabel.TextColor3 = Style.color("textOnAccent")
	numberLabel.FontFace = Style.font("number")
	numberLabel.TextScaled = true
	numberLabel.Parent = numberGui

	-- Macetas y felpudo.
	for index, x in { -3.7, bellX + 1 } do
		standing(builder, "Pot" .. index, 1.3, 1.1, CFrame.new(x, 0.55, 1.4), pastel(paint("orange"), 0.1), Enum.Material.Concrete)
		add(builder, "Bush" .. index, Vector3.new(1.9, 1.9, 1.9), CFrame.new(x, 1.8, 1.4), paint("mint"), nil, Enum.PartType.Ball)
	end
	add(builder, "Mat", Vector3.new(3, 0.08, 1.6), CFrame.new(0, 0.04, 2.7), paint("orange"), Enum.Material.Fabric)
	add(builder, "MatStripe", Vector3.new(2.4, 0.09, 0.3), CFrame.new(0, 0.045, 2.7), Style.color("text"), Enum.Material.Fabric)

	addSign(cornice, "TOCA EL TIMBRE", 2.8)
	model.Parent = folder

	local busyUntil = 0
	local windowToken = 0
	local function setWindows(transparency: number)
		local info = TweenInfo.new(0.25)
		for _, pane in panes do
			TweenService:Create(pane, info, { Transparency = transparency }):Play()
		end
	end

	return {
		started = function()
			local now = os.clock()
			if now < busyUntil then
				return
			end
			busyUntil = now + 1.6
			-- El botón se hunde y vuelve.
			local pressed = root * buttonRest * CFrame.new(0, 0, -0.22) * FACE_Z
			local rest = root * buttonRest * FACE_Z
			TweenService:Create(button, TweenInfo.new(0.06), { CFrame = pressed }):Play()
			task.delay(0.3, function()
				TweenService:Create(button, TweenInfo.new(0.12), { CFrame = rest }):Play()
			end)
			-- Parpadea al ritmo del timbre.
			task.spawn(function()
				for step = 1, 10 do
					local on = step % 2 == 1
					button.Color = if on then Style.color("text") else Style.color("interactive")
					glow.Brightness = if on then 5 else 1.5
					glow.Range = if on then 18 else 12
					task.wait(0.12)
				end
				button.Color = Style.color("interactive")
				glow.Brightness = 0.8
				glow.Range = 9
			end)
			-- El vecino se despierta: las ventanas se encienden unos segundos.
			windowToken += 1
			local mine = windowToken
			setWindows(0.12)
			task.delay(6, function()
				if windowToken == mine then
					setWindows(1)
				end
			end)
			Net.broadcast("spot_fx", { kind = "doorbell", position = button.Position })
		end,
	}
end

-- ─── Arranque ─────────────────────────────────────────────────────────────────

local builders: { [string]: (Spot, number) -> Prop } = {
	Graffiti = buildGraffiti,
	MuralGigante = buildGraffiti,
	Timbrazo = buildDoorbell,
}

function SpotProps.start(built: any)
	local root = Instance.new("Folder")
	root.Name = "SpotProps"
	root.Parent = Workspace
	folder = root

	for zoneName, def in Catalog.mischiefByZone do
		local builder = builders[def.id]
		if not builder then
			continue
		end
		for _, part in Areas.parts(zoneName) do
			local level = built.byId[tostring(part:GetAttribute("LevelId"))]
			local origin = if level then level.data.origin else nil
			local spot: Spot = {
				key = Mischief.spotKey(part),
				part = part,
				def = def,
				level = level,
				center = if type(origin) == "table" then Vector3.new(origin[1] or 0, 0, origin[3] or 0) else Vector3.zero,
			}
			local ground = groundAt(part.Position)
			-- Un fallo al armar un punto no debe detener el arranque del juego: ese punto queda sin props.
			local ok, result = pcall(builder, spot, ground or (part.Position.Y - part.Size.Y / 2 + 0.6))
			if ok then
				props[spot.key] = result
			else
				warn(`[SpotProps] No se pudo armar {spot.key}: {result}`)
			end
		end
	end

	Mischief.started:Connect(function(_, session)
		local prop = props[session.spot.key]
		if prop and prop.started then
			prop.started()
		end
	end)
	Mischief.completed:Connect(function(_, result)
		local prop = props[result.spotKey]
		if prop and prop.completed then
			prop.completed()
		end
	end)
end

return SpotProps
