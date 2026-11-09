# Puntos de enganche del builder

Módulos con API fija, que forman el núcleo del juego, y una tabla del GDD conectan el juego con los demás skills de la fábrica. Gracias a ellos, el level designer, el art director, el environment artist, el UI designer, las analíticas y LiveOps se agregan sin reescribir la lógica del juego.

## Archivos

| Archivo del juego | Plantilla | Cuándo |
| --- | --- | --- |
| `src/shared/Tuning.luau` | [Tuning.luau](../assets/templates/src/shared/Tuning.luau) | Siempre |
| `src/server/Telemetry.luau` | [Telemetry.luau](../assets/templates/src/server/Telemetry.luau) | Siempre |
| `src/server/LevelLoader.luau` | [LevelLoader.luau](../assets/templates/src/server/LevelLoader.luau) | Cuando existe `src/shared/Levels.json` |
| `src/shared/Style.luau` | [Style.luau](../assets/templates/src/shared/Style.luau) | Cuando existe `src/shared/Theme.json` |
| `src/server/EnvironmentLoader.luau` | [EnvironmentLoader.luau](../assets/templates/src/server/EnvironmentLoader.luau) | Cuando existe `src/shared/Environment.json` |
| `src/shared/Place.luau`, `src/server/Travel.luau` | [Place.luau](../assets/templates/src/shared/Place.luau), [Travel.luau](../assets/templates/src/server/Travel.luau) | Cuando el GDD declara varios places ([varios places](multi-place.md)) |
| `src/shared/Signal.luau` | [Signal.luau](../assets/templates/src/shared/Signal.luau) | Cuando un módulo core publica eventos ([arquitectura de módulos](module-architecture.md)) |
| `src/server/Data/PlayerData.luau`, `Session.luau`, `Profile.luau`, `Store.luau`, `DataDebug.luau` | [plantillas de roblox-data-architect](../../roblox-data-architect/assets/templates/src/server/Data) | Cuando existe `src/server/Data/DataSchema.json` (el juego guarda datos); `Signal.luau` también |

Cópialos tal cual. Si el juego necesita más comportamiento, agrégalo en otros módulos: así las plantillas se pueden actualizar copiándolas de nuevo. `check_game.py` verifica que estén y que conserven su API.

## Tuning: valores ajustables

- **Todo valor ajustable va en `Config.luau`** y se lee con `Tuning.get`: daño, tiempos, precios en moneda del juego, multiplicadores, textos de la UI. Config es una tabla con secciones en PascalCase y un comentario por valor (unidad y efecto). Sus valores iniciales salen de la sección "Parámetros ajustables" del GDD; los parámetros técnicos que agregue el builder también se anotan ahí.
- Lee con `Tuning.get("Seccion.Valor")` en el momento de usar el valor. No guardes al iniciar valores que LiveOps podría cambiar, como precios, multiplicadores o tiempos de ronda. No modifiques Config en ejecución.
- Una ruta inexistente falla en el acto; `check_game.py` también compara cada ruta literal con Config.
- `src/server/ServerConfig.luau` guarda solo lo que no debe llegar al cliente, como límites antitrampa o tablas internas de premios. Se lee directamente y LiveOps no lo ajusta.
- Con niveles, la física del personaje vive en `Levels.json`, no en Config. Sin niveles, ponla en `Config.Physics` (`WalkSpeed`, `JumpHeight`, `Gravity`) y aplícala en Bootstrap y en `CharacterAdded`, igual que hace `LevelLoader`.

**Contrato para LiveOps** ([roblox-liveops](../../roblox-liveops/SKILL.md)): el módulo `src/shared/LiveConfig.luau` expone `getOverride(path) -> (activo: boolean, valor: any)` y devuelve el mismo override en el servidor y en el cliente, porque `Tuning` también se usa en la UI. Combina los experience configs de Roblox con los eventos programados de `src/server/LiveSchema.json`. `Tuning` usa el override solo si es del mismo tipo que el valor de Config. Para que un cambio en vivo se note, lee los ajustes con `Tuning.get` al usarlos; si el juego necesita aplicar cambios solo entre rondas, el esquema usa `"refresh": "manual"` y el juego llama a `LiveConfig.refresh()` en ese momento.

## Telemetry: eventos del juego

| Función | Cuándo llamarla | Nombres |
| --- | --- | --- |
| `onboarding(player, paso, nombre)` | Al ocurrir cada paso del funnel de onboarding; el primero cuando el servidor registra al jugador | Pasos de la sección Onboarding del GDD |
| `progressionStart`, `progressionComplete`, `progressionFail` `(player, camino, nivel, nombreNivel?)` | Al empezar, completar o fallar un nivel, oleada, ronda o hito | Camino de progresión de los KPIs (por ejemplo `Obby`) y número de nivel u oleada; con niveles, el orden de `Levels.json` |
| `economy(player, "source" o "sink", moneda, cantidad, saldoFinal, tipo, sku?)` | Después de aplicar en el servidor un cambio de moneda; no si falló | Moneda del GDD; `tipo` estable, como `Gameplay`, `Shop`, `IAP`, `Onboarding` o `TimedReward` |
| `funnel(player, funnel, paso, nombre, sesión?)` | Pasos de otros embudos del GDD (tienda, tutorial opcional) | Funnel del GDD |
| `custom(player, nombre, valor?, campos?)` | Otros eventos del GDD (muertes, partidas terminadas) | `snake_case` estable |

- Solo el servidor emite eventos. Si importa una acción de UI, el cliente la envía por un RemoteEvent validado y el servidor llama a `Telemetry`.
- Los nombres salen del GDD y no cambian entre versiones; si cambian, la comparación de datos se rompe. Si el GDD no los define, completa el GDD antes de programar (ver el paso 1 del builder).
- `onboarding` se envía una vez por paso, jugador y sesión. Las demás funciones no deduplican: llámalas una vez por hecho real, nunca por frame.
- El servicio de recibos del módulo de monetización, después de entregar un producto que da moneda, registra `economy(player, "source", moneda, cantidad, saldo, "IAP", sku)`.
- Para ver los eventos en Studio, agrega al ModuleScript `Telemetry` el atributo booleano `Debug` en `true`.

**Contrato para analíticas** ([roblox-analytics-dev](../../roblox-analytics-dev/SKILL.md)): el módulo `src/server/Analytics.luau` expone funciones con los mismos nombres y argumentos, y solo envía los nombres declarados en `src/server/AnalyticsSchema.json`. `Telemetry` reenvía cada llamada válida dentro de `pcall`; sin ese módulo, no hace nada. Si agregas un nombre nuevo (un paso, un evento propio, una moneda), pide al skill de analíticas que lo declare: si no, `Analytics` lo descarta.

## LevelLoader: el mundo desde `Levels.json`

```lua
local Levels = require(ReplicatedStorage.Shared.Levels)
LevelLoader.applyPhysics(Levels.physics) -- antes de que aparezcan personajes
local built = LevelLoader.build(Levels) -- antes de conectar los sistemas
-- en CharacterAdded: LevelLoader.applyToHumanoid(humanoid, Levels.physics)
```

`built.levels[i]` tiene `index`, `id`, `name`, `data` (el nivel del JSON), `folder`, `start`, `pieces[id]`, `byKind[kind]` y `checkpoints` ordenados por `Order`; `built.byId[id]` da el mismo nivel por id.

`LevelLoader.build(Levels, nil, { only = ids })` construye solo esos niveles; `index` sigue el orden de `Levels.json` entre los construidos. Sirve para dos casos: en un juego con varios places, cada place construye `Place.levels(Levels)`; en un juego de rondas, el servidor construye el mapa de cada ronda a demanda y lo descarga con `built.folder:Destroy()` (y `dressed.folder:Destroy()` si tiene pase de arte; el terreno queda). `LevelLoader.standCFrame(pieza, altura)` devuelve dónde colocar a un personaje sobre una pieza.

| `kind` | Instancia | Etiqueta | Atributos además de `PieceId`, `LevelId` y `LevelIndex` |
| --- | --- | --- | --- |
| `spawn` | SpawnLocation neutral, sin ForceField; `Enabled` según el dato | `LevelSpawn` | — |
| `platform` | Part | `LevelPlatform` | — |
| `checkpoint` | Part | `Checkpoint` | `Order` |
| `goal` | Part | `Goal` | — |
| `truss` | TrussPart | `LevelTruss` | — |
| `wall` | Part | `LevelWall` | — |
| `hazard` | Part | `Hazard` | `Damage`, si el dato lo define |
| `collectible` | Part sin colisión | `Collectible` | `Value` |
| `zone` | Part invisible, sin colisión ni consultas | `Zone` | `ZoneName` |
| `prop` | Part | `LevelProp` | — |

`LevelLoader` no implementa reglas. El juego implementa la semántica de cada tipo:

- **spawn:** Roblox hace aparecer a los jugadores en los `spawn` habilitados. Los deshabilitados son puntos que usa la lógica del juego, por ejemplo al empezar una ronda.
- **checkpoint:** al tocarlo, valida que el jugador esté vivo, en ese nivel y avanzando (`Order` mayor que el actual), y guarda el punto de reaparición. Para reaparecer ahí, recuerda que Roblox coloca al personaje en un SpawnLocation **después** de emparentarlo a Workspace: durante unos frames, si el personaje está lejos de su punto de reaparición, muévelo otra vez, como `placeCharacter` del ejemplo. Moverlo una sola vez puede quedar pisado por el spawn.
- **goal:** valida el nivel actual, registra `progressionComplete` y lleva al jugador al `start` del siguiente nivel o termina el recorrido.
- **hazard:** aplica `TakeDamage` con `Damage` o el daño por defecto de Config, con enfriamiento por jugador y pieza, solo a Humanoids vivos. Por convención de la fábrica, un peligro sin `Damage` mata: el daño por defecto de Config es al menos la vida máxima del personaje.
- **collectible:** el servidor valida que la tocó un jugador vivo y que todavía puede tomarla, otorga `Value` y registra `economy`. El GDD decide si es **compartida** (la toma el primero, se oculta para todos y reaparece después) o **por jugador** (cada jugador la toma una vez; el servidor registra quién la tomó y la pieza sigue visible para los demás).
- **zone:** su significado lo define `LEVELS.md` mediante `ZoneName` (lobby, parcela, área de monedas). Consulta quién está dentro desde el servidor, por ejemplo con `Workspace:GetPartBoundsInBox`; no confíes en el cliente.
- **piezas con `motion`:** ya se mueven con física y el servidor es dueño de su simulación. No las ancles ni las muevas por código.

No edites `Levels.json`: su dueño es el level designer. Si un nivel falla en Studio, resuélvelo con la regla de pendientes del [contrato](factory-contract.md#pendientes-entre-skills).

Sin `Levels.json`, construye el mundo en un módulo propio, por ejemplo `WorldBuilder.luau`.

## Style: el tema visual

Cuando el art director escribió `src/shared/Theme.json`, todo lo visual que hace el builder sale del tema:

- UI: `Style.color("panel")`, `Style.color("text")`, `Style.font("heading")`, `Style.metric("cornerRadius")`; nunca `Color3.fromRGB` ni `Enum.Font` escritos en el código del cliente. `check_game.py` los cuenta.
- Mundo que construye el builder (si no lo hace el level designer): `Style.color("surface")`, `Style.material("hazard")`…
- Iluminación: sin `Environment.json`, `Style.applyLighting("default")` en el servidor, al inicio; con él, la aplica `EnvironmentLoader` con el preset que eligió el environment artist. `Theme.lighting.style` y `prioritizeQuality` se copian a `default.project.json` en `Lighting.$properties` (`LightingStyle`, `PrioritizeLightingQuality`): Roblox no permite cambiarlos por script.

Un rol que no está en el tema falla en el acto, igual que una ruta de `Tuning`. Si falta un rol, pídeselo al art director con la regla de pendientes.

## EnvironmentLoader: el pase de arte

Cuando el [environment artist](../../roblox-environment-artist/SKILL.md) escribió `src/shared/Environment.json`:

```lua
local Environment = require(ReplicatedStorage.Shared.Environment)
local built = LevelLoader.build(Levels)
EnvironmentLoader.apply(built, Environment) -- antes de iniciar los sistemas del juego
```

`apply` aplica el preset de iluminación del tema, las nubes y los colores del terreno; cambia color, material, variante de material y texturas de las piezas por tipo, conservando sus propiedades físicas originales; agrega adornos sin colisión (bordes, guardas, baldosas, zócalos, cornisas, pilastras, rocas, pilares y cimientos), props armados con Parts, modelos del usuario, terreno, luces y sonidos en `Workspace.Environment`, y devuelve `{ folder, props, parts, lights }`. Nunca cambia posición, tamaño, forma, transparencia ni colisión de una pieza de nivel, y los peligros, checkpoints, metas y coleccionables conservan el color de su rol.

Si `Environment.json` declara assets del usuario (`assets`), mapea sus carpetas en `default.project.json`, dentro de los servicios que ya tenga el árbol:

```json
"ServerStorage": { "EnvironmentAssets": { "$path": "assets/models" } },
"MaterialService": { "$path": "assets/materials" }
```

El loader clona los modelos de `ServerStorage.EnvironmentAssets`, les borra los scripts y los encaja en la caja de cada prop; las variantes de material se buscan por nombre en `MaterialService`. Las texturas, sonidos y animaciones llegan como IDs declarados en `assets` y en la sección Assets y servicios del GDD: el código no tiene IDs escritos. `check_environment.py` avisa si falta un mapeo.

Tus sistemas siguen usando las piezas de `built` y sus etiquetas como siempre. No cambies el aspecto de las piezas en tu código: si algo debe verse distinto, pídeselo al environment artist.

## PlayerData: el servicio de datos

Con `design.data`, el [data architect](../../roblox-data-architect/SKILL.md) escribe `src/server/Data/DataSchema.json`, `Migrations.luau` y `src/shared/DataTypes.luau`; tú copias sin cambios las plantillas del servicio y escribes, dentro de cada core con datos, la **fachada** de su sección (`Modules/<Core>/<Core>Data.luau`). Solo la fachada llama a `PlayerData.section(player, "<sección>")`; el resto del core y los demás cores usan las funciones de la fachada o la API del core. `check_data.py` lo comprueba.

```lua
-- Bootstrap, antes de construir el mundo y de Game.start:
PlayerData.start()

-- Modules/Quests/QuestData.luau
local data: DataTypes.Quests? = PlayerData.section(player, "quests"):get() -- copia de solo lectura; nil si no está listo
local ok = PlayerData.section(player, "quests"):update(function(draft: DataTypes.Quests)
	draft.completed[questId] = os.time()
end) -- false si no está listo o si el cambio rompe el esquema (tipos, límites)
```

| Función | Para qué |
| --- | --- |
| `PlayerData.start()` | Una vez, en `Bootstrap`. Carga a los jugadores presentes y a los que entran |
| `PlayerData.waitUntilReady(player, timeout?)` | Espera la carga; `true` si quedó lista. Úsalo antes de leer el progreso de un jugador que acaba de entrar |
| `PlayerData.status(player)` | `loading`, `ready` o `unavailable` y el motivo (`locked`, `error`, `newer`, `lost`) |
| `PlayerData.section(player, nombre)` | `get()` y `update(fn)` de una sección (solo en la fachada de su core) |
| `PlayerData.changed(nombre)` | `Signal` (player, copia) cuando cambia una sección |
| `PlayerData.onLoaded`, `PlayerData.onReleased` | `Signal` (player) |
| `PlayerData.save(player)` | Guarda ya si hay cambios: antes de un viaje con `Travel.onBeforeTravel` |
| `PlayerData.grantPurchase(player, purchaseId, grant)` | Para `ProcessReceipt`: ver [Developer Products](../../roblox-monetization-developer-products/SKILL.md) |

- Al entrar, el jugador juega con el estado inicial mientras su perfil carga; cuando carga, el core lo lleva a donde quedó. **No escribas antes de leer**: una escritura con el estado inicial pisaría el progreso guardado en cuanto el perfil esté listo. El [obby de ejemplo](../assets/example-obby/src/server/Modules/Obby/init.luau) lo resuelve con `enterLevel(..., save = false)` al conectarse y `restore` al cargar.
- Si la carga falla, `update` devuelve `false` y nada se guarda: el jugador sigue jugando. El atributo `DataStatus` del jugador lo dice a la UI.
- `PlayerData` guarda cada 180 segundos si hubo cambios, al salir y al cerrar el servidor. No guardes por cada click: cambia la sección y deja que el servicio guarde.
- En Studio sin acceso a las APIs usa memoria y lo avisa en el Output. `DataDebug` (barra de comandos de Studio) muestra y resetea perfiles.

## Estado para la UI

La interfaz solo presenta lo que decide el servidor. El builder publica ese estado y lo documenta en la Arquitectura del GDD, en la tabla **Estado para la UI**; el [UI designer](../../roblox-ui-designer/SKILL.md) construye las pantallas sobre ella sin leer el código del servidor.

| Atributo del jugador | Tipo | Lo escribe | Significado |
| --- | --- | --- | --- |
| `Level` | número | `Obby` | Nivel actual, desde 1 |

- Atributos de `Player` para el estado de cada jugador (nivel, moneda visible, vidas), y de una instancia compartida, como `ReplicatedStorage`, para el estado de la ronda (fase, tiempo restante). Solo los escribe el servidor.
- Remotes que la UI puede disparar, con dirección, payload y validación: son **intenciones** ("comprar artículo X", "reiniciar nivel"); el servidor decide si se cumplen.
- Si la UI no envía nada al servidor, dilo.

`check_ui.py` avisa si la UI lee un atributo que ningún script del servidor escribe y si el GDD no tiene la tabla.

## Orden de inicio

`Bootstrap.server.luau` es la única entrada del servidor y arranca en este orden:

1. Requiere Config, Tuning y Telemetry, y aplica `Style.applyLighting` si hay tema y no hay pase de arte.
2. Inicia el servicio de datos, si el juego guarda progreso: `PlayerData.start()`.
3. Construye el mundo: `LevelLoader.applyPhysics` y `LevelLoader.build`, o el módulo de mundo propio, y después `EnvironmentLoader.apply` si hay pase de arte.
4. Crea los remotes.
5. Llama a `Game.start(contexto)` con lo que construyó (por ejemplo `built` y la física). `Game` hace `init` de cada core, `connect` de cada puente y `start` de cada core, que conecta las piezas construidas y atiende `PlayerAdded` y a los jugadores ya presentes ([arquitectura de módulos](module-architecture.md#game)).

Hasta el paso 5 ningún jugador puede interactuar con el juego. Con varios places, el mismo `Bootstrap` corre en todos: el paso 3 construye solo los niveles del place y `Game` arranca los cores según `Place.role()`.

## Ejemplo

[assets/example-places](../assets/example-places/README.md) aplica `Place` y `Travel` en una experiencia con dos places, con un core por place. [assets/example-obby](../assets/example-obby/README.md) aplica todo lo demás: el core `Obby` implementa peligros, checkpoints y metas con telemetría, `EnvironmentLoader` viste los niveles, y la UI muestra el estado que publica el servidor en atributos del jugador, documentados en Estado para la UI. [assets/skeleton](../assets/skeleton) muestra dos cores unidos por un puente. [assets/example-quests](../assets/example-quests/README.md) usa `PlayerData` con tres fachadas, una migración de datos y tres puentes encadenados.
