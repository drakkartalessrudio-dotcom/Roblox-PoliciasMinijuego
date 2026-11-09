# Arquitectura de módulos

Cómo se organiza el código de un juego de la fábrica para que cada sistema se pueda reutilizar, cambiar o quitar sin tocar los demás. Viene de la forma de trabajar en UEFN de los proyectos del usuario (por ejemplo MyIsekai): módulos core independientes, módulos puente cuando dos cores tienen que hablar y un módulo Main del juego que mezcla todo. `check_modules.py` comprueba estas reglas; `check_game.py` lo ejecuta.

## Capas

| Capa | Carpeta | Qué tiene | Puede requerir |
| --- | --- | --- | --- |
| Núcleo | `src/shared/` y la raíz de `src/server/` y `src/client/` | Plantillas de la fábrica (`Tuning`, `Telemetry`, `Signal`, `LevelLoader`, `Style`, `EnvironmentLoader`, `Place`, `Travel`, `Analytics`, `LiveConfig`), `Config`, `ServerConfig` y los datos (`Levels.json`, `Theme.json`…) | Solo el núcleo |
| Core | `src/<lado>/Modules/<Nombre>/` | Un sistema reutilizable: misiones, zonas, economía, inventario, rondas | Su propio módulo y el núcleo |
| Puente | `src/<lado>/Bridges/<Origen>_<Destino>/` | La conexión entre dos cores: escucha los eventos de `Origen` y llama la API de `Destino` | Sus dos cores y el núcleo |
| Game | `src/<lado>/Game/` | La composición del juego: contenido, configuración de cada core, arranque y reacciones propias de este juego | Todo |
| UI | `src/client/UI/` (del UI designer) | Pantallas sobre el estado que publica el servidor | El núcleo y los cores de cliente |
| Entrada | `Bootstrap.server.luau` y los Script o LocalScript de la raíz | Arranque | El núcleo y `Game` |

`<lado>` es `server`, `client` o `shared`: un core puede tener partes en los tres (`server/Modules/Quests`, `client/Modules/Quests`, `shared/Modules/Quests`) y siguen siendo el mismo módulo. Un módulo es una carpeta con `init.luau` o un solo archivo `<Nombre>.luau`.

Nadie requiere a `Game` salvo la entrada, y nadie de fuera de `UI/` requiere a la UI. El núcleo no conoce los módulos del juego: las plantillas que cargan un módulo opcional (como `Telemetry` con `Analytics`) lo buscan por nombre con `pcall`, sin `require` fijo.

## Módulo core

Un core resuelve un solo tema y no sabe en qué juego está. Su contrato:

```lua
-- src/server/Modules/Quests/init.luau
local Quests = {}

Quests.completed = Signal.new() :: Signal.Signal<Player, string> -- eventos: verbo en pasado

function Quests.init(catalog: Catalog) end -- contenido y opciones, antes de start
function Quests.start() end -- atiende PlayerAdded y a los jugadores ya presentes
function Quests.progress(player: Player, questId: string, amount: number): boolean end

return Quests
```

- **Eventos con `Signal`** (plantilla del núcleo): `Quests.completed:Connect(...)`. Solo el módulo dueño llama a `Fire`.
- **Contenido inyectado:** el catálogo, los textos, qué zona es cuál, llegan en `init` desde `Game`. En UEFN esto se hacía con subclases y `@editable` en el Main; en Luau se pasa como datos.
- **Estado propio:** guarda su estado por jugador y no entrega tablas internas para que otro las modifique. Los atributos que escribe para la UI llevan su nombre en la columna "Lo escribe" de Estado para la UI.
- **Ajustes:** lee con `Tuning.get`, preferiblemente desde una sección de Config con su nombre.
- **Datos guardados:** un core escribe solo su propia sección del perfil del jugador. Desde la fase 15 las secciones las diseña el data architect y las escribe solo su módulo dueño.

Si un core necesita algo de otro, no lo requiere: publica un evento y deja que un puente lo conecte, o recibe una función en `init` que `Game` le pasa.

## Puente

Un puente une dos cores y se llama `<Origen>_<Destino>`: `Origen` emite el evento, `Destino` reacciona. Es el equivalente de `ModuleTycoon_TrackerQuest` o `ModuleRoomSystem_TrackerQuest` en UEFN.

```lua
-- src/server/Bridges/Zones_Quests/init.luau
local Quests = require(ServerScriptService.Server.Modules.Quests)
local Zones = require(ServerScriptService.Server.Modules.Zones)

local Zones_Quests = {}

function Zones_Quests.connect(options: { questsByZone: { [string]: { string } } })
	Zones.entered:Connect(function(player, zoneId)
		local questIds = options.questsByZone[zoneId]
		if not questIds then
			return
		end
		for _, questId in questIds do
			Quests.progress(player, questId, 1)
		end
	end)
end

return Zones_Quests
```

- Requiere solo sus dos cores y el núcleo. Nunca otro puente, un tercer core ni `Game`.
- No tiene contenido propio: qué zona avanza qué misión lo pasa `Game` en `connect`, como el Main de MyIsekai sobrescribía `QuestsNodes`.
- Un puente por par. Si la relación va en los dos sentidos, el mismo puente conecta ambos.
- Si hacen falta tres cores, son dos puentes o una reacción en `Game`.

## Game

`Game` es el único lugar que conoce todo el juego. `Game/init.luau` exporta `start(contexto)` y arranca en este orden:

1. `init` de cada core, con su contenido y opciones. Todavía no hay jugadores.
2. `connect` de cada puente, para que ningún evento del arranque se pierda.
3. `start` de cada core: atienden `PlayerAdded` y a los jugadores ya presentes.

El contenido del juego (catálogos, mapas entre cores, textos) va en archivos de `Game/`, por ejemplo `Game/Content.luau`. Las reacciones propias de este juego que mezclan módulos o el núcleo (un atributo para la UI cuando se completa una misión, un evento de telemetría que necesita dos cores) también van en `Game`. Cambiar el juego no toca ningún core.

`Bootstrap.server.luau` prepara el núcleo y llama a `Game.start`. No requiere cores ni puentes.

## Cliente

El cliente usa las mismas capas: `src/client/Modules/`, `src/client/Bridges/` y `src/client/Game/`, con una entrada `LocalScript` en la raíz. La interfaz es la capa `UI/` del [UI designer](../../roblox-ui-designer/SKILL.md): lee atributos y remotes del servidor, y puede usar el núcleo y los cores de cliente.

## Excepciones

A veces un core se apoya en otro más básico, como un jefe que usa el sistema de habilidades. Antes de aceptarlo, prueba un puente o pasarle una función en `init`. Si aun así conviene la dependencia directa, decláralo en la columna "Excepción" del Mapa de módulos con el motivo: `check_modules.py` la reporta como aviso en lugar de error, y sigue sin aceptar ciclos.

## Mapa de módulos

Va en la sección Arquitectura del GDD. Una fila por core, puente y `Game`:

```markdown
### Mapa de módulos

| Módulo | Capa | Responsabilidad | API y eventos | Datos que posee | Excepción | Origen |
| --- | --- | --- | --- | --- | --- | --- |
| `Zones` | core | Detectar la entrada a zonas | `init(options)`, `start()`; `entered(player, zoneId)` | — | — | propio |
| `Quests` | core | Progreso de misiones | `init(catalog)`, `start()`, `progress(...)`; `completed(player, questId)` | `quests` | — | propio |
| `Zones_Quests` | puente | Una zona avanza misiones | `connect({ questsByZone })` | — | — | propio |
| `Game` | main | Contenido, arranque y reacciones del juego | `start(contexto)` | — | — | propio |
```

Capas válidas: `core`, `puente` y `main`. En "Origen", `librería <Nombre>@<versión>` para lo que se copió de la [librería de módulos](module-library.md) y `propio` para lo que se escribió en el juego. En "Excepción" van, entre comillas invertidas, los cores de los que este depende directamente y por qué; `—` si ninguno.

## Orden de inicio

`Bootstrap` arranca el núcleo y después `Game` (ver [puntos de enganche](hooks.md#orden-de-inicio)):

1. Config, Tuning y Telemetry; `Style.applyLighting` si hay tema y no hay pase de arte.
2. El servicio de datos, si el juego guarda progreso.
3. El mundo: `LevelLoader` y `EnvironmentLoader`, o el módulo de mundo propio.
4. Los remotes.
5. `Game.start(contexto)`: `init` de los cores, `connect` de los puentes y `start` de los cores.

## Pasar un juego plano a capas

Un juego hecho antes de esta guía tiene sus servicios en la raíz de `src/server/`. `check_modules.py` lo informa sin error. Para pasarlo a capas sin cambiar cómo se juega:

1. Haz una lista de sistemas y de quién llama a quién.
2. Mueve cada sistema a `Modules/<Nombre>/init.luau` con `init` y `start`; lo que recibía en `start` (como `built`) pasa a `init`.
3. Reemplaza cada llamada directa entre sistemas por un evento con `Signal` y un puente, o por una reacción en `Game`.
4. Crea `Game/init.luau` con el orden de arranque y deja `Bootstrap` llamando solo a `Game.start`.
5. Actualiza el Mapa de módulos, Estado para la UI ("Lo escribe") y el README; corre `check_game.py`, luau-lsp y `rojo build`.

Hasta terminar, `check_modules.py` avisa por los archivos que quedan fuera de las capas.

## Qué revisa `check_modules.py`

```bash
python <skill-dir>/scripts/check_modules.py <Juego>
```

Lee `default.project.json` para saber qué instancia es cada archivo y resuelve cada `require` por ruta de instancia (`script.Parent.X`, `ReplicatedStorage.Shared.X`, `:WaitForChild("X")`) o por texto (`"./X"`, `"../X"`, `"@self/X"`, `"@game/..."`).

| Regla | Qué comprueba | Nivel |
| --- | --- | --- |
| M1 | Un core no requiere otro core, un puente, `Game` ni la UI | ERROR (aviso si es una excepción declarada) |
| M2 | Un puente se llama `<Origen>_<Destino>` con dos cores que existen y requiere solo esos dos y el núcleo | ERROR |
| M3 | Solo la entrada requiere `Game`; el núcleo no requiere cores, puentes, `Game` ni UI | ERROR |
| M4 | Sin `require` circulares, ni entre archivos ni entre cores con excepciones | ERROR |
| M5 | `DataStoreService` en una sola capa o módulo (un único servicio de datos) | ERROR |
| M6 | Cada core, puente y `Game` tiene su fila en el Mapa de módulos, y cada fila tiene su carpeta | Aviso |
| M7 | Un juego sin `Modules/`, `Bridges/` ni `Game/` es un proyecto plano: se informa y no se revisan las capas | INFO |
| M8 | Cada módulo de `library.lock.json` existe y sigue igual a la versión de la [librería](module-library.md) que se copió; el Mapa de módulos dice su Origen | ERROR si falta un archivo; aviso si cambió |

Además avisa si la entrada requiere cores o puentes en lugar de `Game`, si hay módulos de juego sueltos en la raíz de un proyecto con capas y si existen los dos puentes de un mismo par. Un `require` que no puede resolver (un nombre calculado en ejecución) dentro de un core, puente o `Game` queda como nota para revisar a mano.

## Equivalencias con UEFN

| UEFN (MyIsekai) | Roblox |
| --- | --- |
| `ModuleQuestSystem/`, `ModuleTycoon/` | `src/server/Modules/Quests/`, `src/server/Modules/Tycoon/` |
| `ModuleTycoon_TrackerQuest/` | `src/server/Bridges/Tycoon_Quests/` |
| `Module_Main_MyIsekai/` | `src/server/Game/` |
| `PlayerDataManager.verse`, `Utils.verse` en la raíz | El núcleo |
| `QuestStartedSubscribe(Handler)` | `Quests.started:Connect(handler)` |
| Subclase con `<override>` en el Main (`star_war_tycoon_tracker_device`) | Contenido que `Game` pasa en `init` o `connect` |
| `using { ModuleX }` | `require` |

## Esqueleto

[assets/skeleton](../assets/skeleton) es un proyecto mínimo con dos cores (`Zones` y `Quests`), un puente (`Zones_Quests`), `Game` con su contenido y `Bootstrap`. Pasa luau-lsp, `rojo build` y `check_modules.py`. Copia su forma, no sus nombres. El obby y la experiencia de dos places de ejemplo también usan capas.

[assets/example-quests](../assets/example-quests/README.md) (Aldea de Gremios) es la referencia completa para un juego con varios sistemas, con la organización de MyIsekai: los cores `Zones`, `Quests`, `Economy` y `Rewards`, cada uno con la fachada de su sección de datos; los puentes encadenados `Zones_Quests` → `Quests_Rewards` → `Rewards_Economy`; y `Game` con el catálogo de misiones, las recompensas y el onboarding. Agregar una misión o un gremio solo toca `Game/Content.luau`.
