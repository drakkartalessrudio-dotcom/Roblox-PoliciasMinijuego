--!strict
--[[
	SoundBank · reproduce los cues de audio de Audio.json.

	Copia de la plantilla de roblox-audio-designer (src/shared/SoundBank.luau). No pongas aquí
	nada del juego: los IDs, volúmenes y alcances viven en src/shared/Audio.json y el código
	solo nombra el cue.

	    SoundBank.play("SpotDoorbell", { position = spot.Position })   -- 3D, en un punto
	    SoundBank.play("UiClick")                                      -- 2D, suena igual en todas partes
	    local music = SoundBank.play("MusicCity")                      -- en bucle: devuelve el Sound
	    SoundBank.setBusVolume("music", 0.3)                           -- ajustes del jugador
	    SoundBank.preload({ "SpotDoorbell", "UiClick" })               -- antes de la primera vez

	Dónde llamarlo: los efectos que oye un jugador (interfaz, respuestas a sus acciones, timbres
	cercanos) se reproducen en el CLIENTE: el servidor avisa por un RemoteEvent y el cliente llama
	a play. Así el sonido nace en el cliente que lo oye y no depende de que un Part replicado
	llegue a tiempo. El servidor solo reproduce ambiente compartido.

	Un cue sin ID (id vacío en Audio.json) no suena y avisa una sola vez. Un cue desconocido
	avisa una sola vez y devuelve nil: el juego sigue.

	Implementación: usa Sound porque funciona y se prueba igual en Studio. Roblox recomienda
	hoy los objetos AudioPlayer, AudioEmitter y Wire; migrar es cambiar el cuerpo de `spawn`
	sin tocar la API ni Audio.json.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local data: any = require(script.Parent.Audio)

export type PlayOptions = {
	position: Vector3?, -- si el cue es espacial, dónde suena
	parent: Instance?, -- si el cue es espacial, en qué Part o Attachment suena (sigue su movimiento)
	volumeScale: number?, -- multiplica el volumen del cue (0 a 1) para este disparo
}

local SoundBank = {}

local lastPlayed: { [string]: number } = {}
local warned: { [string]: boolean } = {}
local busVolume: { [string]: number } = {}
local activeLoops: { [Sound]: { bus: string, base: number } } = {}

for name, bus in data.buses do
	busVolume[name] = bus.volume
end

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(`[SoundBank] {message}`)
end

local function soundIdFor(cueId: string): (any?, any?)
	local cue = data.cues[cueId]
	if cue == nil then
		warnOnce(`cue:{cueId}`, `el cue "{cueId}" no está en Audio.json`)
		return nil, nil
	end
	local asset = data.assets[cue.asset]
	if asset == nil or asset.id == nil or asset.id == "" then
		warnOnce(`id:{cueId}`, `el cue "{cueId}" no suena: el asset "{cue.asset}" no tiene ID (súbelo a Creator Hub y pégalo en Audio.json)`)
		return nil, nil
	end
	return cue, asset
end

local function holderAt(position: Vector3): Part
	local holder = Instance.new("Part")
	holder.Name = "SoundBankEmitter"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = position
	holder.Parent = Workspace
	return holder
end

function SoundBank.play(cueId: string, options: PlayOptions?): Sound?
	local cue, asset = soundIdFor(cueId)
	if cue == nil then
		return nil
	end
	local opts: PlayOptions = options or {}

	local now = os.clock()
	local wait = tonumber(cue.cooldown) or 0
	if wait > 0 and lastPlayed[cueId] ~= nil and now - lastPlayed[cueId] < wait then
		return nil
	end
	lastPlayed[cueId] = now

	local bus = cue.bus
	local base = (tonumber(cue.volume) or 1) * (opts.volumeScale or 1)
	local sound = Instance.new("Sound")
	sound.Name = cueId
	sound.SoundId = asset.id
	sound.Volume = base * (busVolume[bus] or 1)
	sound.Looped = cue.looped == true
	local variance = tonumber(cue.pitchVariance) or 0
	if variance > 0 then
		sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * variance
	end

	local owner: Instance = SoundService
	local spatial = cue.spatial
	if spatial ~= nil then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = spatial.minDistance
		sound.RollOffMaxDistance = spatial.maxDistance
		if opts.parent ~= nil then
			owner = opts.parent
		elseif opts.position ~= nil then
			owner = holderAt(opts.position)
		else
			warnOnce(`pos:{cueId}`, `el cue "{cueId}" es espacial y se disparó sin position ni parent: suena sin posición`)
		end
	elseif opts.parent ~= nil then
		owner = opts.parent
	end
	sound.Parent = owner

	if sound.Looped then
		activeLoops[sound] = { bus = bus, base = base }
		sound.Destroying:Once(function()
			activeLoops[sound] = nil
		end)
	else
		local temporary = owner ~= SoundService and owner ~= opts.parent
		sound.Ended:Once(function()
			if temporary then
				owner:Destroy()
			else
				sound:Destroy()
			end
		end)
		-- Por si el audio nunca carga (sin permiso o ID equivocado) y Ended no llega.
		local limit = (tonumber(asset.durationSeconds) or 10) + 5
		Debris:AddItem(if temporary then owner else sound, limit)
	end
	sound:Play()
	return sound
end

function SoundBank.setBusVolume(bus: string, volume: number)
	if data.buses[bus] == nil then
		warnOnce(`bus:{bus}`, `el bus "{bus}" no está en Audio.json`)
		return
	end
	busVolume[bus] = math.clamp(volume, 0, 1)
	for sound, entry in activeLoops do
		if entry.bus == bus then
			sound.Volume = entry.base * busVolume[bus]
		end
	end
end

function SoundBank.getBusVolume(bus: string): number
	return busVolume[bus] or 1
end

-- Carga los audios con ID de antemano para que el primer disparo no llegue tarde.
-- Sin lista, precarga todos los cues.
function SoundBank.preload(cueIds: { string }?)
	local sounds = {}
	local seen: { [string]: boolean } = {}
	local ids = cueIds
	if ids == nil then
		ids = {}
		for cueId in data.cues do
			table.insert(ids :: { string }, cueId)
		end
	end
	for _, cueId in ids :: { string } do
		local cue = data.cues[cueId]
		local asset = if cue then data.assets[cue.asset] else nil
		if asset ~= nil and asset.id ~= "" and not seen[asset.id] then
			seen[asset.id] = true
			local sound = Instance.new("Sound")
			sound.SoundId = asset.id
			table.insert(sounds, sound)
		end
	end
	if #sounds == 0 then
		return
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(sounds)
	end)
	if not ok then
		warn(`[SoundBank] no se pudo precargar: {err}`)
	end
	for _, sound in sounds do
		sound:Destroy()
	end
end

return SoundBank
