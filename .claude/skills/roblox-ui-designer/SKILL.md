---
name: roblox-ui-designer
description: Diseñar e implementar la interfaz de juegos de Roblox como un diseñador de UI/HUD senior. Define pantallas, flujos, distribución por plataforma (PC, celular, tableta y consola), estados y accesibilidad en design/UI.md, y la construye en src/client/UI con un kit que respeta las zonas de Roblox (chat, barra superior, controles táctiles), el tema visual, el tamaño táctil y la navegación con gamepad. Úsalo cuando el usuario quiera crear o rehacer el HUD, la tienda, menús o ventanas de su juego, cuando un botón quede tapado por el chat o por los controles del celular, cuando la UI se vea "de programador", o cuando el GDD active design.ui. No decide la paleta ni las fuentes (roblox-art-director) ni la lógica del juego o qué vende la tienda (roblox-game-builder y los módulos de monetización).
metadata:
  version: "1.0.1"
  last_verified: "2026-10-12"
---

# Roblox UI Designer

Diseña y construye la interfaz para que el jugador entienda qué pasa y qué puede hacer, en cualquier dispositivo, sin pelear con la UI de Roblox. El kit se encarga de lo que siempre sale mal (botones debajo del chat, botones chicos en el celular, menús que no se cierran con el gamepad), así el trabajo se concentra en qué mostrar y cuándo.

Una UI "de programador" no es fea por falta de adornos: tiene jerarquía plana, todo el mismo tamaño, botones donde había lugar y estados que nadie diseñó. Diseñar es decidir qué importa más en cada momento.

## Qué produces y qué no

- Lees del `GDD.md`: loop, onboarding, plataformas, monetización y la sección **Estado para la UI** de la Arquitectura (los atributos y remotes que publica el builder). De `design/ART.md` y `Theme.json`, el estilo.
- Escribes, según el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md):
  - `design/UI.md`, con la [plantilla](references/ui-doc-template.md);
  - `src/client/UI/`: la entrada `init.client.luau`, el kit en `Kit/` copiado sin cambios de la [plantilla](assets/templates/src/client/UI/Kit) y las pantallas en `Screens/`.
- No eliges colores ni fuentes: el kit los toma de `Theme.json` con `Style`. Si falta el tema, pídelo al art director con la regla de pendientes.
- No escribes lógica del juego. Una pantalla muestra estado y envía **intenciones** por los remotes del builder; el servidor decide. Si te falta un atributo o un remote, pídeselo al builder: si está instalado y el usuario pidió la UI, agrégalo con sus reglas y documéntalo en "Estado para la UI".
- La tienda muestra lo que define el módulo de monetización y abre sus prompts; no inventa precios ni IDs.
- Activa `design.ui: true` en el frontmatter si el usuario pidió la interfaz, como permite la excepción del contrato.

## Reglas de la plataforma

Verificadas el 12 de octubre de 2026. Detalles en [zonas de pantalla](references/screen-zones.md).

- La ventana de chat está arriba a la izquierda por defecto y su tamaño cambia según el dispositivo. El kit lee su rectángulo real (`ChatWindowConfiguration.AbsolutePosition` y `AbsoluteSize`) y no coloca nada encima.
- La barra superior de Roblox se evita con `ScreenInsets.CoreUISafeInsets` en cada capa.
- En pantallas táctiles, el joystick ocupa la esquina inferior izquierda y el botón de salto la inferior derecha. Las acciones frecuentes van junto al botón de salto.
- La barra de herramientas de Roblox (mochila) ocupa el centro inferior cuando el jugador tiene herramientas; el kit sube el slot `bottom` por encima.
- `UserInputService.PreferredInput` (Touch, Gamepad o KeyboardAndMouse) indica cómo mostrar controles y atajos.
- Roblox no publica un tamaño mínimo táctil. La fábrica usa 44 px, el estándar de la industria (`ui.minTouchTarget` del tema).

## 1. Inventario de pantallas y flujos

Lista cada pantalla con su propósito, cuándo aparece, qué estado muestra y qué acciones ofrece: HUD, tienda, inventario, menús, avisos, fin de ronda. Dibuja los flujos con flechas en texto (`HUD → Tienda → Confirmación → HUD`).

- **Jerarquía:** en cada pantalla, una sola cosa es la más importante (más grande, más contraste, mejor ubicada).
- **El juego primero:** el centro de la pantalla es del mundo. El HUD vive en los bordes y muestra solo lo que cambia decisiones.
- **Estados:** cada pantalla con datos tiene cargando, vacío, error y no disponible (por ejemplo, compra desactivada porque falta el ID), con `Kit.status`.
- **Onboarding:** lo que el jugador nuevo debe ver primero coincide con el funnel del GDD.

## 2. Distribución por plataforma

Para cada elemento decide en qué **slot** del kit va, en PC, celular y consola. Los slots ya esquivan la UI de Roblox:

| Slot | Dónde | Para qué |
| --- | --- | --- |
| `top` | Arriba al centro, sin invadir el chat | Estado principal: ronda, tiempo, nivel |
| `left` | Riel izquierdo, debajo del chat | Botones de menús (tienda, inventario, ayuda) |
| `right` | Riel derecho, centrado | Información secundaria, contadores |
| `bottom` | Abajo al centro, entre los controles táctiles | Barra de acciones o mensajes contextuales |
| `actions` | Junto al botón de salto en táctil; abajo a la derecha en el resto | La acción principal que se repite |

Ventanas en `Kit.modal` y mensajes breves en `Kit.toast`. Lee [patrones](references/patterns.md) para HUD, tiendas, menús y fin de ronda.

## 3. Construir

1. Copia `Kit/` sin cambios a `src/client/UI/Kit/` y crea `src/client/UI/init.client.luau` con la lista de pantallas, como en el [ejemplo](../roblox-game-builder/assets/example-obby/src/client/UI/init.client.luau).
2. Una pantalla por módulo en `Screens/`, con `mount(Kit)`. Usa solo componentes del kit (`Kit.panel`, `Kit.label`, `Kit.button`, `Kit.modal`, `Kit.toast`, `Kit.tabs`, `Kit.grid`, `Kit.card`, `Kit.status`) y coloca los elementos raíz en slots. API completa en [kit](references/kit.md).
3. Lee el estado con `Kit.bindAttribute` y envía intenciones por los remotes del builder. Nunca decidas en el cliente un precio, una recompensa ni un resultado.
4. Cada acción tiene un botón en pantalla y, si corresponde, un atajo (`binding = { keyboard = …, gamepad = … }`). El botón muestra el atajo según la entrada actual.
5. En un juego con varios places, todos comparten `src/client/UI`: `init.client.luau` monta las pantallas de cada place según `Place.current()`, y la tabla de pantallas de `UI.md` dice en qué place va cada una. Si un viaje falla, el jugador recibe el atributo `TravelFailed`: avísalo con `Kit.toast` (ver [patrones](references/patterns.md#viajes-entre-places)).
6. Si el juego ya tenía UI, reemplázala pantalla por pantalla y borra los scripts viejos cuando su pantalla nueva funcione. No cambies su lógica de juego.

## 4. Verificar

```bash
python <skill-dir>/scripts/check_ui.py <Juego>
```

En Windows, usa `python` o `py -3` si `python3` no existe. El script comprueba:

- que cada pantalla de `UI.md` exista y que no haya pantallas sin documentar;
- que el kit esté completo y sin cambios, y que el tema tenga las fuentes y métricas que usa;
- que las pantallas usen slots y componentes del kit, sin `ScreenGui` ni botones sueltos;
- que cada atributo que lee la UI lo escriba el servidor;
- que el GDD documente el "Estado para la UI".

`check_game.py` del builder lo ejecuta cuando el GDD activa `design.ui`. Corrige todos los ERROR.

Después pide al usuario la prueba en Studio de [zonas de pantalla](references/screen-zones.md#verificación-en-studio): emulador de dispositivos (teléfono chico apaisado, tableta, 1080p), gamepad y el modo `DebugZones` del kit, que pinta las zonas reservadas. Un script no ve si algo se lee bien o si un flujo confunde.

## Entrega

Resume en pocas líneas: pantallas y flujos, distribución en cada plataforma, resultado de `check_ui.py`, pedidos abiertos al builder (estado o remotes que faltan) o al art director, y qué revisar en Studio.
