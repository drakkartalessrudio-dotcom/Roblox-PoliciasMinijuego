--[[
	Hub: el centro social de La Guarida. Un panel con tres pestañas y el fundido del viaje.

	  Viajar     destinos con el nivel que piden, y la parcela propia (ir / soltar)
	  Logros     la lista de logros con su progreso
	  Jugadores  quién hay en el servidor con su nivel, Ascensiones y logros, para compararse
	             e invitar a la banda; al tocar la parcela de alguien se abre su perfil aquí

	Solo muestra estado que el servidor publica en atributos del jugador (Level,
	AscensionCount, AchCount, Ach_<id>, BandId, BandName, PlotId, District) y envía
	intenciones: `travel {id}`, `plot_go`, `plot_release` y `band {action = "invite"}`. El
	servidor valida nivel, estrellas y zona segura. Mensajes del servidor: `travel` (fundido)
	y `hub_inspect` (abrir el perfil de un jugador).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Destinations = require(Shared:WaitForChild("Destinations"))
local Net = require(Shared:WaitForChild("Net"))
local Style = require(Shared:WaitForChild("Style"))

local Hub = {}

local ROW_WIDTH = 520

local function number(instance: Instance, attribute: string): number
	local value = instance:GetAttribute(attribute)
	return if type(value) == "number" then value else 0
end

local function text(instance: Instance, attribute: string): string
	local value = instance:GetAttribute(attribute)
	return if type(value) == "string" then value else ""
end

local function achievementsOf(target: Player): { string }
	local names = {}
	for _, def in Catalog.achievements do
		if number(target, `Ach_{def.id}`) >= def.goal then
			table.insert(names, def.name)
		end
	end
	return names
end

-- Fundido a negro del viaje: el servidor avisa "out" antes de teletransportar y "in" al llegar.
local function mountFade()
	local localPlayer = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Kit_travel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	local cover = Instance.new("Frame")
	cover.BackgroundColor3 = Style.color("background")
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.Size = UDim2.fromScale(1, 1)
	cover.Visible = false
	cover.Active = false
	cover.Parent = gui
	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.5)
	caption.Size = UDim2.fromOffset(480, 60)
	caption.FontFace = Style.font("heading")
	caption.TextColor3 = Style.color("text")
	caption.TextSize = 36
	caption.TextTransparency = 1
	caption.Parent = cover

	local function fade(toTransparency: number, seconds: number, label: string?)
		if label then
			caption.Text = label
		end
		cover.Visible = true
		if GuiService.ReducedMotionEnabled then
			seconds = 0
		end
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(cover, info, { BackgroundTransparency = toTransparency }):Play()
		local tween = TweenService:Create(caption, info, { TextTransparency = toTransparency })
		tween:Play()
		if toTransparency >= 1 then
			tween.Completed:Once(function()
				if cover.BackgroundTransparency >= 1 then
					cover.Visible = false
				end
			end)
		end
	end

	Net.on("travel", function(data)
		if type(data) ~= "table" then
			return
		end
		local seconds = if type(data.seconds) == "number" then data.seconds else 0.35
		if data.phase == "out" then
			fade(0, seconds, if type(data.name) == "string" then data.name else nil)
		elseif data.phase == "in" then
			fade(1, seconds * 1.5, nil)
		end
	end)
end

function Hub.mount(Kit: any)
	local player = Players.LocalPlayer
	mountFade()

	local modal = Kit.modal("La Guarida")
	local tabs = Kit.tabs(modal.content, { "Viajar", "Logros", "Jugadores" })
	local updates: { () -> () } = {}

	local function row(parent: Instance): Frame
		return Kit.panel(parent, Enum.FillDirection.Horizontal)
	end

	-- Viajar ------------------------------------------------------------------
	local travel = tabs.pages["Viajar"]
	local plotPanel = Kit.panel(travel)
	local plotLabel = Kit.label({ text = "", kind = "body", parent = plotPanel, size = UDim2.fromOffset(ROW_WIDTH, 44) })
	local plotButtons = row(plotPanel)
	local goPlot = Kit.button({
		text = "Ir a mi parcela",
		variant = "secondary",
		parent = plotButtons,
		onActivated = function()
			Net.send("plot_go")
			modal:close()
		end,
	})
	local dropPlot = Kit.button({
		text = "Soltar parcela",
		variant = "danger",
		parent = plotButtons,
		onActivated = function()
			Net.send("plot_release")
		end,
	})
	table.insert(updates, function()
		local hasPlot = text(player, "PlotId") ~= ""
		plotLabel.Text = if hasPlot
			then "Tu parcela está en el lobby: tus visitas ven tu nivel, Ascensiones y logros."
			else "Reclama una parcela libre en el lobby (pedestal, tecla E) para mostrar tu progreso."
		goPlot.Visible = hasPlot and text(player, "District") == Destinations.HOME
		dropPlot.Visible = hasPlot
	end)

	for _, destination in Destinations.list do
		local line = Kit.panel(travel, Enum.FillDirection.Horizontal)
		local name = Kit.label({ text = destination.name, kind = "label", parent = line, size = UDim2.fromOffset(230, 36) })
		name.TextColor3 = destination.color
		local requirement = Kit.label({ text = "", kind = "number", color = "textMuted", parent = line, size = UDim2.fromOffset(120, 36) })
		local go = Kit.button({
			text = "Viajar",
			variant = "primary",
			parent = line,
			onActivated = function()
				Net.send("travel", { id = destination.id })
				modal:close()
			end,
		})
		table.insert(updates, function()
			local level = number(player, "Level")
			local here = text(player, "District") == destination.levelId
			local locked = level < destination.minLevel
			requirement.Text = if here then "Estás aquí" elseif locked then `Nivel {destination.minLevel}` else "Disponible"
			requirement.TextColor3 = Style.color(if locked then "danger" else "textMuted")
			go.Visible = not here and not locked
		end)
	end
	Kit.label({ text = "Solo se viaja desde una Guarida o un portal, sin estrellas.", kind = "body", color = "textMuted", parent = travel, size = UDim2.fromOffset(ROW_WIDTH, 40) })

	-- Logros -------------------------------------------------------------------
	local achievements = tabs.pages["Logros"]
	local summary = Kit.label({ text = "", kind = "heading", color = "reward", parent = achievements, size = UDim2.fromOffset(ROW_WIDTH, 36) })
	table.insert(updates, function()
		summary.Text = `Logros {number(player, "AchCount")}/{#Catalog.achievements}`
	end)
	for _, def in Catalog.achievements do
		local card = Kit.panel(achievements)
		local title = Kit.label({ text = def.name, kind = "label", parent = card, size = UDim2.fromOffset(ROW_WIDTH - 20, 26) })
		local detail = Kit.label({ text = "", kind = "body", color = "textMuted", parent = card, size = UDim2.fromOffset(ROW_WIDTH - 20, 24) })
		table.insert(updates, function()
			local value = number(player, `Ach_{def.id}`)
			local done = value >= def.goal
			title.Text = if done then `✓ {def.name}` else def.name
			title.TextColor3 = Style.color(if done then "reward" else "text")
			detail.Text = if done then def.description else `{def.description} · {math.floor(value)}/{def.goal}`
		end)
	end

	-- Jugadores ---------------------------------------------------------------
	local people = tabs.pages["Jugadores"]
	local profile = Kit.panel(people)
	local profileTitle = Kit.label({ text = "", kind = "heading", parent = profile, size = UDim2.fromOffset(ROW_WIDTH, 34) })
	local profileBody = Kit.label({ text = "", kind = "body", parent = profile, size = UDim2.fromOffset(ROW_WIDTH, 90) })
	local profileAchievements = Kit.label({ text = "", kind = "body", color = "textMuted", parent = profile, size = UDim2.fromOffset(ROW_WIDTH, 70) })
	local list = Kit.panel(people)
	local selected: Player? = nil

	local function summaryOf(target: Player): string
		local band = text(target, "BandName")
		return `Nivel {number(target, "Level")} · Ascensiones {number(target, "AscensionCount")} · Logros {number(target, "AchCount")}/{#Catalog.achievements}`
			.. (if band ~= "" then ` · Banda {band}` else "")
	end

	local function renderPeople()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if selected and selected.Parent ~= Players then
			selected = nil
		end
		profile.Visible = selected ~= nil
		if selected then
			profileTitle.Text = selected.DisplayName
			profileBody.Text = `{summaryOf(selected)}\nTú: {summaryOf(player)}`
			local names = achievementsOf(selected)
			profileAchievements.Text = if #names > 0 then "Logros: " .. table.concat(names, ", ") else "Todavía no tiene logros"
		end
		local everyone = Players:GetPlayers()
		table.sort(everyone, function(a, b)
			local levelA, levelB = number(a, "Level") + 100 * number(a, "AscensionCount"), number(b, "Level") + 100 * number(b, "AscensionCount")
			if levelA ~= levelB then
				return levelA > levelB
			end
			return a.DisplayName < b.DisplayName
		end)
		local myBand = text(player, "BandId")
		for _, other in everyone do
			local line = Kit.panel(list)
			Kit.label({ text = if other == player then `{other.DisplayName} (tú)` else other.DisplayName, kind = "label", parent = line, size = UDim2.fromOffset(ROW_WIDTH - 20, 26) })
			Kit.label({ text = summaryOf(other), kind = "body", color = "textMuted", parent = line, size = UDim2.fromOffset(ROW_WIDTH - 20, 24) })
			local actions = row(line)
			Kit.button({
				text = "Ver perfil",
				variant = "secondary",
				parent = actions,
				onActivated = function()
					selected = other
					renderPeople()
				end,
			})
			if other ~= player and myBand ~= "" and text(other, "BandId") ~= myBand then
				Kit.button({
					text = "Invitar a la banda",
					variant = "primary",
					parent = actions,
					onActivated = function()
						Net.send("band", { action = "invite", userId = other.UserId })
					end,
				})
			end
		end
	end
	table.insert(updates, function()
		if modal:isOpen() then
			renderPeople()
		end
	end)

	-- Refresco ------------------------------------------------------------------
	local queued = false
	local function refresh()
		if queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			for _, update in updates do
				update()
			end
		end)
	end

	local WATCHED = { "Level", "AscensionCount", "AchCount", "BandId", "BandName", "PlotId", "District" }
	local function watch(target: Player)
		for _, attribute in WATCHED do
			target:GetAttributeChangedSignal(attribute):Connect(refresh)
		end
	end
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerAdded:Connect(function(other)
		watch(other)
		refresh()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
	for _, def in Catalog.achievements do
		player:GetAttributeChangedSignal(`Ach_{def.id}`):Connect(refresh)
	end
	refresh()

	Net.on("hub_inspect", function(data)
		if type(data) ~= "table" or type(data.userId) ~= "number" then
			return
		end
		selected = Players:GetPlayerByUserId(data.userId)
		tabs:select("Jugadores")
		renderPeople()
		modal:open()
	end)

	Kit.button({
		text = "La Guarida",
		variant = "secondary",
		binding = { keyboard = Enum.KeyCode.H, gamepad = Enum.KeyCode.ButtonL2 },
		parent = Kit.slot("left"),
		onActivated = function()
			refresh()
			renderPeople()
			modal:open()
		end,
	})
end

return Hub
