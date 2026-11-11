--[[
	HidingProps · el aspecto de los escondites. Las zonas `hide` y `tutorial_hide` de Levels.json son
	volúmenes invisibles; aquí se visten con un prop que llena la zona, para que el jugador sepa dónde
	esconderse (mismo enfoque que Game/SpotProps con los puntos de travesura):

	  bush        arbusto grande: un racimo de esferas de follaje con unas florecitas
	  container   contenedor de basura: caja de metal con tapa, franja y ruedas

	Todo es decoración sin colisión ni consulta de rayos: no cambia la visión de los policías, el
	ruido ni las rutas (la ocultación la decide Game/Hiding con la zona, no con el prop). Cada prop
	lleva la etiqueta "HideProp" y el atributo HideId («nivel/id» de la pieza de la zona) para que el cliente
	(HideFeedback) lo resalte.

	API:
	  HidingProps.start()
]]

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Style = require(ReplicatedStorage.Shared.Style)
local Areas = require(ServerScriptService.Server.Modules.Areas)

local HidingProps = {}

local TAG = "HideProp"

local folder: Folder

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.Shape = shape or Enum.PartType.Block
	piece.Material = material
	piece.Color = color
	piece.Size = size
	piece.CFrame = cframe
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Parent = model
	return piece
end

local function shade(color: Color3, amount: number): Color3
	return color:Lerp(if amount >= 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), math.abs(amount))
end

-- Arbusto: un racimo de esferas que cubre ~5 × 4 × 5 studs, con flores.
local function buildBush(model: Model, base: CFrame)
	local green = Style.color("success")
	local balls = {
		{ Vector3.new(0, 2, 0), 4.6, 0 },
		{ Vector3.new(-1.7, 1.5, 0.9), 3.6, -0.12 },
		{ Vector3.new(1.6, 1.6, -0.8), 3.8, 0.08 },
		{ Vector3.new(0.5, 1.5, 1.8), 3.3, -0.05 },
		{ Vector3.new(-1, 1.4, -1.7), 3.2, 0.12 },
		{ Vector3.new(2, 1.2, 1.6), 2.6, -0.18 },
		{ Vector3.new(0.2, 3.5, 0.2), 2.8, 0.15 },
	}
	for index, ball in balls do
		local size = ball[2] :: number
		part(model, "Leaf" .. index, Vector3.one * size, base * CFrame.new(ball[1] :: Vector3), shade(green, ball[3] :: number), Enum.Material.LeafyGrass, Enum.PartType.Ball)
	end
	local flower = Style.color("coral")
	for index, offset in { Vector3.new(-2.3, 2.1, 1.3), Vector3.new(1.2, 3.3, 1.5), Vector3.new(2.5, 1.8, -0.2), Vector3.new(-0.6, 2.9, -1.9) } do
		part(model, "Flower" .. index, Vector3.one * 0.55, base * CFrame.new(offset), flower, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
end

-- Contenedor: caja de ~5,6 × 4,6 × 3,2 con tapa, franja de color, costillas y dos ruedas.
local function buildContainer(model: Model, base: CFrame)
	local body = Style.color("panelAlt")
	local stripe = Style.color("accent")
	local dark = Style.color("ink")
	part(model, "Body", Vector3.new(5.6, 3.6, 3.2), base * CFrame.new(0, 2.5, 0), body, Enum.Material.Metal)
	part(model, "Stripe", Vector3.new(5.64, 0.5, 3.24), base * CFrame.new(0, 1.6, 0), stripe, Enum.Material.Metal)
	part(model, "Lid", Vector3.new(5.9, 0.5, 3.5), base * CFrame.new(0, 4.55, 0), dark, Enum.Material.Metal)
	part(model, "LidHandle", Vector3.new(2, 0.3, 0.35), base * CFrame.new(0, 4.95, 1.55), stripe, Enum.Material.Metal)
	for index, x in { -2, 0, 2 } do
		part(model, "Rib" .. index, Vector3.new(0.25, 3.4, 3.3), base * CFrame.new(x, 2.5, 0), shade(body, -0.25), Enum.Material.Metal)
	end
	for index, x in { -2.2, 2.2 } do
		part(model, "Wheel" .. index, Vector3.new(0.5, 1, 1), base * CFrame.new(x, 0.5, 1.5), dark, Enum.Material.Rubber, Enum.PartType.Cylinder)
	end
end

-- Altura del suelo bajo una zona (la acera, no el asfalto), sin que el prop nuevo cuente.
local function groundHeight(zone: BasePart): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local origin = zone.Position + Vector3.new(0, zone.Size.Y / 2 + 4, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(zone.Size.Y + 12), 0), params)
	return if hit then hit.Position.Y else zone.Position.Y - zone.Size.Y / 2
end

local function build(zone: BasePart)
	local kind = zone:GetAttribute("HideKind")
	local id = `{zone:GetAttribute("LevelId")}/{zone:GetAttribute("PieceId")}` -- los ids de pieza se repiten entre distritos
	local model = Instance.new("Model")
	model.Name = "Hide_" .. id
	model:SetAttribute("HideId", id)
	model:SetAttribute("HideKind", if kind == "container" then "container" else "bush")
	local ground = groundHeight(zone)
	-- Un giro distinto por escondite (múltiplos de 90° para el contenedor, libre para el arbusto), estable entre partidas.
	local seed = 0
	for index = 1, #id do
		seed += string.byte(id, index)
	end
	local yaw = if kind == "container" then (seed % 4) * 90 else (seed * 37) % 360
	local base = CFrame.new(zone.Position.X, ground, zone.Position.Z) * CFrame.Angles(0, math.rad(yaw), 0)
	if kind == "container" then
		buildContainer(model, base)
	else
		buildBush(model, base)
	end
	model.Parent = folder
	CollectionService:AddTag(model, TAG)
end

function HidingProps.start()
	folder = Workspace:FindFirstChild("HideProps") :: Folder? or Instance.new("Folder")
	folder.Name = "HideProps"
	folder.Parent = Workspace
	for _, zone in Areas.parts("hide") do
		build(zone)
	end
	for _, zone in Areas.parts("tutorial_hide") do
		build(zone)
	end
end

return HidingProps
