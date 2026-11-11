--[[
	SpotFeedback · el sonido de los puntos de travesura, en el cliente. El servidor (Game/SpotProps)
	anima los props y avisa con Net "spot_fx"; aquí se oye.

	  doorbell   el timbre de un Timbrazo: un teléfono de juguete (dos tonos que se alternan,
	             dos veces "trrring"). Se oye en 3D desde el timbre, para todos los que estén cerca.

	El audio no puede viajar en el repositorio: hay que subir assets/audio/doorbell_toyphone.wav
	a Creator Hub y poner el ID en Config.SpotFx.DoorbellSoundId. Sin ID no suena (se avisa una vez).
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

local warned = false

-- Acepta "123456", "rbxassetid://123456" o cualquier URL de audio válida.
local function doorbellId(): string?
	local raw = Tuning.get("SpotFx.DoorbellSoundId")
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	if string.match(raw, "^%d+$") then
		return "rbxassetid://" .. raw
	end
	return raw
end

local function playDoorbell(position: Vector3)
	local id = doorbellId()
	if not id then
		if not warned then
			warned = true
			warn("[SpotFeedback] Config.SpotFx.DoorbellSoundId está vacío: el timbre no suena (sube assets/audio/doorbell_toyphone.wav y pega su ID)")
		end
		return
	end
	local range = Tuning.get("SpotFx.DoorbellRange")
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > range then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "DoorbellSound"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = position
	holder.Parent = Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = Tuning.get("SpotFx.DoorbellVolume")
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = range
	sound.Parent = holder
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	sound:Play()
	Debris:AddItem(holder, 8) -- por si el audio no carga (permiso o ID equivocado) y nunca termina
end

Net.on("spot_fx", function(payload)
	if type(payload) ~= "table" or typeof(payload.position) ~= "Vector3" then
		return
	end
	if payload.kind == "doorbell" then
		playDoorbell(payload.position)
	end
end)

-- Carga el audio de antemano para que el primer timbre no llegue tarde.
task.spawn(function()
	local id = doorbellId()
	if id then
		local sound = Instance.new("Sound")
		sound.SoundId = id
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
		sound:Destroy()
	end
end)
