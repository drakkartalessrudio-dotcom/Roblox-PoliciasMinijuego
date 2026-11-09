--[[
	CopModels · el aspecto de los policías brainrot de TravesurasBrainrot, armados con
	Parts (sin assets externos). Cada función devuelve un Model con HumanoidRootPart como
	PrimaryPart y, salvo el helicóptero, un Humanoid. El pase de arte los puede reemplazar
	por modelos del usuario sin tocar el core Cops.

	Los colores salen del tema: la luz de sirena es `hazard`, exclusivo de la policía.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Style = require(ReplicatedStorage.Shared.Style)

local CopModels = {}

local function part(model: Model, root: BasePart, name: string, shape: Enum.PartType, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = root.CFrame * CFrame.new(offset)
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function newRoot(model: Model, size: Vector3): Part
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = size
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function humanoid(model: Model, hipHeight: number, health: number?): Humanoid
	local h = Instance.new("Humanoid")
	h.HipHeight = hipHeight
	h.MaxHealth = health or 100
	h.Health = health or 100
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.Parent = model
	return h
end

local function tag(model: Model, root: BasePart, height: number, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(110, 46)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Adornee = root
	gui.Parent = model
	local alert = Instance.new("TextLabel")
	alert.Name = "Alert"
	alert.BackgroundTransparency = 1
	alert.Size = UDim2.fromScale(1, 0.6)
	alert.Text = ""
	alert.TextScaled = true
	alert.FontFace = Style.font("heading")
	alert.TextColor3 = Style.color("hazard")
	alert.TextStrokeTransparency = 0.3
	alert.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, 0.6)
	label.Size = UDim2.fromScale(1, 0.4)
	label.Text = text
	label.TextScaled = true
	label.FontFace = Style.font("label")
	label.TextColor3 = Style.color("text")
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
end

local function siren(model: Model, root: BasePart, offset: Vector3)
	local light = part(model, root, "Sirena", Enum.PartType.Block, Vector3.new(1.4, 0.6, 0.8), offset, Style.color("hazard"), Enum.Material.Neon)
	local point = Instance.new("PointLight")
	point.Color = Style.color("hazard")
	point.Range = 12
	point.Brightness = 2
	point.Parent = light
end

local function eyes(model: Model, root: BasePart, y: number, z: number)
	local white = Color3.new(1, 1, 1)
	local black = Color3.new(0.05, 0.05, 0.05)
	for _, x in { -0.6, 0.6 } do
		part(model, root, "Ojo", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), Vector3.new(x, y, z), white)
		part(model, root, "Pupila", Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), Vector3.new(x, y, z - 0.35), black)
	end
end

local builders: { [string]: () -> Model } = {}

builders.patata = function()
	local model = Instance.new("Model")
	local root = newRoot(model, Vector3.new(2, 2, 1.5))
	humanoid(model, 0.7)
	part(model, root, "Cuerpo", Enum.PartType.Ball, Vector3.new(3.4, 3.2, 3.2), Vector3.new(0, 0.5, 0), Color3.fromRGB(196, 148, 92))
	part(model, root, "Gorra", Enum.PartType.Cylinder, Vector3.new(0.7, 2.6, 2.6), Vector3.new(0, 2.1, 0), Color3.fromRGB(40, 60, 140)).CFrame *= CFrame.Angles(0, 0, math.rad(90))
	part(model, root, "Visera", Enum.PartType.Block, Vector3.new(1.8, 0.2, 1.2), Vector3.new(0, 1.8, -1.5), Color3.fromRGB(40, 60, 140))
	eyes(model, root, 0.8, -1.4)
	siren(model, root, Vector3.new(0, 2.7, 0))
	tag(model, root, 4, "Patrullero Patata")
	return model
end

builders.capibara = function()
	local model = Instance.new("Model")
	local root = newRoot(model, Vector3.new(2.4, 2, 4))
	humanoid(model, 0.6)
	part(model, root, "Cuerpo", Enum.PartType.Block, Vector3.new(2.4, 2, 3.8), Vector3.new(0, 0.4, 0), Color3.fromRGB(150, 105, 70))
	part(model, root, "Cabeza", Enum.PartType.Block, Vector3.new(1.8, 1.6, 1.6), Vector3.new(0, 1.2, -2), Color3.fromRGB(165, 118, 80))
	eyes(model, root, 1.5, -2.8)
	part(model, root, "Moto", Enum.PartType.Block, Vector3.new(1.2, 0.8, 4.4), Vector3.new(0, -0.9, 0), Color3.fromRGB(230, 230, 240))
	for _, z in { -1.8, 1.8 } do
		part(model, root, "Rueda", Enum.PartType.Cylinder, Vector3.new(0.6, 1.8, 1.8), Vector3.new(0, -1, z), Color3.fromRGB(30, 30, 40)).CFrame *= CFrame.Angles(0, 0, math.rad(90))
	end
	siren(model, root, Vector3.new(0, 1.8, 0.4))
	tag(model, root, 3.6, "Capibara Motorizada")
	return model
end

builders.tiburon = function()
	local model = Instance.new("Model")
	local root = newRoot(model, Vector3.new(2.4, 3, 3.6))
	humanoid(model, 1.2)
	part(model, root, "Cuerpo", Enum.PartType.Block, Vector3.new(2.4, 2.4, 4.4), Vector3.new(0, 0.6, 0), Color3.fromRGB(110, 140, 175))
	part(model, root, "Panza", Enum.PartType.Block, Vector3.new(2.2, 0.6, 3.8), Vector3.new(0, -0.5, 0), Color3.fromRGB(235, 240, 248))
	part(model, root, "Aleta", Enum.PartType.Block, Vector3.new(0.3, 1.6, 1.6), Vector3.new(0, 2.2, 0.4), Color3.fromRGB(95, 125, 160))
	eyes(model, root, 1.2, -2.3)
	for _, x in { -0.8, 0.8 } do
		part(model, root, "Zapatilla", Enum.PartType.Block, Vector3.new(1, 0.9, 1.8), Vector3.new(x, -1.4, -0.4), Color3.fromRGB(255, 255, 255))
	end
	siren(model, root, Vector3.new(0, 3.1, 0.4))
	tag(model, root, 4.6, "Tiburón Zapatilla")
	return model
end

builders.cafetera = function()
	local model = Instance.new("Model")
	local root = newRoot(model, Vector3.new(2.4, 2.4, 3.6))
	humanoid(model, 0.8)
	part(model, root, "Cuerpo", Enum.PartType.Block, Vector3.new(2.4, 2.6, 3.4), Vector3.new(0, 0.6, 0), Color3.fromRGB(60, 60, 78))
	part(model, root, "Tapa", Enum.PartType.Block, Vector3.new(2, 0.5, 2.6), Vector3.new(0, 2.1, 0), Color3.fromRGB(205, 210, 225), Enum.Material.Metal)
	part(model, root, "Oreja", Enum.PartType.Block, Vector3.new(0.3, 1.2, 0.9), Vector3.new(-1.1, 2.4, -0.4), Color3.fromRGB(60, 60, 78))
	part(model, root, "Oreja", Enum.PartType.Block, Vector3.new(0.3, 1.2, 0.9), Vector3.new(1.1, 2.4, -0.4), Color3.fromRGB(60, 60, 78))
	eyes(model, root, 1.2, -1.8)
	siren(model, root, Vector3.new(0, 2.6, 0.9))
	tag(model, root, 4.6, "Cafetera K-9")
	return model
end

builders.helicoptero = function()
	local model = Instance.new("Model")
	local root = newRoot(model, Vector3.new(4, 3, 8))
	root.CanCollide = false
	part(model, root, "Banana", Enum.PartType.Block, Vector3.new(2.6, 3, 8), Vector3.new(0, 0, 0), Color3.fromRGB(255, 225, 70))
	part(model, root, "Cola", Enum.PartType.Block, Vector3.new(0.7, 0.7, 5), Vector3.new(0, 0.6, 5.5), Color3.fromRGB(255, 225, 70))
	part(model, root, "Rotor", Enum.PartType.Block, Vector3.new(14, 0.2, 0.7), Vector3.new(0, 2.2, 0), Color3.fromRGB(60, 60, 78))
	eyes(model, root, 0.3, -4.2)
	local foco = part(model, root, "Foco", Enum.PartType.Block, Vector3.new(1, 0.6, 1), Vector3.new(0, -1.8, -2), Style.color("hazard"), Enum.Material.Neon)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 40
	spot.Range = 90
	spot.Brightness = 4
	spot.Color = Color3.fromRGB(255, 250, 210)
	spot.Parent = foco
	tag(model, root, 5, "Helicóptero Banana")
	return model
end

builders.comisario = function()
	local model = Instance.new("Model")
	local root = newRoot(model, Vector3.new(5, 5, 4))
	humanoid(model, 2.5, 1000)
	part(model, root, "Cerebro", Enum.PartType.Ball, Vector3.new(8.5, 7, 7.5), Vector3.new(0, 1.2, 0), Color3.fromRGB(255, 160, 190))
	part(model, root, "Pliegue", Enum.PartType.Block, Vector3.new(0.4, 5, 6.5), Vector3.new(0, 1.4, 0), Color3.fromRGB(235, 120, 160))
	part(model, root, "Gorra", Enum.PartType.Cylinder, Vector3.new(1.2, 6.5, 6.5), Vector3.new(0, 5.2, 0), Color3.fromRGB(30, 40, 90)).CFrame *= CFrame.Angles(0, 0, math.rad(90))
	eyes(model, root, 1.4, -3.6)
	siren(model, root, Vector3.new(0, 6.2, 0))
	tag(model, root, 8.4, "Comisario Cerebrote")
	return model
end

function CopModels.build(typeId: string): Model
	local builder = builders[typeId]
	assert(builder, `no hay modelo para el policía {typeId}`)
	return builder()
end

return CopModels
