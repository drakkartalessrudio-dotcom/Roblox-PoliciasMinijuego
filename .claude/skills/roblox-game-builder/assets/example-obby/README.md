# ObbyEjemplo

Obby de tres niveles sobre lava. Es el ejemplo de referencia del contrato de la fábrica: niveles como datos, mundo construido por `LevelLoader` y vestido por `EnvironmentLoader`, ajustes leídos con `Tuning`, eventos emitidos con `Telemetry` y progreso guardado con `PlayerData`.

## Abrirlo

- Con Rojo 7.2 o superior, desde esta carpeta: `rojo build -o build/ObbyEjemplo.rbxlx` y abre el archivo en Roblox Studio.
- O en vivo: `rojo serve` y conecta desde el plugin de Rojo en Studio.

Pulsa Play (F5). Para probar con dos jugadores: Test → Clients and Servers.

## Cómo se juega

Salta de plataforma en plataforma hasta la meta azul de cada nivel. Los checkpoints amarillos guardan dónde reapareces, también entre sesiones: al volver, sigues desde el último que alcanzaste. La lava naranja mata.

## Ajustes

- `src/shared/Config.luau`: daño de la lava, enfriamiento entre daños, tiempo y altura de reaparición, y mensaje inicial.
- `src/shared/Levels.json`: niveles y física del personaje. Después de editarlo, valida con `validate_levels.py` del level designer.
- Para ver los eventos de telemetría en el Output, agrega al ModuleScript `ServerScriptService.Server.Telemetry` el atributo booleano `Debug` en `true`.

## Datos guardados

- Qué se guarda y por qué: `design/DATA.md`; el esquema es `src/server/Data/DataSchema.json` (dueño: data architect).
- Para probar el guardado real en Studio, publica el place y activa Game Settings → Security → Enable Studio Access to API Services. Sin eso, `PlayerData` guarda en memoria y lo avisa en el Output.
- Desde la barra de comandos de Studio, con el juego corriendo: `require(game.ServerScriptService.Server.Data.DataDebug).dump(game.Players.TuNombre)` muestra el perfil y `.reset(game.Players.TuNombre)` lo vuelve a empezar.

## Archivos

| Archivo | Qué hace |
| --- | --- |
| `src/server/Bootstrap.server.luau` | Entrada del servidor: datos, física, mundo y pase de arte, y después `Game` |
| `src/server/Game/init.luau` | Composición del juego: configura y arranca el core `Obby` |
| `src/server/Modules/Obby/init.luau` | Core: peligros, checkpoints, metas, leaderstats y telemetría; publica `levelCompleted` y `finished` |
| `src/server/Modules/Obby/ObbyData.luau` | Fachada de la sección `obby` del perfil: nivel y checkpoint actuales, mejor tiempo por nivel |
| `src/server/Data/` | Servicio de datos (`PlayerData` y sus módulos, plantillas de roblox-data-architect), `DataSchema.json` y `Migrations.luau` |
| `src/shared/DataTypes.luau` | Tipos del perfil, generados con `gen_types.py` |
| `src/server/LevelLoader.luau` | Construye los niveles desde `Levels.json` (plantilla del builder) |
| `src/server/EnvironmentLoader.luau` | Aplica el pase de arte de `Environment.json` sin cambiar lo jugable (plantilla del builder) |
| `src/server/Telemetry.luau` | Fachada de eventos (plantilla del builder) |
| `src/shared/Signal.luau` | Eventos entre módulos (plantilla del builder) |
| `src/shared/Config.luau` | Valores ajustables |
| `src/shared/Tuning.luau` | Lectura de valores ajustables (plantilla del builder) |
| `src/shared/Levels.json` | Niveles (dueño: level designer) |
| `src/shared/Theme.json` | Tema visual: paleta, fuentes, materiales e iluminación (dueño: art director) |
| `src/shared/Style.luau` | Lectura del tema e iluminación (plantilla del builder) |
| `src/shared/Environment.json` | Pase de arte: aspecto de las piezas, props, terreno, luces y cielo (dueño: environment artist) |
| `src/client/UI/` | Interfaz: kit de la fábrica (`Kit/`, sin cambios) y pantallas `Hud` y `Help` (dueño: UI designer) |

## Pendiente (no construido)

Tabla de tiempos, más niveles y cosméticos.

## Estado de verificación

| Nivel | Estado |
| --- | --- |
| Archivos y build | `rojo build` correcto con Rojo 7.7.1 |
| Análisis estático | `check_game.py` sin errores ni advertencias (incluye arte, interfaz, pase de arte, módulos y datos); `luau-lsp` 1.70.1 sin errores |
| Niveles | `validate_levels.py`: 0 errores, 0 advertencias |
| Studio | **Pendiente.** Comprobar: aparición, saltos, reaparición en checkpoint, plataforma móvil que arrastra, barra giratoria que daña, meta → siguiente nivel, HUD, decoración (ver `design/ENVIRONMENT.md`), dos jugadores, y salir y volver al último checkpoint con acceso a las APIs |
| Datos y monetización | Servicio de datos probado con Lune (bloqueo, carga fallida, migraciones, compras); en Studio y en una experiencia publicada, pendiente. Sin monetización |
| Servicios publicados | No aplica |
