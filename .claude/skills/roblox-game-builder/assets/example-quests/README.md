# AldeaDeGremios

Juego de referencia de la fábrica para juegos con varios sistemas: cuatro módulos core (`Zones`, `Quests`, `Economy`, `Rewards`) unidos por tres puentes, un módulo `Game` con el contenido y el onboarding, y el progreso guardado con `PlayerData`. Sigue la organización de los proyectos de UEFN (MyIsekai): sistema de misiones independiente, trackers como módulos puente y el catálogo en el módulo principal.

## Abrirlo

- Con Rojo 7.2 o superior, desde esta carpeta: `rojo build -o build/AldeaDeGremios.rbxlx` y abre el archivo en Roblox Studio.
- O en vivo: `rojo serve` y conecta desde el plugin de Rojo en Studio.

## Cómo se juega

Caminá hasta el bosque (noroeste) y la mina (noreste). El panel de arriba a la derecha muestra las misiones activas; cada visita a una zona suma a sus objetivos. Las misiones completas dan monedas y abren la siguiente del gremio. La recompensa diaria llega sola al entrar.

## Cómo está armado

| Capa | Archivos | Qué hace |
| --- | --- | --- |
| Núcleo | `src/shared/` (`Config`, `Tuning`, `Signal`, `DataTypes`, `Levels.json`), `src/server/LevelLoader.luau`, `Telemetry.luau`, `src/server/Data/` | Plantillas de la fábrica, ajustes, niveles y servicio de datos |
| Cores | `src/server/Modules/Zones`, `Quests`, `Economy`, `Rewards` | Un sistema cada uno; ninguno requiere a otro |
| Puentes | `src/server/Bridges/Zones_Quests`, `Quests_Rewards`, `Rewards_Economy` | Escuchan el evento de un core y llaman la API de otro |
| Game | `src/server/Game/init.luau`, `Content.luau` | Catálogo de misiones, recompensas, monedas, arranque y onboarding |
| Entrada | `src/server/Bootstrap.server.luau`, `src/client/Hud.client.luau` | Arranque del servidor y HUD mínimo |

La cadena de una misión: `Zones.entered` → `Zones_Quests` → `Quests.reportObjective` → `Quests.completed` → `Quests_Rewards` → `Rewards.granted` → `Rewards_Economy` → `Economy.add`.

**Para agregar un gremio o una misión:** solo `Game/Content.luau`. No se toca ningún core ni puente y no hace falta migrar datos, porque el perfil guarda las misiones por su id.

**Para agregar un sistema** (por ejemplo, una tienda que gasta monedas): un core nuevo `Modules/Shop` y, si reacciona a otro core, un puente; `Game` lo inicia. Si guarda algo, primero el data architect agrega su sección.

## Ajustes

- `src/shared/Config.luau`: enfriamiento de las zonas y ventana de la racha diaria.
- `src/server/Game/Content.luau`: misiones, recompensas, monedas y recompensa diaria.
- Para ver los eventos de telemetría en el Output, agrega al ModuleScript `ServerScriptService.Server.Telemetry` el atributo booleano `Debug` en `true`.

## Datos guardados

- Qué se guarda y por qué: `design/DATA.md`. El esquema (versión 2, con la migración desde la 1) es `src/server/Data/DataSchema.json`.
- Para probar el guardado real en Studio, publica el place y activa Game Settings → Security → Enable Studio Access to API Services. Sin eso, `PlayerData` guarda en memoria y lo avisa en el Output.
- Barra de comandos de Studio: `require(game.ServerScriptService.Server.Data.DataDebug).dump(game.Players.TuNombre)` muestra el perfil y `.reset(game.Players.TuNombre)` lo vuelve a empezar.

## Estado de verificación

| Nivel | Estado |
| --- | --- |
| Archivos y build | `rojo build` correcto con Rojo 7.7.1 |
| Análisis estático | `check_game.py` sin errores ni advertencias (con `check_modules.py` y `check_data.py`); `luau-lsp` 1.70.1 sin errores |
| Niveles | `validate_levels.py`: 0 errores, 0 advertencias |
| Datos | Servicio de datos probado con Lune; migración de la versión 1 simulada por `check_data.py` |
| Studio | **Pendiente.** Comprobar: misiones que empiezan solas, zonas que suman una vez cada 10 s, recompensa diaria, panel en PC y celular, y salir y volver con acceso a las APIs |
| Servicios publicados | Pendiente: dos servidores con el mismo jugador |
