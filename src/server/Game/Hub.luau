--[[
	Hub · lo que pasa en La Guarida (el lobby) de TravesurasBrainrot: el centro social del
	juego y la zona segura donde aparecen todos. Mezcla Areas, Plots, Achievements y
	Transit con el progreso de cada jugador, así que es de Game.

	  portales     zonas "portal" (atributo Target = id de Destinations): un aviso para viajar y
	               un cartel con el nombre y el nivel; los de los distritos vuelven al lobby
	  parcelas     16 pedestales: se reclaman con el aviso (una por jugador, mientras esté en el
	               servidor). El cartel de cada parcela muestra al dueño: nivel, Ascensiones y
	               logros; encima del pedestal crece una torre con su nivel. Quien pasa por una
	               parcela ajena puede abrir su perfil para compararse
	  logros       Achievements.metric calcula cada logro con datos que ya se guardan; al cruzar
	               uno se avisa al jugador

	Mensajes al cliente (Net.send):
	  hub_inspect {userId}      abre el perfil de ese jugador (el de la parcela que tocaron)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Destinations = require(ReplicatedStorage.Shared.Destinations)
local Net = require(ReplicatedStorage.Shared.Net)
local Style = require(ReplicatedStorage.Shared.Style)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local LevelLoader = require(ServerScriptService.Server.LevelLoader)
local Achievements = require(ServerScriptService.Server.Modules.Achievements)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local Arrest = require(ServerScriptService.Server.Modules.Arrest)
local Ascension = require(ServerScriptService.Server.Modules.Ascension)
local Mischief = require(ServerScriptService.Server.Modules.Mischief)
local Plots = require(ServerScriptService.Server.Modules.Plots)
local Progress = require(ServerScriptService.Server.Modules.Progress)
local Stats = require(ServerScriptService.Server.Modules.Stats)
local Movement = require(script.Parent.Movement)
local Transit = require(script.Parent.Transit)

local Hub = {}

local TOWER_BASE = 3 -- studs de torre con nivel 1
local TOWER_PER_LEVEL = 0.45 -- studs que suma cada nivel (nivel 50 ≈ 25 studs)
local TOWER_MAX = 28

type PlotView = {
	part: BasePart,
	number: number,
	pedestal: BasePart,
	prompt: ProximityPrompt,
	title: TextLabel,
	detail: TextLabel,
	tower: Part?,
}

local views: { PlotView } = {}

-- Métrica de cada logro (Catalog.achievements[].metric) con datos que ya se guardan.
function Hub.metric(player: Player, metric: string): number
	local stat = string.match(metric, "^stat:(.+)$")
	if stat then
		return Stats.get(player, stat)
	elseif metric == "level" then
		-- La Ascensión reinicia el nivel; haberla hecho implica haber llegado al máximo.
		return if Ascension.count(player) > 0 then Tuning.get("Progress.MaxLevel") else Progress.level(player)
	elseif metric == "ascensions" then
		return Ascension.count(player)
	elseif metric == "album" then
		return Mischief.designCount(player)
	end
	return 0
end

-- Último distrito que el nivel del jugador deja visitar: da color a su torre.
local function frontier(level: number): Destinations.Destination
	local best = Destinations.byId[Destinations.START]
	for _, destination in Destinations.list do
		if destination.kind == "district" and destination.minLevel <= level then
			best = destination
		end
	end
	return best
end

local function label(parent: Instance, size: UDim2, position: UDim2, kind: string, color: string): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = size
	text.Position = position
	text.TextScaled = true
	text.TextWrapped = true
	text.FontFace = Style.font(kind)
	text.TextColor3 = Style.color(color)
	text.Parent = parent
	return text
end

local function billboard(parent: BasePart, offset: Vector3, size: UDim2, maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = false
	gui.Parent = parent
	return gui
end

local function notify(player: Player, payload: { [string]: any })
	Net.send(player, "notify", payload)
end

-- ---------------------------------------------------------------- portales

local function setupPortal(zone: BasePart)
	local target = zone:GetAttribute("Target")
	local destination = if type(target) == "string" then Destinations.byId[target] else nil
	if not destination then
		warn(`[Hub] El portal {zone.Name} no tiene un destino válido ({target})`)
		return
	end
	local home = destination.id == Destinations.HOME
	local gui = billboard(zone, Vector3.new(0, if home then 5 else 14, 0), UDim2.fromOffset(240, 70), 140)
	local title = label(gui, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0), "heading", "text")
	title.Text = if home then "Volver a La Guarida" else destination.name
	title.TextColor3 = destination.color
	title.TextStrokeTransparency = 0.4
	local subtitle = label(gui, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6), "label", "mist")
	subtitle.Text = if home then "Zona segura" elseif destination.minLevel > 1 then `Nivel {destination.minLevel}` else "Para empezar"
	subtitle.TextStrokeTransparency = 0.5

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Viajar"
	prompt.ObjectText = destination.name
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = zone
	prompt.Triggered:Connect(function(player)
		local ok, reason = Transit.to(player, destination.id)
		if not ok then
			Hub.travelError(player, destination, reason)
		end
	end)
end

-- Avisa por qué no se pudo viajar; con "level" dice cuánto falta.
function Hub.travelError(player: Player, destination: Destinations.Destination, reason: string?)
	if reason == "level" then
		notify(player, { kind = "travel_locked", name = destination.name, level = destination.minLevel })
	elseif reason ~= "here" and reason ~= "cooldown" and reason ~= "busy" then
		notify(player, { kind = "error", code = reason })
	end
end

-- ---------------------------------------------------------------- parcelas

local function describe(owner: Player): (string, string)
	local level = Progress.level(owner)
	local ascensions = Ascension.count(owner)
	local bandName = owner:GetAttribute("BandName")
	local detail = `Nivel {level}  ·  Ascensiones {ascensions}\nLogros {Achievements.count(owner)}/{#Catalog.achievements}`
	if type(bandName) == "string" and bandName ~= "" then
		detail ..= `\nBanda {bandName}`
	end
	return owner.DisplayName, detail
end

local function updateTower(view: PlotView, owner: Player?)
	if not owner then
		if view.tower then
			view.tower:Destroy()
			view.tower = nil
		end
		return
	end
	local height = math.min(TOWER_BASE + TOWER_PER_LEVEL * Progress.level(owner), TOWER_MAX)
	local tower = view.tower
	if not tower then
		tower = Instance.new("Part")
		tower.Name = "Torre"
		tower.Anchored = true
		tower.CanCollide = true
		tower.Material = Enum.Material.Neon
		tower.TopSurface = Enum.SurfaceType.Smooth
		tower.BottomSurface = Enum.SurfaceType.Smooth
		tower.Parent = view.part.Parent
		view.tower = tower
	end
	assert(tower)
	tower.Size = Vector3.new(4, height, 4)
	tower.Color = frontier(Progress.level(owner)).color
	-- Sobre el pedestal, en su orientación.
	tower.CFrame = view.pedestal.CFrame * CFrame.new(0, view.pedestal.Size.Y / 2 + height / 2, 0)
end

local function updateView(view: PlotView)
	local owner = Plots.ownerOf(view.part)
	if owner then
		local name, detail = describe(owner)
		view.title.Text = name
		view.detail.Text = detail
		view.prompt.ActionText = "Ver perfil"
		view.prompt.ObjectText = name
	else
		view.title.Text = "PARCELA LIBRE"
		view.detail.Text = "Reclámala en el pedestal\ny muestra tu progreso"
		view.prompt.ActionText = "Reclamar parcela"
		view.prompt.ObjectText = `Parcela {view.number}`
	end
	updateTower(view, owner)
end

local function setupPlot(level: LevelLoader.BuiltLevel, part: BasePart)
	local number = tonumber(string.match(part.Name, "(%d+)$"))
	local pedestal = if number then level.pieces[`parcela-pedestal-{number}`] else nil
	local sign = if number then level.pieces[`parcela-cartel-{number}`] else nil
	if not number or not pedestal or not sign then
		warn(`[Hub] La parcela {part.Name} no tiene pedestal y cartel`)
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = sign
	local title = label(gui, UDim2.fromScale(0.94, 0.3), UDim2.fromScale(0.03, 0.04), "heading", "text")
	local detail = label(gui, UDim2.fromScale(0.94, 0.58), UDim2.fromScale(0.03, 0.36), "body", "mist")
	detail.TextXAlignment = Enum.TextXAlignment.Left

	local prompt = Instance.new("ProximityPrompt")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal

	local view: PlotView = { part = part, number = number, pedestal = pedestal, prompt = prompt, title = title, detail = detail, tower = nil }
	table.insert(views, view)
	prompt.Triggered:Connect(function(player)
		local owner = Plots.ownerOf(part)
		if owner then
			Net.send(player, "hub_inspect", { userId = owner.UserId })
			return
		end
		local ok, reason = Plots.claim(player, part)
		if not ok then
			notify(player, { kind = "error", code = if reason == "already" then "plot_have" else "plot_taken" })
		end
	end)
	updateView(view)
end

-- Se lleva al jugador a la entrada de su parcela (el cartel mira al centro del lobby).
function Hub.goToPlot(player: Player): boolean
	local part = Plots.plotOf(player)
	if not part or Arrest.isHeld(player) or not Areas.inside(player, "lobby") then
		return false
	end
	for _, view in views do
		if view.part == part then
			return Movement.teleport(player, view.pedestal.Position + Vector3.new(0, 1, 0) + view.pedestal.CFrame.LookVector * -8)
		end
	end
	return false
end

-- ---------------------------------------------------------------- arranque

function Hub.start(built: LevelLoader.Built)
	local lobby = built.byId[Destinations.byId[Destinations.HOME].levelId]
	assert(lobby, "Levels.json no tiene el nivel del lobby")

	for _, zone in Areas.parts("portal") do
		setupPortal(zone)
	end
	for _, part in Plots.list() do
		setupPlot(lobby, part)
	end

	local monument = lobby.pieces["monumento-cima"]
	if monument then
		local gui = billboard(monument, Vector3.new(0, 10, 0), UDim2.fromOffset(320, 90), 400)
		local title = label(gui, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0), "heading", "cyan")
		title.Text = "LA GUARIDA"
		title.TextStrokeTransparency = 0.3
		local subtitle = label(gui, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6), "label", "snow")
		subtitle.Text = "Zona segura · reclama tu parcela"
		subtitle.TextStrokeTransparency = 0.4
	end

	Plots.claimed:Connect(function(player, part)
		for _, view in views do
			if view.part == part then
				updateView(view)
			end
		end
		Telemetry.custom(player, "plot_claimed", nil, { item = part.Name })
	end)
	Plots.released:Connect(function(_player, part)
		for _, view in views do
			if view.part == part then
				updateView(view)
			end
		end
	end)
	-- Los carteles siguen el progreso del dueño.
	task.spawn(function()
		while true do
			task.wait(Tuning.get("Plots.StandRefreshSeconds"))
			for _, view in views do
				if Plots.ownerOf(view.part) then
					updateView(view)
				end
			end
		end
	end)

	-- Logros.
	Progress.loaded:Connect(function(player)
		Achievements.sync(player)
	end)
	Progress.leveledUp:Connect(function(player)
		Achievements.refresh(player)
	end)
	Stats.incremented:Connect(function(player)
		Achievements.refresh(player)
	end)
	Ascension.ascended:Connect(function(player)
		Achievements.refresh(player)
	end)
	Achievements.unlocked:Connect(function(player, def)
		notify(player, { kind = "achievement", name = def.name, description = def.description })
		Telemetry.custom(player, "achievement_unlocked", nil, { item = def.id })
	end)
end

return Hub
