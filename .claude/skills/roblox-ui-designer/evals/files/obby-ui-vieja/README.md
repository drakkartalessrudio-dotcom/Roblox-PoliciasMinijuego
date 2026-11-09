# ObbyEjemplo

Obby de tres niveles sobre lava. Es el ejemplo de referencia del contrato de la fábrica: niveles como datos, mundo construido por `LevelLoader`, ajustes leídos con `Tuning` y eventos emitidos con `Telemetry`.

## Abrirlo

- Con Rojo 7.2 o superior, desde esta carpeta: `rojo build -o build/ObbyEjemplo.rbxlx` y abre el archivo en Roblox Studio.
- O en vivo: `rojo serve` y conecta desde el plugin de Rojo en Studio.

Pulsa Play (F5). Para probar con dos jugadores: Test → Clients and Servers.

## Cómo se juega

Salta de plataforma en plataforma hasta la meta azul de cada nivel. Los checkpoints amarillos guardan dónde reapareces. La lava naranja mata.

## Ajustes

- `src/shared/Config.luau`: daño de la lava, enfriamiento entre daños, tiempo y altura de reaparición, y mensaje inicial.
- `src/shared/Levels.json`: niveles y física del personaje. Después de editarlo, valida con `validate_levels.py` del level designer.
- Para ver los eventos de telemetría en el Output, agrega al ModuleScript `ServerScriptService.Server.Telemetry` el atributo booleano `Debug` en `true`.

## Archivos

| Archivo | Qué hace |
| --- | --- |
| `src/server/Bootstrap.server.luau` | Entrada del servidor: física, mundo y reglas, en ese orden |
| `src/server/LevelLoader.luau` | Construye los niveles desde `Levels.json` (plantilla del builder) |
| `src/server/ObbyService.luau` | Peligros, checkpoints, metas, leaderstats y telemetría |
| `src/server/Telemetry.luau` | Fachada de eventos (plantilla del builder) |
| `src/shared/Config.luau` | Valores ajustables |
| `src/shared/Tuning.luau` | Lectura de valores ajustables (plantilla del builder) |
| `src/shared/Levels.json` | Niveles (dueño: level designer) |
| `src/shared/Theme.json` | Tema visual: paleta, fuentes, materiales e iluminación (dueño: art director) |
| `src/shared/Style.luau` | Lectura del tema e iluminación (plantilla del builder) |
| `src/client/HUD.client.luau` | Nivel, checkpoint, mensaje inicial y botón de tienda |

## Pendiente (no construido)

Guardar progreso, tabla de tiempos, más niveles y cosméticos.

## Estado de verificación

| Nivel | Estado |
| --- | --- |
| Archivos y build | Estructura y JSON revisados con `check_game.py`. `rojo build` pendiente: no había Rojo instalado al escribirlo |
| Análisis estático | `check_game.py` sin errores. Sin `luau-analyze` ni `luau-lsp` disponibles |
| Niveles | `validate_levels.py`: 0 errores, 0 advertencias |
| Studio | **Pendiente.** Comprobar: aparición, saltos, reaparición en checkpoint, plataforma móvil que arrastra, barra giratoria que daña, meta → siguiente nivel, HUD y dos jugadores |
| Datos y monetización | No aplica |
| Servicios publicados | No aplica |
