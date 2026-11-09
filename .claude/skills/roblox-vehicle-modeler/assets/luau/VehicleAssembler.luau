--!strict
--[[
	VehicleAssembler · arma un auto a partir de las mallas importadas del FBX y VehicleModels.json (manifest v2).

	El FBX trae las piezas sueltas (Chassis, Windows, Trim, Lights, Bumpers, Tire_xx, Rim_xx...). Este módulo les
	aplica tamaño, posición, material, color y transparencia del manifest, las suelda al Chassis y crea los
	Attachments Socket_* (guía de arte, sección 3). Como el manifest ya viene en el marco de Roblox, el modelo queda
	mirando a -Z sin ningún giro y el Chassis cumple el contrato de VehicleRig. Sirve en servidor y cliente.

	  local model = VehicleAssembler.build(imported, "T1_Sedan")   -- imported = el modelo importado de Studio
	  VehicleAssembler.setBodyColor(model, Color3.fromRGB(255, 80, 40))
	  VehicleAssembler.setWindowTint(model, Color3.fromRGB(15, 15, 15), 0.35)
	  VehicleAssembler.setRimStyle(model, Color3.fromRGB(255, 200, 0), Enum.Material.Metal)
	  VehicleAssembler.attachModule(model, "Socket_Spoiler", spoilerTemplate)

	Para un auto que se maneje, usa VehicleBody.build (agrega asiento, ruedas animables y atributos de pintura).
]]

local Plan = require(script.Parent.VehicleModelPlan)

local VehicleAssembler = {}

local MODELS = (require(script.Parent.VehicleModels) :: any).models :: { [string]: Plan.Entry }

local MODULE_ATTR = "ModuleSocket"
local SCALE_WARN_RATIO = 0.02 -- avisa si lo importado difiere más de 2 % del manifest

local function materialOf(name: string): Enum.Material
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and material then material else Enum.Material.SmoothPlastic
end

local function findPart(model: Instance, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

function VehicleAssembler.entry(assetKey: string): Plan.Entry?
	return MODELS[assetKey]
end

function VehicleAssembler.keys(): { string }
	local keys = {}
	for key in MODELS do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Clona `imported`, aplica el manifest de `assetKey` y devuelve el Model ensamblado (sin parent), centrado en el origen.
function VehicleAssembler.build(imported: Instance, assetKey: string): Model
	local entry = MODELS[assetKey]
	assert(entry, `[VehicleAssembler] '{assetKey}' no está en VehicleModels.json`)

	local source = imported:Clone()
	local model = Instance.new("Model")
	model.Name = assetKey
	for _, child in source:GetDescendants() do
		if child:IsA("BasePart") then
			child.Parent = model
		end
	end
	source:Destroy()

	local chassis = findPart(model, "Chassis")
	assert(chassis, `[VehicleAssembler] el modelo importado de '{assetKey}' no tiene la malla Chassis`)

	-- Un tamaño importado distinto del manifest indica otra escala de importación: se corrige con Size, pero se avisa.
	local importedSize = { chassis.Size.X, chassis.Size.Y, chassis.Size.Z }
	local ratio = Plan.scaleRatio(importedSize, entry.parts.Chassis.size)
	if ratio and math.abs(ratio - 1) > SCALE_WARN_RATIO then
		warn(
			`[VehicleAssembler] {assetKey}: lo importado está a escala {string.format("%.3f", ratio)} del manifest; se corrige con Size`
		)
	end

	for _, op in Plan.operations(entry) do
		local part = findPart(model, op.name)
		if not part then
			warn(`[VehicleAssembler] {assetKey}: falta la malla '{op.name}' en el modelo importado`)
			continue
		end
		part.Anchored = true
		part.Size = vector(op.size)
		part.CFrame = CFrame.new(vector(op.center))
		part.Color = Color3.fromRGB(op.color[1], op.color[2], op.color[3])
		part.Material = materialOf(op.material)
		part.Transparency = op.transparency
		part.CanCollide = part == chassis
		part.CanTouch = false
		part.Massless = part ~= chassis
		part.CastShadow = op.kind ~= "Windows"
		local target = Plan.paintTarget(op.name)
		if target then
			part:SetAttribute("Paintable", target)
			part:SetAttribute("BaseColor", part.Color)
		end
	end

	if chassis:IsA("MeshPart") then
		chassis.CollisionFidelity = Enum.CollisionFidelity.Box
	end
	model.PrimaryPart = chassis
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= chassis then
			local weld = Instance.new("WeldConstraint")
			weld.Name = `Weld_{child.Name}`
			weld.Part0 = chassis
			weld.Part1 = child
			weld.Parent = child
		end
	end
	for socketName in entry.sockets do
		local offset = Plan.socketOffset(entry, socketName)
		if offset then
			local attachment = Instance.new("Attachment")
			attachment.Name = socketName
			attachment.Position = vector(offset)
			attachment.Parent = chassis
		end
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child.Anchored = false
		end
	end

	model:SetAttribute("VehicleAsset", assetKey)
	model:SetAttribute("BodyType", entry.bodyType)
	if entry.tier then
		model:SetAttribute("Tier", entry.tier)
	end
	return model
end

local function eachKind(model: Model, kind: string, fn: (BasePart) -> ())
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and Plan.kindOf(child.Name) == kind then
			fn(child)
		end
	end
end

-- Color del cuerpo (Chassis y caja). Cambia también BaseColor para que la pintura de fábrica no lo pise.
function VehicleAssembler.setBodyColor(model: Model, color: Color3)
	for _, kind in { "Chassis", "Bed" } do
		eachKind(model, kind, function(part)
			part.Color = color
			part:SetAttribute("BaseColor", color)
		end)
	end
end

-- Ejemplo de la guía 2.1: tinte de ventanas por jugador.
function VehicleAssembler.setWindowTint(model: Model, color: Color3, transparency: number)
	eachKind(model, "Windows", function(part)
		part.Color = color
		part.Transparency = math.clamp(transparency, 0, 1)
		part.Material = Enum.Material.Glass
	end)
end

-- Llantas (guía 2.2): color y material independientes del neumático.
function VehicleAssembler.setRimStyle(model: Model, color: Color3?, material: Enum.Material?)
	eachKind(model, "Rim", function(part)
		if color then
			part.Color = color
		end
		if material then
			part.Material = material
		end
	end)
end

-- Cualquier pieza por tipo ("Roof", "Bumpers", "Trim", "Neon"...).
function VehicleAssembler.setKindColor(model: Model, kind: string, color: Color3)
	eachKind(model, kind, function(part)
		part.Color = color
	end)
end

-- Llantas y neumáticos caben en cualquier auto escalando (guía 5.1). El pivote está en el buje.
function VehicleAssembler.scaleWheels(model: Model, factor: number)
	for _, kind in { "Tire", "Rim" } do
		eachKind(model, kind, function(part)
			part.Size *= factor
		end)
	end
end

function VehicleAssembler.socket(model: Model, socketName: string): Attachment?
	local chassis = model.PrimaryPart
	local attachment = chassis and chassis:FindFirstChild(socketName)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end
	return nil
end

-- Guía 3.2: clona la pieza, alinea su Attachment con el Socket_* del auto y la fija con un RigidConstraint.
-- La plantilla puede ser un BasePart o un Model; si trae un Attachment con el nombre del socket (o cualquiera), se usa.
function VehicleAssembler.attachModule(model: Model, socketName: string, template: Instance): Instance?
	local socket = VehicleAssembler.socket(model, socketName)
	if not socket then
		warn(`[VehicleAssembler] {model.Name} no tiene el socket {socketName}`)
		return nil
	end
	VehicleAssembler.detachModule(model, socketName)

	local module = template:Clone()
	local root: BasePart? = if module:IsA("BasePart")
		then module
		elseif module:IsA("Model") then (module.PrimaryPart or module:FindFirstChildWhichIsA("BasePart", true))
		else nil
	if not root then
		module:Destroy()
		return nil
	end

	local own = module:FindFirstChild(socketName, true) or module:FindFirstChildWhichIsA("Attachment", true)
	local moduleAttachment: Attachment
	if own and own:IsA("Attachment") then
		moduleAttachment = own
	else
		moduleAttachment = Instance.new("Attachment")
		moduleAttachment.Name = socketName
		moduleAttachment.Parent = root
	end

	for _, descendant in module:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	if module:IsA("BasePart") then
		module.Anchored = false
		module.CanCollide = false
		module.Massless = true
	end

	module:SetAttribute(MODULE_ATTR, socketName)
	module.Parent = model
	local parentPart = moduleAttachment.Parent :: BasePart
	local alignment = Instance.new("RigidConstraint")
	alignment.Name = `Rigid_{socketName}`
	alignment.Attachment0 = socket
	alignment.Attachment1 = moduleAttachment
	alignment.Parent = parentPart
	return module
end

function VehicleAssembler.detachModule(model: Model, socketName: string)
	for _, child in model:GetChildren() do
		if child:GetAttribute(MODULE_ATTR) == socketName then
			child:Destroy()
		end
	end
end

return VehicleAssembler
