# Experiencias con varios places

Un place es un mundo aparte: su propio Workspace, sus propios servidores y su propia memoria. Una experiencia puede tener varios, y los jugadores pasan de uno a otro con un teleport. Esta guía explica cómo se arma un juego así con la fábrica. Verificado el 13 de octubre de 2026 en la documentación de Roblox ([teleport](https://create.roblox.com/docs/projects/teleport), [publicar places](https://create.roblox.com/docs/production/publishing/publish-experiences-and-places), [data stores](https://create.roblox.com/docs/cloud-services/datastores)).

## Cuándo conviene

Lo decide el game designer en el GDD. Conviene cuando:

- el mundo es grande o tiene muchas zonas, y no entra cómodo en la memoria de un servidor (sobre todo en celulares);
- hay un vestíbulo y partidas: los jugadores se agrupan en el vestíbulo y cada partida corre en su propio servidor reservado;
- los modos o las zonas necesitan cantidades de jugadores distintas, o reglas y ambientes muy distintos;
- varias personas van a trabajar en zonas separadas durante mucho tiempo.

No conviene para pocos mapas chicos que se juegan con los mismos jugadores: ahí alcanza con un place que construye el mapa de cada ronda a demanda (`LevelLoader.build` con `only`, ver [puntos de enganche](hooks.md#levelloader-el-mundo-desde-levelsjson)). Varios places suman viajes que pueden fallar, emparejamiento y pruebas que solo se hacen publicado.

## Qué comparten los places de una experiencia

- **Datos:** los DataStores son de la experiencia; todos los places leen y escriben el mismo progreso.
- **Compras:** los pases y productos son de la experiencia (según fuentes de la comunidad): los mismos IDs valen en todos los places.
- **Código:** con la fábrica, todos los places usan el mismo `src/`. Cada uno arranca lo que le toca.

No comparten servidor: un jugador que viaja sale de un servidor y entra a otro.

## Cómo se declara

En el frontmatter del GDD, `project.places` pasa de `1` a una lista:

```yaml
project:
  places:
    - id: vestibulo
      role: start      # la entrada de la experiencia; exactamente uno
      maxPlayers: 30
    - id: arena
      role: match      # partidas: el grupo viaja a un servidor reservado
      maxPlayers: 12
    - id: bosque
      role: area       # zona del mundo: servidores públicos
      maxPlayers: 20
```

Y la sección **Places y viajes** del GDD: qué tiene cada place y una tabla de viajes (de, a, cuándo, tipo de servidor, qué datos viajan, qué pasa si falla).

## Estructura del proyecto

```text
<Juego>/
├── default.project.json        → el place de inicio
├── places/
│   ├── arena.project.json      → un proyecto por cada otro place
│   └── bosque.project.json
├── src/
│   ├── shared/                 → Places.json, Place.luau, Levels.json, Config.luau, ...
│   ├── server/                 → Bootstrap.server.luau, Travel.luau, servicios
│   └── client/
└── build/                      → un .rbxlx por place
```

Todos los proyectos mapean las mismas carpetas de `src/` (en `places/`, con `../src/...`) y agregan en `ReplicatedStorage` un `StringValue` llamado `PlaceKey` con la clave del place:

```json
"ReplicatedStorage": {
  "Shared": { "$path": "../src/shared" },
  "PlaceKey": { "$className": "StringValue", "$properties": { "Value": "arena" } }
}
```

Así el mismo código sabe en qué place corre, en Studio y publicado.

## Registro: `src/shared/Places.json`

```json
{
  "schemaVersion": 1,
  "start": "vestibulo",
  "places": {
    "vestibulo": { "placeId": 0, "role": "start", "maxPlayers": 30 },
    "arena": { "placeId": 0, "role": "match", "maxPlayers": 12 }
  }
}
```

`placeId` vale 0 hasta que el usuario crea los places en la experiencia y carga sus IDs. Nunca se inventa un PlaceId.

## `Place` y `Travel`

Copia de las plantillas `src/shared/Place.luau` y `src/server/Travel.luau`, sin cambiar su API.

| `Place` | Qué hace |
| --- | --- |
| `Place.current()` | Clave del place en el que corre el código (lee `PlaceKey`) |
| `Place.start()` | Clave del place de inicio |
| `Place.info(key?)`, `Place.role(key?)` | Datos y rol de un place: `start`, `match` o `area` |
| `Place.id(key)` | PlaceId publicado, o `nil` si está pendiente |
| `Place.all()` | Claves de todos los places |
| `Place.levels(Levels, key?)` | Ids de los niveles de ese place (un nivel sin `place` va al de inicio) |

| `Travel` (solo servidor) | Qué hace |
| --- | --- |
| `Travel.to(jugadores, clave, opciones?)` | Viaja con reintentos. `opciones.reserved` crea un servidor reservado para el grupo; `opciones.accessCode` entra a uno existente; `opciones.data` lleva datos no sensibles. Devuelve `(true, resultado)` o `(false, motivo)`: `"desconocido"`, `"pendiente"`, `"studio"` o el error de Roblox |
| `Travel.toStart(jugadores)` | Vuelve al place de inicio |
| `Travel.onBeforeTravel(función)` | Corre antes de cada viaje, por jugador: guarda ahí el perfil |
| `Travel.arrival(jugador)` | Datos con los que llegó el jugador. No son confiables: el cliente puede verlos |

Si un viaje falla del todo, el jugador recibe el atributo `TravelFailed` con la clave del destino: la UI lo avisa y el jugador sigue jugando donde estaba. `Travel` emite los eventos `travel` y `travel_failed` con `Telemetry`; con analíticas, decláralos en el esquema.

## Entrada de cada place

Un solo `Bootstrap.server.luau` para todos, que construye lo del place y arranca sus sistemas según el rol:

```lua
local Place = require(ReplicatedStorage.Shared.Place)
LevelLoader.applyPhysics(Levels.physics)
local built = LevelLoader.build(Levels, nil, { only = Place.levels(Levels) })
if Place.role() == "start" then
	LobbyService.start(built)
else
	MatchService.start(built)
end
```

## Datos y compras

- Un solo servicio de datos para todos los places. Guarda en `Travel.onBeforeTravel` y en `PlayerRemoving`. Con `PlayerData` ([roblox-data-architect](../../roblox-data-architect/SKILL.md)): `Travel.onBeforeTravel(function(player) PlayerData.save(player) end)`; el guardado final y la liberación del bloqueo ya ocurren al salir.
- **El bloqueo de sesión es obligatorio:** el jugador se guarda en un servidor y se carga en otro casi al mismo tiempo. Usa `UpdateAsync` con un bloqueo que el servidor de destino espere antes de cargar. `PlayerData` lo hace: el place de destino reintenta la carga mientras el de origen libera el bloqueo.
- El progreso y la moneda viajan por DataStore, nunca en los datos del teleport.
- Registra `ProcessReceipt` en todos los places donde haya jugadores (con el mismo código, ya ocurre): Roblox reintenta un recibo pendiente cuando el jugador vuelve a entrar.

## Construir, probar y publicar

- Construye un archivo por place: `rojo build default.project.json -o build/<Inicio>.rbxlx` y `rojo build places/<place>.project.json -o build/<Place>.rbxlx`. `rojo serve` acepta el proyecto de cada place.
- **TeleportService no funciona en Studio.** Prueba cada place por separado en Studio (`Travel` avisa en vez de viajar) y los viajes en la experiencia publicada, mejor en una experiencia de prueba.
- Publicar es del usuario: el start place se publica como experiencia, y cada otro place con **Archivo → Publicar como → Agregar como place nuevo**. Después carga los PlaceId en `Places.json` y en el GDD, configura el tamaño de servidor de cada place en Creator Hub y limita los places que no son la entrada a "solo por teleport".

## Qué revisa `check_game.py`

- `project.places` con ids, roles y exactamente un `start`.
- `Places.json` igual al GDD; PlaceId pendientes (aviso) o declarados en el GDD (un ID que no está en el GDD es un error).
- `Place.luau` y `Travel.luau` con su API.
- `default.project.json` con el `PlaceKey` de inicio y un `places/<place>.project.json` por cada otro place, con su `PlaceKey` y las mismas carpetas compartidas.
- Cada nivel de `Levels.json` con un `place` declarado; la sección "Places y viajes"; `TeleportService` solo dentro de `Travel`; `TeleportAsync` nunca en el cliente; `UpdateAsync` si hay datos.

## Ejemplo

[assets/example-places](../assets/example-places/README.md): una plaza con un portal y una torre de saltos en otro place, que comparten el mismo código.
