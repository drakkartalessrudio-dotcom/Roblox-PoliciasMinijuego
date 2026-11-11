--[[
	HideFeedback · cómo se ven los escondites en el cliente. El servidor (Game/Hiding) decide quién está
	oculto y publica atributos del jugador; Game/HidingProps pone los props (etiqueta "HideProp").

	  Resaltado   con ≥ 1 estrella, los escondites a ≤ HIGHLIGHT_RANGE studs se resaltan (los 8 más cercanos):
	              amarillo (rol interactive) si ocultan, rojo (rol danger) si están quemados para ti.
	  Transparencia  oculto a salvo, tu personaje se ve semitransparente (solo para ti) para saber que estás cubierto.

	Atributos que lee: Stars, Hidden, HideBurned (";nivel/id;…").
	No decide nada: si el servidor no te oculta, aquí tampoco se muestra que lo estás.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Style = require(ReplicatedStorage.Shared:WaitForChild("Style"))

local TAG = "HideProp"
local HIGHLIGHT_RANGE = 80
local MAX_HIGHLIGHTS = 8
local HIDDEN_TRANSPARENCY = 0.55

local player = Players.LocalPlayer

local props: { [Model]: boolean } = {}
local highlights: { [Model]: Highlight } = {}
local originalTransparency: { [BasePart]: number } = {}

local function track(model: Instance)
	if model:IsA("Model") then
		props[model] = true
	end
end

local function untrack(model: Instance)
	if model:IsA("Model") then
		props[model] = nil
		local highlight = highlights[model]
		if highlight then
			highlight:Destroy()
			highlights[model] = nil
		end
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)
for _, model in CollectionService:GetTagged(TAG) do
	track(model)
end

local function highlightFor(model: Model): Highlight
	local highlight = highlights[model]
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "HideHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.7
		highlight.OutlineTransparency = 0.1
		highlight.Adornee = model
		highlight.Enabled = false
		highlight.Parent = model
		highlights[model] = highlight
	end
	return highlight
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function updateHighlights()
	local position = rootPosition()
	local stars = player:GetAttribute("Stars")
	local wanted = type(stars) == "number" and stars > 0 and position ~= nil
	local burned = player:GetAttribute("HideBurned")
	burned = if type(burned) == "string" then burned else ""

	local candidates: { { model: Model, distance: number } } = {}
	if wanted and position then
		for model in props do
			local distance = (model:GetPivot().Position - position).Magnitude
			if distance <= HIGHLIGHT_RANGE then
				table.insert(candidates, { model = model, distance = distance })
			end
		end
		table.sort(candidates, function(a, b)
			return a.distance < b.distance
		end)
	end
	local shown: { [Model]: boolean } = {}
	for index = 1, math.min(#candidates, MAX_HIGHLIGHTS) do
		local model = candidates[index].model
		shown[model] = true
		local highlight = highlightFor(model)
		local isBurned = string.find(burned, `;{model:GetAttribute("HideId")};`, 1, true) ~= nil
		local color = Style.color(if isBurned then "danger" else "interactive")
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.Enabled = true
	end
	for model, highlight in highlights do
		if not shown[model] then
			highlight.Enabled = false
		end
	end
end

-- Tu personaje, semitransparente solo para ti mientras estás oculto a salvo.
local function applyTransparency(hidden: boolean)
	local character = player.Character
	if hidden and character then
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
				if originalTransparency[descendant] == nil then
					originalTransparency[descendant] = descendant.Transparency
				end
				descendant.Transparency = math.max(originalTransparency[descendant], HIDDEN_TRANSPARENCY)
			end
		end
	else
		for part, original in originalTransparency do
			if part.Parent then
				part.Transparency = original
			end
		end
		table.clear(originalTransparency)
	end
end

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.3 then
		return
	end
	accumulated = 0
	updateHighlights()
	applyTransparency(player:GetAttribute("Hidden") == true)
end)
