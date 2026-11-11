--[[
	Compinche · el brainrot que recibe el Botín en cada Guarida: Sapini Cashini, un sapo alcancía
	armado con Parts (sin assets externos). Antes el depósito era un aviso flotante sobre una zona
	invisible; ahora hay alguien a quien dárselo. Mezcla Areas y World, así que es de Game.

	  - Se para en cada zona "guarida" (distritos y lobby), 8 studs hacia el centro del nivel y
	    mirando al punto de aparición, sobre una plataforma con anillo de neón cian (el color de
	    rol `goal`, el de la Guarida y los depósitos).
	  - El prompt "Depositar Botín" sale ahora de su boca.
	  - Mientras se mantiene el prompt abre la boca; sus ojos siguen al jugador más cercano.
	  - Al depositar (World.deposited): las monedas vuelan del jugador a su boca, la traga, la
	    panza rebota, el sombrero salta y escupe confeti dorado.

	Solo anima: el depósito sigue siendo de World. Si algo falla al armar un compinche, esa
	Guarida conserva su prompt de siempre. El pase de arte lo puede reemplazar por un modelo del
	usuario sin tocar World.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Style = require(ReplicatedStorage.Shared.Style)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local World = require(script.Parent.World)

local Compinche = {}

local NAME = "Sapini Cashini"
local OFFSET = 8 -- studs desde el centro de la Guarida hacia dentro del nivel
local LOOK_RANGE = 45 -- studs a los que los ojos siguen a un jugador
local MOUTH = Vector3.new(3.2, 1.8, 0.9) -- tamaño de la boca cerrada
local LIPS = Vector3.new(3.8, 2.2, 1)
local BELLY = Vector3.new(3.6, 2.8, 2)

-- Los discos de Roblox (Cylinder) tienen su eje en X: estos giros lo llevan a Z (de frente) o a Y (de pie).
local FACE_Z = CFrame.Angles(0, math.rad(90), 0)
local STAND_Y = CFrame.Angles(0, 0, math.rad(90))

type Frog = {
	cframe: CFrame, -- en el suelo; +Z es el frente
	mouthWorld: Vector3,
	mouth: Part,
	lips: Part,
	belly: Part,
	hat: { Part },
	hatRest: { CFrame },
	pupils: { Part },
	pupilBase: { Vector3 },
	eyeLocal: { Vector3 },
	emitter: ParticleEmitter,
	anchor: Attachment, -- la boca: de aquí sale el prompt
	busyUntil: number,
	eatToken: number,
	lookX: number,
	lookY: number,
}

local frogs: { [BasePart]: Frog } = {}
local folder: Folder? = nil

local function groundAt(position: Vector3): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if folder then { folder } else {}
	local hit = Workspace:Raycast(position, Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else nil
end

-- Dirección cardinal hacia el centro del nivel (si la Guarida está en el centro, +Z).
local function inwardOf(zone: BasePart, origin: Vector3): Vector3
	local offset = Vector3.new(origin.X - zone.Position.X, 0, origin.Z - zone.Position.Z)
	if offset.Magnitude < 1 then
		return Vector3.zAxis
	end
	if math.abs(offset.X) > math.abs(offset.Z) then
		return Vector3.new(math.sign(offset.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(offset.Z))
end

local function build(zone: BasePart, level: any): Frog
	local origin = if level and type(level.data.origin) == "table" then Vector3.new(level.data.origin[1] or 0, 0, level.data.origin[3] or 0) else Vector3.zero
	local inward = inwardOf(zone, origin)
	local spot = zone.Position + inward * OFFSET
	local ground = groundAt(Vector3.new(spot.X, zone.Position.Y, spot.Z)) or (zone.Position.Y - zone.Size.Y / 2)
	local base = Vector3.new(spot.X, ground, spot.Z)
	-- Mira hacia el centro de la Guarida (donde aparecen los jugadores): su +Z es lo opuesto a `inward`.
	local root = CFrame.lookAt(base, base + inward)

	local model = Instance.new("Model")
	model.Name = `Compinche_{zone:GetAttribute("LevelId")}_{zone:GetAttribute("PieceId")}`

	local ink = Style.color("textOnAccent")
	local snow = Style.color("text")
	local mint = Style.color("success")
	local mintDark = mint:Lerp(ink, 0.25)
	local bellyColor = mint:Lerp(snow, 0.55)
	local gold = Style.color("interactive")
	local violet = Style.color("reward")

	local function put(name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, tint: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = material or Enum.Material.SmoothPlastic
		part.Color = tint
		part.Size = size
		part.CFrame = root * offset
		part.Parent = model
		return part
	end
	local function ball(name: string, size: Vector3, at: Vector3, tint: Color3): Part
		return put(name, Enum.PartType.Ball, size, CFrame.new(at), tint)
	end
	-- Disco de pie (plataforma, sombrero): `height` va sobre Y.
	local function stand(name: string, diameter: number, height: number, y: number, z: number, tint: Color3, material: Enum.Material?): Part
		return put(name, Enum.PartType.Cylinder, Vector3.new(height, diameter, diameter), CFrame.new(0, y, z) * STAND_Y, tint, material)
	end
	-- Disco que mira al frente (monedas pegadas a la panza).
	local function badge(name: string, diameter: number, thickness: number, at: Vector3, tint: Color3, material: Enum.Material?): Part
		return put(name, Enum.PartType.Cylinder, Vector3.new(thickness, diameter, diameter), CFrame.new(at) * FACE_Z, tint, material)
	end

	-- Plataforma con anillo de neón cian: se reconoce de lejos como la Guarida.
	local ring = stand("Anillo", 9.4, 0.3, 0.15, 0, Style.color("goal"), Style.material("goal"))
	stand("Plataforma", 8.4, 0.4, 0.5, 0, Style.color("panelAlt"), Enum.Material.Concrete)
	local glow = Instance.new("PointLight")
	glow.Color = Style.color("goal")
	glow.Range = 16
	glow.Brightness = 1.2
	glow.Parent = ring

	-- Cuerpo.
	for _, side in { -1, 1 } do
		ball("Pie", Vector3.new(2.2, 0.9, 2.8), Vector3.new(side * 1.6, 1.15, 1.6), mintDark)
		ball("Brazo", Vector3.new(1.5, 2.2, 1.5), Vector3.new(side * 3, 2.5, 0.8), mint)
		ball("Cuenca", Vector3.new(2.4, 2.4, 2.4), Vector3.new(side * 1.5, 5.3, 0.9), mint)
	end
	local body = ball("Cuerpo", Vector3.new(5.4, 5, 5.2), Vector3.new(0, 3.2, 0), mint)
	body.CanCollide = true
	local belly = ball("Panza", BELLY, Vector3.new(0, 2.1, 1.9), bellyColor)
	badge("Moneda", 1.5, 0.15, Vector3.new(0, 1.7, 2.9), gold, Style.material("interactive"))
	badge("MonedaCentro", 1, 0.17, Vector3.new(0, 1.7, 2.92), gold:Lerp(ink, 0.3))

	-- Cara: los ojos siguen a los jugadores.
	local pupils: { Part } = {}
	local pupilBase: { Vector3 } = {}
	local eyeLocal: { Vector3 } = {}
	for _, side in { -1, 1 } do
		local eye = Vector3.new(side * 1.5, 5.65, 1.1)
		ball("Ojo", Vector3.new(2, 2, 2), eye, snow)
		local center = eye + Vector3.new(0, 0, 0.85)
		table.insert(pupils, ball("Pupila", Vector3.new(0.95, 0.95, 0.95), center, ink))
		table.insert(pupilBase, center)
		table.insert(eyeLocal, eye)
	end
	local lips = ball("Labios", LIPS, Vector3.new(0, 3.95, 2.3), mintDark)
	local mouth = ball("Boca", MOUTH, Vector3.new(0, 3.95, 2.45), ink)
	put("Lengua", Enum.PartType.Block, Vector3.new(1.2, 0.25, 1.2), CFrame.new(0, 3.2, 2.8) * CFrame.Angles(math.rad(-15), 0, 0), Style.color("danger"))

	-- Sombrero de copa violeta (el color del Botín) con cinta dorada.
	local hat = {
		stand("Ala", 3.4, 0.25, 5.45, -1, violet:Lerp(ink, 0.3)),
		stand("Copa", 2.3, 1.6, 6.35, -1, violet),
		stand("Cinta", 2.4, 0.4, 5.8, -1, gold, Style.material("interactive")),
	}
	local hatRest = {}
	for _, piece in hat do
		table.insert(hatRest, piece.CFrame)
	end

	-- La boca: desde aquí sale el prompt y el confeti.
	local anchor = Instance.new("Attachment")
	anchor.Name = "Boca"
	anchor.Position = Vector3.new(0, 0.75, 3.4) -- relativo a Cuerpo (centro en y = 3,2)
	anchor.Parent = body
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Back -- el +Z local: hacia el frente
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Lifetime = NumberRange.new(0.7, 1.2)
	emitter.Speed = NumberRange.new(14, 24)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Size = NumberSequence.new(0.7, 0.2)
	emitter.LightEmission = 0.4
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, gold),
		ColorSequenceKeypoint.new(0.6, Style.color("goal")),
		ColorSequenceKeypoint.new(1, violet),
	})
	emitter.Parent = anchor

	model.Parent = folder

	return {
		cframe = root,
		mouthWorld = (root * CFrame.new(0, 3.95, 2.6)).Position,
		mouth = mouth,
		lips = lips,
		belly = belly,
		hat = hat,
		hatRest = hatRest,
		pupils = pupils,
		pupilBase = pupilBase,
		eyeLocal = eyeLocal,
		emitter = emitter,
		anchor = anchor,
		busyUntil = 0,
		eatToken = 0,
		lookX = 0,
		lookY = 0,
	}
end

-- 0 = boca cerrada, 1 = abierta del todo.
local function setOpen(frog: Frog, amount: number, seconds: number)
	local info = TweenInfo.new(math.max(seconds, 0.05), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(frog.mouth, info, { Size = Vector3.new(MOUTH.X + 0.7 * amount, MOUTH.Y + 1.6 * amount, MOUTH.Z) }):Play()
	TweenService:Create(frog.lips, info, { Size = Vector3.new(LIPS.X + 0.7 * amount, LIPS.Y + 1.6 * amount, LIPS.Z) }):Play()
end

local function flyCoin(frog: Frog, from: Vector3)
	local coin = Instance.new("Part")
	coin.Name = "Moneda"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.2, 1.3, 1.3)
	coin.Material = Style.material("interactive")
	coin.Color = Style.color("interactive")
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanTouch = false
	coin.CanQuery = false
	coin.CastShadow = false
	coin.CFrame = CFrame.new(from) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
	coin.Parent = folder
	local apex = from:Lerp(frog.mouthWorld, 0.5) + Vector3.new(0, 6 + math.random() * 2, 0)
	local rise = TweenService:Create(coin, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Position = apex })
	local fall = TweenService:Create(coin, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Position = frog.mouthWorld, Size = Vector3.new(0.1, 0.5, 0.5) })
	rise.Completed:Once(function()
		fall:Play()
	end)
	fall.Completed:Once(function()
		coin:Destroy()
	end)
	rise:Play()
	Debris:AddItem(coin, 2)
end

-- Traga: cierra la boca, la panza rebota, el sombrero salta y escupe confeti.
local function gulp(frog: Frog)
	setOpen(frog, 0, 0.18)
	TweenService:Create(frog.belly, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = BELLY * 1.3 }):Play()
	task.delay(0.12, function()
		TweenService:Create(frog.belly, TweenInfo.new(0.35, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Size = BELLY }):Play()
	end)
	for index, piece in frog.hat do
		local rest = frog.hatRest[index]
		TweenService:Create(piece, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rest + Vector3.new(0, 0.8, 0) }):Play()
		task.delay(0.12, function()
			TweenService:Create(piece, TweenInfo.new(0.35, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = rest }):Play()
		end)
	end
	frog.emitter:Emit(26)
end

local function eat(frog: Frog, player: Player, amount: number)
	frog.eatToken += 1
	local token = frog.eatToken
	local coins = math.clamp(math.ceil(amount / 30), 5, 14)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 1, 0) else frog.mouthWorld + Vector3.new(0, 0, 8)
	local flight = 0.5 + coins * 0.06
	frog.busyUntil = os.clock() + flight + 0.8
	setOpen(frog, 1, 0.15)
	for index = 1, coins do
		task.delay((index - 1) * 0.06, function()
			flyCoin(frog, from + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5))
		end)
	end
	task.delay(flight, function()
		if frog.eatToken == token then
			gulp(frog)
		end
	end)
end

-- Los ojos miran a `target` (o al frente si es nil). Solo toca las Parts si la mirada cambió.
local function look(frog: Frog, target: Vector3?)
	local x, y = 0, 0
	if target then
		local local_ = frog.cframe:PointToObjectSpace(target)
		local direction = (local_ - frog.eyeLocal[1]).Unit
		x = math.clamp(direction.X, -1, 1) * 0.32
		y = math.clamp(direction.Y, -1, 1) * 0.28
	end
	if math.abs(x - frog.lookX) < 0.02 and math.abs(y - frog.lookY) < 0.02 then
		return
	end
	frog.lookX, frog.lookY = x, y
	for index, pupil in frog.pupils do
		pupil.CFrame = frog.cframe * CFrame.new(frog.pupilBase[index] + Vector3.new(x, y, 0))
	end
end

function Compinche.start(built: any)
	local root = Instance.new("Folder")
	root.Name = "Compinches"
	root.Parent = Workspace
	folder = root

	for _, zone in Areas.parts("guarida") do
		local prompt = zone:FindFirstChildOfClass("ProximityPrompt")
		local level = built.byId[tostring(zone:GetAttribute("LevelId"))]
		-- Un fallo al armar uno no debe detener el arranque: esa Guarida queda con su prompt de siempre.
		local ok, frog = pcall(build, zone, level)
		if not ok then
			warn(`[Compinche] No se pudo armar el de {zone:GetFullName()}: {frog}`)
			continue
		end
		frogs[zone] = frog
		if prompt then
			prompt.ObjectText = NAME
			prompt.Parent = frog.anchor -- el prompt sale de la boca
			prompt.PromptButtonHoldBegan:Connect(function()
				setOpen(frog, 0.5, prompt.HoldDuration)
			end)
			prompt.PromptButtonHoldEnded:Connect(function()
				-- Si fue un depósito, `eat` ya marcó que está ocupado y la boca sigue su propia animación.
				task.delay(0.15, function()
					if os.clock() > frog.busyUntil then
						setOpen(frog, 0, 0.2)
					end
				end)
			end)
		end
	end

	World.deposited:Connect(function(player, amount, zone)
		local frog = frogs[zone]
		if frog then
			eat(frog, player, amount)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.15 then
			return
		end
		elapsed = 0
		for _, frog in frogs do
			local nearest: Vector3? = nil
			local best = LOOK_RANGE
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local head = character and character:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					local distance = (head.Position - frog.cframe.Position).Magnitude
					if distance < best then
						best = distance
						nearest = head.Position
					end
				end
			end
			look(frog, nearest)
		end
	end)
end

return Compinche
