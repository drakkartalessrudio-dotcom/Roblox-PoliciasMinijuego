# Zonas de pantalla

Qué espacio ocupa Roblox en cada plataforma y cómo lo evita el kit. Verificado el 12 de octubre de 2026 en la documentación de Roblox ([contenedores en pantalla](https://create.roblox.com/docs/ui/on-screen-containers), [ventana de chat](https://create.roblox.com/docs/chat/chat-window), [ChatWindowConfiguration](https://create.roblox.com/docs/reference/engine/classes/ChatWindowConfiguration), [ScreenInsets](https://create.roblox.com/docs/reference/engine/enums/ScreenInsets), [UserInputService](https://create.roblox.com/docs/reference/engine/classes/UserInputService)) y en las definiciones de tipos de Roblox.

## Zonas reservadas

| Zona | Dónde | Cómo la evita el kit |
| --- | --- | --- |
| Barra superior (menú de Roblox, chat, lista de jugadores) | Franja superior | Cada capa usa `ScreenInsets.CoreUISafeInsets`, que deja los elementos dentro del área segura, lejos de la barra y de los recortes de la pantalla |
| Ventana de chat y barra de entrada | Arriba a la izquierda por defecto (`HorizontalAlignment` Left, `VerticalAlignment` Top); el tamaño depende del dispositivo | Lee `TextChatService.ChatWindowConfiguration.AbsolutePosition` y `AbsoluteSize` (y la barra de entrada) y ubica el riel izquierdo debajo y el slot superior sin invadirla. Se recalcula si el chat cambia |
| Joystick táctil | Esquina inferior izquierda | En táctil (`PreferredInput` Touch y `GuiService.TouchControlsEnabled`), reserva los controles de `PlayerGui.TouchGui`; si todavía no existen, reserva las esquinas inferiores |
| Botón de salto | Esquina inferior derecha | El slot `actions` se ubica a su izquierda, como recomienda Roblox para botones de acción |
| Recortes de pantalla (notch) | Bordes del teléfono | `CoreUISafeInsets` |
| Barra de herramientas (mochila) | Abajo al centro, cuando `CoreGuiType.Backpack` está activado y el jugador tiene herramientas | Sube el slot `bottom` por encima. Roblox no expone su rectángulo: el kit reserva 90 px, una estimación con margen que se revisa con `DebugZones` |
| Lista de jugadores | Arriba a la derecha, debajo de la barra superior; crece con la cantidad de jugadores | El riel derecho está centrado en vertical. Con servidores grandes, revisa que no se tapen en Studio con varios clientes |

Mover el chat (`ChatWindowConfiguration.HorizontalAlignment` y `VerticalAlignment`) es posible, pero confunde a los jugadores que lo esperan en su lugar. Hazlo solo si el diseño lo justifica y documéntalo en `UI.md`. El kit se adapta solo a la nueva posición.

## Escala y texto

- Escala por capa (`UIScale`): según el tamaño de la pantalla respecto de 1280 × 720, entre 0,85 y 1,4. En táctil nunca baja de 1, para conservar los 44 px de los botones. En consola (`GuiService:IsTenFootInterface()`) se multiplica por 1,25: se mira desde lejos.
- El texto respeta el tamaño preferido del jugador (`GuiService.PreferredTextSize`: Medium, Large, Larger o Largest).
- Con `GuiService.ReducedMotionEnabled`, los botones no se animan.
- `GuiService.PreferredTransparency` reduce la transparencia de los paneles cuando el jugador la prefiere baja.

## Entrada

`UserInputService.PreferredInput` vale Touch, Gamepad o KeyboardAndMouse y cambia cuando el jugador conecta o usa otro dispositivo. El kit lo escucha (`Kit.Input.onChanged`) para mostrar atajos: "(B)" con teclado, "(Y)" con gamepad y nada en táctil. Los atajos se registran con `ContextActionService` sin botones táctiles extra: en táctil se toca el botón del kit.

## Verificación en Studio

1. En el ModuleScript `Kit.Layout`, agrega el atributo booleano `DebugZones` en `true`: las zonas reservadas se pintan con el color `danger` del tema. Ningún elemento propio debe quedar encima.
2. Test → Device (emulador): un teléfono chico apaisado, una tableta y una pantalla de 1080p. En cada uno, todo se lee completo, nada toca el chat ni los controles, y los botones se pueden tocar.
3. Con un gamepad: los menús se abren con su atajo, el foco cae en un botón y B cierra las ventanas.
4. Cambia el tamaño de texto preferido y el movimiento reducido en la configuración de Roblox y comprueba que la UI sigue entrando.

Si algo del kit no coincide con lo observado (por ejemplo, la posición real del chat en una plataforma), anótalo en `UI.md` y pídelo como corrección del kit: el arreglo va en la plantilla, para todos los juegos.
