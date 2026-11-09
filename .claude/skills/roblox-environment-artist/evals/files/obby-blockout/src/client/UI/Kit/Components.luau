--[[
	Components · kit de UI de la fábrica (roblox-ui-designer).

	Piezas de interfaz que ya cumplen las reglas de la fábrica: colores, fuentes y
	medidas del tema (Style), tamaño táctil mínimo, texto escalado con límites,
	navegación con gamepad, accesibilidad (tamaño de texto preferido y movimiento
	reducido) y estados de presión. Las pantallas las usan en vez de crear
	TextButton o Frame sueltos.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))
local Input = require(script.Parent:WaitForChild("Input"))
local Layout = require(script.Parent:WaitForChild("Layout"))

local Components = {}

export type TextKind = "heading" | "body" | "label" | "number"
export type ButtonVariant = "primary" | "secondary" | "danger"

export type LabelProps = {
	text: string?,
	kind: TextKind?,
	color: string?,
	size: UDim2?,
	parent: Instance?,
}

export type ButtonProps = {
	text: string,
	variant: ButtonVariant?,
	binding: Input.Binding?,
	onActivated: () -> (),
	parent: Instance?,
	layoutOrder: number?,
}

export type Modal = {
	frame: Frame,
	content: Frame,
	open: (self: Modal) -> (),
	close: (self: Modal) -> (),
	isOpen: (self: Modal) -> boolean,
}

local TEXT_SCALE: { [string]: number } = { Medium = 1, Large = 1.15, Larger = 1.3, Largest = 1.5 }

local function textScale(): number
	return TEXT_SCALE[GuiService.PreferredTextSize.Name] or 1
end

local function reducedMotion(): boolean
	return GuiService.ReducedMotionEnabled
end

local function decorate(object: GuiObject, stroke: boolean)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Style.metric("cornerRadius"))
	corner.Parent = object
	if stroke then
		local border = Instance.new("UIStroke")
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		border.Color = Style.color("surfaceAlt")
		border.Thickness = Style.metric("strokeThickness")
		border.Parent = object
	end
	local padding = Instance.new("UIPadding")
	local pad = UDim.new(0, Style.metric("spacing"))
	padding.PaddingLeft = pad
	padding.PaddingRight = pad
	padding.PaddingTop = pad
	padding.PaddingBottom = pad
	padding.Parent = object
end

local function limitText(object: GuiObject, kind: TextKind)
	-- TextLabel y TextButton comparten estas propiedades; el cast evita la unión de tipos.
	local text = object :: any
	text.TextScaled = true
	text.TextWrapped = true
	text.FontFace = Style.font(kind)
	local limit = Instance.new("UITextSizeConstraint")
	local scale = textScale()
	local maxSize = if kind == "heading" then Style.metric("textSizeMax") else Style.metric("textSizeMax") * 0.75
	limit.MinTextSize = math.floor(Style.metric("textSizeMin") * scale)
	limit.MaxTextSize = math.floor(maxSize * scale)
	limit.Parent = object
end

-- Panel con fondo, esquinas, borde y espaciado del tema. Los hijos se apilan.
function Components.panel(parent: Instance?, direction: Enum.FillDirection?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.BackgroundColor3 = Style.color("panel")
	frame.BackgroundTransparency = Style.metric("panelTransparency") * (1 - GuiService.PreferredTransparency)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	decorate(frame, true)
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction or Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, Style.metric("spacing"))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = frame
	frame.Parent = parent
	return frame
end

-- Texto con fuente, color y tamaño del tema.
function Components.label(props: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Text = props.text or ""
	label.TextColor3 = Style.color(props.color or "text")
	label.Size = props.size or UDim2.fromOffset(280, 32)
	limitText(label, props.kind or "body")
	label.Parent = props.parent
	return label
end

-- Botón con tamaño táctil mínimo, atajo opcional de teclado y gamepad, y el texto
-- del atajo según la entrada actual ("Tienda (B)" en teclado, "Tienda" en táctil).
function Components.button(props: ButtonProps): TextButton
	local variant = props.variant or "primary"
	local button = Instance.new("TextButton")
	button.Name = props.text
	button.AutoButtonColor = false
	button.Selectable = true
	button.LayoutOrder = props.layoutOrder or 0
	button.BackgroundColor3 = Style.color(if variant == "primary" then "accent" elseif variant == "danger" then "danger" else "panel")
	button.TextColor3 = Style.color(if variant == "secondary" then "text" else "textOnAccent")
	local minimum = Style.metric("minTouchTarget")
	button.Size = UDim2.fromOffset(math.max(minimum * 3, 132), minimum)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(minimum, minimum)
	sizeLimit.Parent = button
	decorate(button, variant == "secondary")
	limitText(button, "label")

	local function render()
		local hint = Input.hint(props.binding)
		button.Text = if hint ~= "" then `{props.text} ({hint})` else props.text
	end
	Input.onChanged(render)

	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function press(target: number)
		if reducedMotion() then
			return
		end
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = target }):Play()
	end
	button.MouseButton1Down:Connect(function()
		press(0.95)
	end)
	button.MouseButton1Up:Connect(function()
		press(1)
	end)
	button.MouseLeave:Connect(function()
		press(1)
	end)
	button.Activated:Connect(props.onActivated)
	if props.binding then
		Input.bindAction(props.text, props.binding, props.onActivated)
	end
	button.Parent = props.parent
	return button
end

local openModal: Modal? = nil

-- Ventana modal centrada en la capa "modal", con título, botón de cerrar (también
-- con B en gamepad) y fondo que bloquea los clics. Solo hay una abierta a la vez.
function Components.modal(title: string, onClose: (() -> ())?): Modal
	local gui = Layout.layer("modal")
	local shade = Instance.new("Frame")
	shade.Name = "Modal_" .. title
	shade.Active = true
	shade.Visible = false
	shade.BackgroundColor3 = Style.color("background")
	shade.BackgroundTransparency = 0.4
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = gui

	local window = Components.panel(shade)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(560, 460)
	maxSize.Parent = window

	Components.label({ text = title, kind = "heading", parent = window, size = UDim2.fromOffset(360, 40) })
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	content.Size = UDim2.fromOffset(0, 0)
	content.LayoutOrder = 1
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, Style.metric("spacing"))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = content
	content.Parent = window

	local modal: Modal
	local closeButton = Components.button({
		text = "Cerrar",
		variant = "secondary",
		layoutOrder = 2,
		parent = window,
		onActivated = function()
			modal:close()
		end,
	})
	local unbindClose: (() -> ())? = nil

	modal = {
		frame = window,
		content = content,
		open = function(self: Modal)
			if openModal and openModal ~= self then
				openModal:close()
			end
			openModal = self
			shade.Visible = true
			if Input.preferred() == Enum.PreferredInput.Gamepad then
				GuiService.SelectedObject = closeButton
			end
			unbindClose = Input.bindAction("CloseModal", { gamepad = Enum.KeyCode.ButtonB }, function()
				self:close()
			end)
		end,
		close = function(self: Modal)
			if not shade.Visible then
				return
			end
			shade.Visible = false
			if openModal == self then
				openModal = nil
			end
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(shade) then
				GuiService.SelectedObject = nil
			end
			if unbindClose then
				unbindClose()
				unbindClose = nil
			end
			if onClose then
				onClose()
			end
		end,
		isOpen = function(_self: Modal): boolean
			return shade.Visible
		end,
	}
	return modal
end

-- Mensaje breve arriba al centro, en la capa "toast". Desaparece solo.
function Components.toast(text: string, seconds: number?)
	local gui = Layout.layer("toast")
	local panel = Components.panel(gui)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0.18, 0)
	Components.label({ text = text, kind = "body", parent = panel, size = UDim2.fromOffset(360, 30) })
	task.delay(seconds or 3, function()
		panel:Destroy()
	end)
end

export type Tabs = {
	frame: Frame,
	pages: { [string]: Frame },
	select: (self: Tabs, name: string) -> (),
	selected: (self: Tabs) -> string,
}

-- Pestañas: una fila de botones y una página por nombre; se ve una página a la vez.
-- Cada página es un Frame vacío donde la pantalla agrega su contenido.
function Components.tabs(parent: Instance, names: { string }, onSelect: ((string) -> ())?): Tabs
	assert(#names > 0, "[Kit] tabs necesita al menos un nombre")
	local root = Instance.new("Frame")
	root.Name = "Tabs"
	root.BackgroundTransparency = 1
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.Size = UDim2.fromOffset(0, 0)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, Style.metric("spacing"))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = root

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.AutomaticSize = Enum.AutomaticSize.XY
	bar.Size = UDim2.fromOffset(0, 0)
	local barList = Instance.new("UIListLayout")
	barList.FillDirection = Enum.FillDirection.Horizontal
	barList.Padding = UDim.new(0, Style.metric("spacing"))
	barList.SortOrder = Enum.SortOrder.LayoutOrder
	barList.Parent = bar
	bar.Parent = root

	local pages: { [string]: Frame } = {}
	local buttons: { [string]: TextButton } = {}
	local current = names[1]
	local tabs: Tabs

	local function show(name: string)
		assert(pages[name], `[Kit] Pestaña desconocida "{name}"`)
		current = name
		for pageName, page in pages do
			page.Visible = pageName == name
		end
		for buttonName, button in buttons do
			local active = buttonName == name
			button.BackgroundColor3 = Style.color(if active then "accent" else "panel")
			button.TextColor3 = Style.color(if active then "textOnAccent" else "text")
		end
	end

	for index, name in names do
		buttons[name] = Components.button({
			text = name,
			variant = "secondary",
			layoutOrder = index,
			parent = bar,
			onActivated = function()
				tabs:select(name)
			end,
		})
		local page = Instance.new("Frame")
		page.Name = "Page_" .. name
		page.BackgroundTransparency = 1
		page.AutomaticSize = Enum.AutomaticSize.XY
		page.Size = UDim2.fromOffset(0, 0)
		page.LayoutOrder = 1
		local pageList = Instance.new("UIListLayout")
		pageList.Padding = UDim.new(0, Style.metric("spacing"))
		pageList.SortOrder = Enum.SortOrder.LayoutOrder
		pageList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		pageList.Parent = page
		page.Parent = root
		pages[name] = page
	end

	tabs = {
		frame = root,
		pages = pages,
		select = function(_self: Tabs, name: string)
			show(name)
			if onSelect then
				onSelect(name)
			end
		end,
		selected = function(_self: Tabs): string
			return current
		end,
	}
	show(current)
	root.Parent = parent
	return tabs
end

-- Grilla con desplazamiento vertical para listas largas (artículos, inventario).
-- Cada hijo es una celda de cellSize; usa Kit.card para su contenido.
function Components.grid(parent: Instance, cellSize: Vector2?, height: number?): ScrollingFrame
	local spacing = Style.metric("spacing")
	local cell = cellSize or Vector2.new(150, 170)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromOffset(cell.X * 3 + spacing * 4, height or cell.Y * 2 + spacing * 3)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = math.max(Style.metric("strokeThickness") * 3, 6)
	scroll.ScrollBarImageColor3 = Style.color("textMuted")
	scroll.Selectable = false
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	layout.CellPadding = UDim2.fromOffset(spacing, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, spacing)
	padding.PaddingBottom = UDim.new(0, spacing)
	padding.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- Celda con fondo de panel para una grilla: el tamaño lo fija la grilla.
function Components.card(parent: Instance?, layoutOrder: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.BackgroundColor3 = Style.color("panel")
	frame.BackgroundTransparency = Style.metric("panelTransparency") * (1 - GuiService.PreferredTransparency)
	frame.LayoutOrder = layoutOrder or 0
	decorate(frame, true)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, Style.metric("spacing"))
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = frame
	frame.Parent = parent
	return frame
end

export type StatusKind = "loading" | "empty" | "error" | "unavailable"

local STATUS_COLOR: { [string]: string } = {
	loading = "textMuted",
	empty = "textMuted",
	error = "danger",
	unavailable = "textMuted",
}

-- Mensaje de estado de una pantalla o sección: cargando, vacío, error o no disponible.
-- El texto dice qué pasa y qué puede hacer el jugador ("Todavía no hay artículos").
function Components.status(parent: Instance, kind: StatusKind, text: string): TextLabel
	local label = Components.label({ text = text, kind = "body", color = STATUS_COLOR[kind], parent = parent })
	label.Name = "Status_" .. kind
	return label
end

-- Llama a callback con el valor actual del atributo y cada vez que cambia.
function Components.bindAttribute(instance: Instance, attribute: string, callback: (any) -> ()): RBXScriptConnection
	task.spawn(callback, instance:GetAttribute(attribute))
	return instance:GetAttributeChangedSignal(attribute):Connect(function()
		callback(instance:GetAttribute(attribute))
	end)
end

return Components
