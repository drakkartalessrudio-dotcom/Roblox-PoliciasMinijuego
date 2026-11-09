# Plantilla de `design/UI.md`

Copia esta estructura en `<Juego>/design/UI.md`. Ejemplo completo: [UI.md del obby](../assets/example/UI.md). `check_ui.py` lee los módulos de la tabla de pantallas (`Screens/<Nombre>.luau`).

```markdown
# Interfaz de <Juego>

Fuente: `GDD.md` (loop, onboarding, plataformas y Estado para la UI) y `design/ART.md` (estilo). Código: `src/client/UI/` con el kit de la fábrica sin cambios. Verificado con `check_ui.py` el <fecha>: <resultado>.

## Principios

1. **<Regla corta>.** <Qué decide.>

## Pantallas

| Pantalla | Módulo | Dónde | Qué muestra | Estado que usa |
| --- | --- | --- | --- | --- |
| HUD | `Screens/Hud.luau` | Slot `top` | <...> | <atributos o remotes> |

## Flujos

<Pantalla → pantalla, con qué acción, en texto.>

## Distribución por plataforma

| Elemento | PC (teclado y ratón) | Celular y tableta | Consola (gamepad) |
| --- | --- | --- | --- |

Zonas que no se usan: <chat, barra superior, controles táctiles y cualquier otra>.

## Estados

| Pantalla | Cargando | Vacío | Error o no disponible | Normal |
| --- | --- | --- | --- | --- |

## Accesibilidad

<Tamaño de texto, movimiento reducido, contraste, acciones sin depender de un solo dispositivo.>

## Verificación en Studio

<Zonas con DebugZones, dispositivos del emulador, gamepad.>

## Pendientes

<Pedidos al builder (estado o remotes que faltan), al art director o a monetización, con el formato del GDD.>
```
