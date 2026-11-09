# Interfaz de ObbyEjemplo

Fuente: `GDD.md` (loop, onboarding, plataformas y Estado para la UI) y `design/ART.md` (estilo). Código: `src/client/UI/` con el kit de la fábrica sin cambios. Verificado con `check_ui.py` el 2026-10-12: 0 errores.

## Principios

1. **El recorrido primero.** La pantalla del obby es el mundo: la UI ocupa el borde superior y un botón lateral, nada en el centro.
2. **Nada debajo de la UI de Roblox.** Todo se coloca en slots del kit, que esquivan el chat, la barra superior y los controles táctiles.
3. **Cada control dice cómo se usa.** Los botones muestran su atajo según la entrada: "(H)" con teclado, "(X)" con gamepad y nada en táctil.

## Pantallas

| Pantalla | Módulo | Dónde | Qué muestra | Estado que usa |
| --- | --- | --- | --- | --- |
| HUD | `Screens/Hud.luau` | Slot `top`; avisos en la capa `toast` | Nivel y checkpoint, mensaje inicial y aviso de fin | `Level`, `LevelCount`, `Checkpoint`, `Finished` |
| Ayuda | `Screens/Help.luau` | Botón en el slot `left`; ventana en la capa `modal` | Controles de la entrada actual | — |

## Distribución por plataforma

| Elemento | PC (teclado y ratón) | Celular y tableta | Consola (gamepad) |
| --- | --- | --- | --- |
| Estado del nivel | Arriba al centro | Arriba al centro, achicado para no tocar el chat | Arriba al centro, escala 1,25 |
| Botón Controles | Riel izquierdo, debajo del chat; atajo H | Riel izquierdo, debajo del chat; botón de 44 px o más | Riel izquierdo; atajo X; se selecciona con el D-pad |
| Ventana Controles | Centro; se cierra con el botón Cerrar o H | Centro; botón Cerrar | Centro; se cierra con B; el foco va a Cerrar |
| Avisos | Arriba, debajo del estado | Igual | Igual |

Zonas que no se usan: la esquina superior izquierda (chat), la barra superior y, en táctil, las esquinas inferiores (joystick y salto).

## Estados

| Pantalla | Cargando | Normal | Fin |
| --- | --- | --- | --- |
| HUD | "Cargando…" hasta que el servidor publica `Level` y `LevelCount` | "Nivel N/M · Checkpoint K" | "¡Completaste el obby!" y un aviso de 5 s |

## Accesibilidad

Texto escalado según el tamaño de texto preferido del jugador. Sin animaciones de botones si pidió movimiento reducido. Contrastes del tema verificados por el art director (4,5:1 en texto). Toda acción tiene botón en pantalla, no solo atajo.

## Verificación en Studio

1. Con el atributo `DebugZones` en `true` en el ModuleScript `Kit.Layout`, las zonas reservadas se pintan: ningún elemento propio debe quedar encima.
2. Emulador de dispositivos (Test → Device): un teléfono chico apaisado, una tableta y 1080p. En cada uno: el estado se lee completo, el botón Controles no toca el chat y se puede tocar.
3. Con gamepad: el botón X abre la ventana, el foco queda en Cerrar y B la cierra.
