# API del kit de UI

El kit vive en `src/client/UI/Kit/` y se copia sin cambios de [la plantilla](../assets/templates/src/client/UI/Kit). Requiere `src/shared/Style.luau` y `src/shared/Theme.json` con las fuentes `heading`, `body`, `label` y `number` y todas las métricas de `ui` (`check_ui.py` lo comprueba). Las pantallas lo reciben en `mount(Kit)`.

## Inicio y distribución

| Función | Qué hace |
| --- | --- |
| `Kit.start()` | Crea las capas y los slots y conecta los recálculos. Se llama una vez, en `init.client.luau` |
| `Kit.slot(nombre)` | Frame del slot `"top"`, `"left"`, `"right"`, `"bottom"` o `"actions"`. Los hijos se apilan con el espaciado del tema |
| `Kit.layer(nombre)` | `ScreenGui` de la capa `"hud"`, `"menu"`, `"modal"` o `"toast"` (orden de dibujo creciente) |
| `Kit.refresh()` | Recalcula escala y slots. Normalmente no hace falta: se llama sola |
| `Kit.scale()` | Escala actual de la UI |
| `Kit.chatRect()` | Rectángulo del chat en pantalla, o `nil` |
| `Kit.touchRects()` | Rectángulos de los controles táctiles (vacío fuera de táctil) |

## Componentes

| Función | Qué devuelve |
| --- | --- |
| `Kit.panel(parent?, direction?)` | Frame con fondo `panel`, esquinas, borde y espaciado del tema; los hijos se apilan |
| `Kit.label({ text?, kind?, color?, size?, parent? })` | TextLabel. `kind`: `"heading"`, `"body"`, `"label"` o `"number"` (fuente del tema). `color`: un rol del tema (por defecto `"text"`) |
| `Kit.button({ text, onActivated, variant?, binding?, parent?, layoutOrder? })` | TextButton de 44 px o más. `variant`: `"primary"` (acento), `"secondary"` (panel) o `"danger"`. `binding = { keyboard = Enum.KeyCode.B, gamepad = Enum.KeyCode.ButtonY }` registra el atajo y lo muestra en el texto |
| `Kit.modal(título, onClose?)` | Ventana centrada con fondo que bloquea clics, cabecera fija con título y botón X de cerrar (también B en gamepad) y cuerpo con desplazamiento limitado al alto de la pantalla, para que el botón de cerrar nunca quede fuera en celulares bajos. Devuelve `{ frame, content, open, close, isOpen }`: agrega el contenido en `content` |
| `Kit.toast(texto, segundos?)` | Mensaje breve arriba al centro |
| `Kit.tabs(parent, nombres, onSelect?)` | Fila de pestañas con una página por nombre. Devuelve `{ frame, pages, select, selected }`: agrega el contenido en `pages[nombre]` |
| `Kit.grid(parent, cellSize?, height?)` | `ScrollingFrame` con grilla y desplazamiento vertical para listas largas (artículos, inventario) |
| `Kit.card(parent?, layoutOrder?)` | Celda con fondo de panel para una grilla; el tamaño lo fija la grilla |
| `Kit.status(parent, tipo, texto)` | Mensaje de estado: `"loading"`, `"empty"`, `"error"` o `"unavailable"`, con el color del tema |
| `Kit.bindAttribute(instancia, atributo, callback)` | Llama a `callback(valor)` ahora y en cada cambio del atributo |

## Entrada

| Función | Qué hace |
| --- | --- |
| `Kit.Input.preferred()` | `Enum.PreferredInput` actual |
| `Kit.Input.onChanged(callback)` | Llama a `callback(preferido)` ahora y en cada cambio. Devuelve la función para dejar de escuchar |
| `Kit.Input.hint(binding)` | Texto del atajo para la entrada actual (`"B"`, `"Y"` o `""`) |
| `Kit.Input.bindAction(nombre, binding, callback)` | Registra un atajo sin botón táctil. Devuelve la función para quitarlo |

## Ejemplo

```lua
local Shop = {}

function Shop.mount(Kit: any)
	local modal = Kit.modal("Tienda")
	local tabs = Kit.tabs(modal.content, { "Estelas", "Efectos" })
	Kit.status(tabs.pages.Efectos, "empty", "Todavía no hay efectos a la venta")
	local grid = Kit.grid(tabs.pages.Estelas)
	for index, item in { "Fuego", "Hielo" } do
		local card = Kit.card(grid, index)
		Kit.label({ text = item, kind = "label", parent = card, size = UDim2.new(1, 0, 0, 28) })
	end
	Kit.button({
		text = "Tienda",
		binding = { keyboard = Enum.KeyCode.B, gamepad = Enum.KeyCode.ButtonY },
		parent = Kit.slot("left"),
		onActivated = function()
			modal:open()
		end,
	})
end

return Shop
```

## Lo que el kit no hace

- No define estilo: todo color, fuente y medida sale del tema.
- No guarda estado del juego: lo lee de atributos o remotes del builder.
- No anima pantallas completas ni trae tooltips: en táctil no hay hover, así que la descripción de un artículo va en su celda o en un panel de detalle.
