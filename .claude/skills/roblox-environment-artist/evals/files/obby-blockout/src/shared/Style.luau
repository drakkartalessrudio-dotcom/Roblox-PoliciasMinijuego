--[[
	Style · plantilla del contrato de la fábrica (roblox-game-builder).

	Lee el tema del juego (src/shared/Theme.json, dueño: roblox-art-director) y lo
	entrega listo para usar. La UI, el mundo y los efectos piden colores, fuentes,
	materiales y métricas por rol, en lugar de escribir valores en el código:

	  Style.color("hazard")       -- Color3 del rol (o de un color de la paleta)
	  Style.font("heading")       -- Font para TextLabel.FontFace
	  Style.material("surface")   -- Enum.Material del rol
	  Style.metric("cornerRadius")-- número de Theme.ui
	  Style.applyLighting("default") -- solo servidor: aplica un preset de iluminación

	Un rol que no existe en el tema es un error de programación y falla en el acto.
	LightingStyle y PrioritizeLightingQuality no se cambian por script: van en
	default.project.json (ver references/hooks.md).
]]

local RunService = game:GetService("RunService")

local Theme: any = require(script.Parent:WaitForChild("Theme"))

local Style = {}

local colorCache: { [string]: Color3 } = {}
local fontCache: { [string]: Font } = {}

local function hexOf(reference: string): string?
	if string.match(reference, "^#%x%x%x%x%x%x$") then
		return reference
	end
	local palette = Theme.palette or {}
	local roles = Theme.roles or {}
	local swatch = roles[reference] or reference
	local hex = palette[swatch]
	return if type(hex) == "string" then hex else nil
end

-- Color3 de un rol ("hazard"), de un color de la paleta ("lava") o de un "#RRGGBB".
function Style.color(reference: string): Color3
	local cached = colorCache[reference]
	if cached then
		return cached
	end
	local hex = hexOf(reference)
	if not hex then
		error(`[Style] El color "{reference}" no está en Theme.json`, 2)
	end
	local color = Color3.fromHex(hex)
	colorCache[reference] = color
	return color
end

-- Font de un tipo de texto del tema ("heading", "body", "label", "number").
function Style.font(kind: string): Font
	local cached = fontCache[kind]
	if cached then
		return cached
	end
	local spec = Theme.fonts and Theme.fonts[kind]
	if type(spec) ~= "table" then
		error(`[Style] La fuente "{kind}" no está en Theme.json`, 2)
	end
	local ok, font = pcall(function()
		local family = Font.fromEnum((Enum.Font :: any)[spec.font]).Family
		local weight = (Enum.FontWeight :: any)[spec.weight or "Regular"]
		return Font.new(family, weight, Enum.FontStyle.Normal)
	end)
	if not ok then
		warn(`[Style] Fuente "{kind}" inválida en Theme.json ({font}); se usa BuilderSans`)
		font = Font.fromEnum(Enum.Font.BuilderSans)
	end
	fontCache[kind] = font
	return font
end

-- Material de un rol ("surface", "hazard"...). Sin entrada en el tema, SmoothPlastic.
function Style.material(role: string): Enum.Material
	local name = Theme.materials and Theme.materials[role]
	if type(name) ~= "string" then
		return Enum.Material.SmoothPlastic
	end
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and material then material else Enum.Material.SmoothPlastic
end

-- Métrica de UI del tema ("cornerRadius", "spacing", "minTouchTarget"...).
function Style.metric(name: string): number
	local value = Theme.ui and Theme.ui[name]
	if type(value) ~= "number" then
		error(`[Style] La métrica "{name}" no está en Theme.json`, 2)
	end
	return value
end

local function ensureChild(parent: Instance, className: string): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local child = Instance.new(className)
	child.Parent = parent
	return child
end

-- Aplica un preset de Theme.lighting.presets. Solo en el servidor: Lighting replica a
-- todos los clientes. Las propiedades que el preset no define quedan como estaban.
function Style.applyLighting(presetName: string?)
	assert(RunService:IsServer(), "[Style] applyLighting solo se usa en el servidor")
	local Lighting = game:GetService("Lighting")
	local presets = Theme.lighting and Theme.lighting.presets or {}
	local preset = presets[presetName or "default"]
	if type(preset) ~= "table" then
		warn(`[Style] No hay preset de iluminación "{presetName or "default"}" en Theme.json`)
		return
	end
	local numbers = {
		clockTime = "ClockTime",
		brightness = "Brightness",
		exposure = "ExposureCompensation",
		environmentDiffuseScale = "EnvironmentDiffuseScale",
		environmentSpecularScale = "EnvironmentSpecularScale",
		shadowSoftness = "ShadowSoftness",
	}
	for key, property in numbers do
		if type(preset[key]) == "number" then
			(Lighting :: any)[property] = preset[key]
		end
	end
	local colors = {
		ambient = "Ambient",
		outdoorAmbient = "OutdoorAmbient",
		colorShiftTop = "ColorShift_Top",
		colorShiftBottom = "ColorShift_Bottom",
	}
	for key, property in colors do
		if type(preset[key]) == "string" then
			(Lighting :: any)[property] = Style.color(preset[key])
		end
	end
	if type(preset.globalShadows) == "boolean" then
		Lighting.GlobalShadows = preset.globalShadows
	end
	if type(preset.fog) == "table" then
		if preset.fog.color then
			Lighting.FogColor = Style.color(preset.fog.color)
		end
		Lighting.FogStart = preset.fog.start or Lighting.FogStart
		Lighting.FogEnd = preset.fog["end"] or Lighting.FogEnd
	end
	if type(preset.atmosphere) == "table" then
		local atmosphere = ensureChild(Lighting, "Atmosphere") :: Atmosphere
		local values = preset.atmosphere
		atmosphere.Density = values.density or atmosphere.Density
		atmosphere.Offset = values.offset or atmosphere.Offset
		atmosphere.Glare = values.glare or atmosphere.Glare
		atmosphere.Haze = values.haze or atmosphere.Haze
		if values.color then
			atmosphere.Color = Style.color(values.color)
		end
		if values.decay then
			atmosphere.Decay = Style.color(values.decay)
		end
	end
	if type(preset.colorCorrection) == "table" then
		local effect = ensureChild(Lighting, "ColorCorrectionEffect") :: ColorCorrectionEffect
		local values = preset.colorCorrection
		effect.Brightness = values.brightness or effect.Brightness
		effect.Contrast = values.contrast or effect.Contrast
		effect.Saturation = values.saturation or effect.Saturation
		if values.tint then
			effect.TintColor = Style.color(values.tint)
		end
	end
	if type(preset.bloom) == "table" then
		local effect = ensureChild(Lighting, "BloomEffect") :: BloomEffect
		effect.Intensity = preset.bloom.intensity or effect.Intensity
		effect.Size = preset.bloom.size or effect.Size
		effect.Threshold = preset.bloom.threshold or effect.Threshold
	end
	if type(preset.sunRays) == "table" then
		local effect = ensureChild(Lighting, "SunRaysEffect") :: SunRaysEffect
		effect.Intensity = preset.sunRays.intensity or effect.Intensity
		effect.Spread = preset.sunRays.spread or effect.Spread
	end
end

return Style
