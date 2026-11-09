--[[
	Layout · kit de UI de la fábrica (roblox-ui-designer).

	Crea las capas de pantalla (hud, menu, modal, toast) y los slots donde las
	pantallas colocan sus elementos raíz. Los slots se recalculan para no quedar
	debajo de la UI de Roblox:

	  - la ventana de chat y su barra de entrada (TextChatService), leyendo su
	    rectángulo real, que cambia según dispositivo y configuración;
	  - la barra superior, mediante ScreenInsets.CoreUISafeInsets;
	  - el joystick y el botón de salto en pantallas táctiles (TouchGui);
	  - la barra de herramientas de Roblox (mochila), abajo al centro, cuando está
	    activada y el jugador tiene herramientas.

	Slots: "top" (arriba al centro), "left" (riel izquierdo, debajo del chat),
	"right" (riel derecho), "bottom" (abajo al centro, entre los controles táctiles)
	y "actions" (junto al botón de salto en táctil; abajo a la derecha en el resto).

	Con el atributo booleano DebugZones en true en este ModuleScript, dibuja las
	zonas reservadas (con el color danger del tema) para revisarlas en Studio.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local Layout = {}

export type SlotName = "top" | "left" | "right" | "bottom" | "actions"

local LAYER_ORDER = { hud = 10, menu = 20, modal = 30, toast = 40 }
-- Alto reservado para la barra de herramientas de Roblox. Roblox no expone su
-- rectángulo: es una estimación con margen; revísala con DebugZones.
local HOTBAR_HEIGHT = 90

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local layers: { [string]: ScreenGui } = {}
local scales: { UIScale } = {}
local slots: { [string]: Frame } = {}
local topLimit: UISizeConstraint
local bottomLimit: UISizeConstraint
local debugFrames: { Frame } = {}
local currentScale = 1
local started = false

local function makeLayer(name: string, order: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Kit_" .. name
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	table.insert(scales, scale)
	gui.Parent = playerGui
	return gui
end

local function makeSlot(name: string, direction: Enum.FillDirection): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Slot_" .. name
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction
	list.Padding = UDim.new(0, Style.metric("spacing"))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = frame
	frame.Parent = layers.hud
	slots[name] = frame
	return frame
end

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function computeScale(): number
	local view = viewportSize()
	local scale = math.clamp(math.min(view.X / 1280, view.Y / 720), 0.85, 1.4)
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		-- En táctil no se achica: los botones mantienen su tamaño mínimo.
		scale = math.max(scale, 1)
	end
	if GuiService:IsTenFootInterface() then
		scale *= 1.25
	end
	return scale
end

local function rectOf(object: GuiBase2d): Rect?
	local size = object.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	return Rect.new(object.AbsolutePosition, object.AbsolutePosition + size)
end

-- Rectángulo de la ventana de chat y su barra de entrada, en coordenadas de pantalla.
function Layout.chatRect(): Rect?
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if not window or not window.Enabled then
		return nil
	end
	local size = window.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local min = window.AbsolutePosition
	local max = min + size
	local input = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if input and input.Enabled and input.AbsoluteSize.Y > 0 then
		local inputMax = input.AbsolutePosition + input.AbsoluteSize
		max = Vector2.new(math.max(max.X, inputMax.X), math.max(max.Y, inputMax.Y))
	end
	return Rect.new(min, max)
end

local function touchFrame(): Instance?
	if UserInputService.PreferredInput ~= Enum.PreferredInput.Touch or not GuiService.TouchControlsEnabled then
		return nil
	end
	local touchGui = playerGui:FindFirstChild("TouchGui")
	return touchGui and touchGui:FindFirstChild("TouchControlFrame")
end

-- Rectángulos de los controles táctiles por defecto (vacío si no se usan).
function Layout.touchRects(): { Rect }
	local rects = {}
	local frame = touchFrame()
	if frame then
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local rect = rectOf(child)
				if rect then
					table.insert(rects, rect)
				end
			end
		end
	end
	if #rects == 0 and UserInputService.PreferredInput == Enum.PreferredInput.Touch and GuiService.TouchControlsEnabled then
		-- Sin TouchGui todavía: se reservan las esquinas inferiores.
		local view = viewportSize()
		local height = math.min(view.Y * 0.45, 260)
		table.insert(rects, Rect.new(0, view.Y - height, view.X * 0.35, view.Y))
		table.insert(rects, Rect.new(view.X * 0.7, view.Y - height, view.X, view.Y))
	end
	return rects
end

local function jumpRect(): Rect?
	local frame = touchFrame()
	local jump = frame and frame:FindFirstChild("JumpButton")
	return if jump and jump:IsA("GuiObject") and jump.Visible then rectOf(jump) else nil
end

-- Franja de la barra de herramientas de Roblox, si está activada y hay herramientas.
local function hotbarRect(): Rect?
	if not StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack) then
		return nil
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local hasTool = (backpack and backpack:FindFirstChildOfClass("Tool")) or (character and character:FindFirstChildOfClass("Tool"))
	if not hasTool then
		return nil
	end
	local view = viewportSize()
	return Rect.new(view.X * 0.2, view.Y - HOTBAR_HEIGHT, view.X * 0.8, view.Y)
end

local function drawDebug(rects: { Rect })
	for _, frame in debugFrames do
		frame:Destroy()
	end
	table.clear(debugFrames)
	if script:GetAttribute("DebugZones") ~= true then
		return
	end
	local gui = layers.toast
	for _, rect in rects do
		local frame = Instance.new("Frame")
		frame.Name = "ReservedZone"
		frame.BackgroundColor3 = Style.color("danger")
		frame.BackgroundTransparency = 0.7
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromOffset((rect.Min.X - gui.AbsolutePosition.X) / currentScale, (rect.Min.Y - gui.AbsolutePosition.Y) / currentScale)
		frame.Size = UDim2.fromOffset(rect.Width / currentScale, rect.Height / currentScale)
		frame.Parent = gui
		table.insert(debugFrames, frame)
	end
end

-- Recalcula escala y posición de los slots. Se llama sola cuando cambia la pantalla,
-- el chat, el tipo de entrada o los controles táctiles.
function Layout.refresh()
	if not started then
		return
	end
	currentScale = computeScale()
	for _, scale in scales do
		scale.Scale = currentScale
	end
	local gui = layers.hud
	local origin = gui.AbsolutePosition
	local area = gui.AbsoluteSize
	local pad = Style.metric("spacing")
	local function toOffset(pixels: number): number
		return pixels / currentScale
	end

	-- Arriba al centro, sin invadir el ancho del chat si está arriba.
	slots.top.AnchorPoint = Vector2.new(0.5, 0)
	slots.top.Position = UDim2.new(0.5, 0, 0, pad)
	local chat = Layout.chatRect()
	local topWidth = area.X * 0.6
	if chat and chat.Min.Y - origin.Y < area.Y * 0.5 then
		local chatRight = chat.Max.X - origin.X
		local chatLeft = chat.Min.X - origin.X
		if chatLeft < area.X / 2 then
			topWidth = math.min(topWidth, area.X - 2 * (chatRight + pad))
		end
	end
	topLimit.MaxSize = Vector2.new(math.max(toOffset(topWidth), 120), math.huge)

	-- Riel izquierdo: centrado, o debajo del chat si el chat ocupa ese lado.
	local leftTop = area.Y * 0.35
	if chat and chat.Min.X - origin.X < area.X / 2 then
		leftTop = math.max(leftTop, chat.Max.Y - origin.Y + pad)
	end
	slots.left.AnchorPoint = Vector2.new(0, 0)
	slots.left.Position = UDim2.fromOffset(pad, toOffset(leftTop))

	-- Riel derecho: centrado verticalmente.
	slots.right.AnchorPoint = Vector2.new(1, 0.5)
	slots.right.Position = UDim2.new(1, -pad, 0.5, 0)

	-- Abajo al centro, entre los controles táctiles y sobre la barra de herramientas.
	local hotbar = hotbarRect()
	slots.bottom.AnchorPoint = Vector2.new(0.5, 1)
	slots.bottom.Position = UDim2.new(0.5, 0, 1, -pad - (if hotbar then toOffset(hotbar.Height) else 0))
	bottomLimit.MaxSize = Vector2.new(toOffset(area.X * 0.4), math.huge)

	-- Acciones: a la izquierda del botón de salto en táctil; abajo a la derecha en el resto.
	local jump = jumpRect()
	slots.actions.AnchorPoint = Vector2.new(1, 1)
	if jump then
		slots.actions.Position = UDim2.fromOffset(toOffset(jump.Min.X - origin.X - pad), toOffset(jump.Max.Y - origin.Y))
	else
		slots.actions.Position = UDim2.new(1, -pad, 1, -pad)
	end

	local reserved = Layout.touchRects()
	if chat then
		table.insert(reserved, chat)
	end
	if hotbar then
		table.insert(reserved, hotbar)
	end
	drawDebug(reserved)
end

-- Crea capas y slots (una sola vez) y conecta los recálculos.
function Layout.start()
	if started then
		return
	end
	started = true
	for name, order in LAYER_ORDER do
		layers[name] = makeLayer(name, order)
	end
	makeSlot("top", Enum.FillDirection.Vertical)
	makeSlot("left", Enum.FillDirection.Vertical)
	makeSlot("right", Enum.FillDirection.Vertical)
	makeSlot("bottom", Enum.FillDirection.Horizontal)
	makeSlot("actions", Enum.FillDirection.Horizontal)
	topLimit = Instance.new("UISizeConstraint")
	topLimit.Parent = slots.top
	bottomLimit = Instance.new("UISizeConstraint")
	bottomLimit.Parent = slots.bottom

	local function queue()
		task.defer(Layout.refresh)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(queue)
	end
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(queue)
	GuiService:GetPropertyChangedSignal("TouchControlsEnabled"):Connect(queue)
	layers.hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(queue)
	script:GetAttributeChangedSignal("DebugZones"):Connect(queue)
	for _, className in { "ChatWindowConfiguration", "ChatInputBarConfiguration" } do
		local config = TextChatService:FindFirstChildOfClass(className)
		if config then
			config:GetPropertyChangedSignal("AbsoluteSize"):Connect(queue)
			config:GetPropertyChangedSignal("AbsolutePosition"):Connect(queue)
			config:GetPropertyChangedSignal("Enabled"):Connect(queue)
		end
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "TouchGui" then
			task.delay(0.5, Layout.refresh)
		end
	end)
	-- Herramientas que entran o salen de la mochila (la mochila se recrea al reaparecer).
	local function watchTools(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				queue()
			end
		end)
		container.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				queue()
			end
		end)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watchTools(backpack)
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchTools(child)
			queue()
		end
	end)
	Layout.refresh()
end

function Layout.slot(name: SlotName): Frame
	assert(started, "[Kit] Llama a Kit.start() antes de usar slots")
	local frame = slots[name]
	assert(frame, `[Kit] Slot desconocido "{name}"`)
	return frame
end

function Layout.layer(name: string): ScreenGui
	assert(started, "[Kit] Llama a Kit.start() antes de usar capas")
	local gui = layers[name]
	assert(gui, `[Kit] Capa desconocida "{name}"`)
	return gui
end

function Layout.scale(): number
	return currentScale
end

return Layout
