---
project:
  name: AldeaDeGremios
  mode: prototype
  genre: rpg
  places: 1
  platforms: [desktop, mobile]
design:
  levels: true
  art: false
  environment: false
  ui: false
  data: true
data:
  persistence: persistent
monetization:
  enabled: []
analytics:
  enabled: false
liveops:
  enabled: false
---

# Aldea de Gremios

Juego de referencia de la fábrica para juegos con varios sistemas: cuatro módulos core unidos por tres puentes, un módulo `Game` con el contenido y datos guardados con `PlayerData`. Está inspirado en la organización de MyIsekai (UEFN): sistema de misiones independiente, trackers como módulos puente y el catálogo en el módulo principal. Los cores y los puentes vienen de la librería de módulos (`Roblox-Library`, versiones en `library.lock.json`); `Game` es propio.

## Concepto

Una aldea con dos gremios, leñadores y mineros. El jugador recorre el bosque y la mina para cumplir sus encargos, gana monedas y vuelve cada día por la recompensa diaria.

Pilares:

1. Siempre hay una misión a la vista.
2. Cada visita a una zona cuenta.
3. Volver cada día vale la pena.

## Loop principal

- **Momento a momento:** caminar hasta una zona y entrar; el panel suma progreso.
- **Sesión:** completar las misiones activas de los dos gremios; cada misión completa abre la siguiente de su gremio.
- **Regreso:** la recompensa diaria con racha y las misiones que quedaron a medias.

Se juega igual en solitario. No hay pérdida ni muerte: la aldea no tiene peligros.

## Onboarding

1. Entrar (`joined`).
2. Entrar al bosque o a la mina por primera vez (`first_zone`).
3. Completar "Conocé la aldea" (`first_quest_completed`).

El panel muestra la primera misión apenas carga el perfil.

## Progresión

"Conocé la aldea" abre la primera misión de cada gremio; cada misión de gremio abre la siguiente. Al completar la segunda de cada gremio el jugador recibe una gema.

## Contenido y alcance

MVP: una aldea, dos zonas que cuentan, cinco misiones, monedas, gemas y recompensa diaria. Posterior: tienda para gastar monedas, más gremios y misiones de recolección.

## Brief de niveles

Un nivel hub ("aldea") de 100 × 100 studs: plaza central con el punto de aparición, bosque al noroeste y mina al noreste, a unos 40 studs de la plaza. Sin saltos ni peligros.

## Física y métricas del personaje

Valores habituales de Roblox: `walkSpeed` 16, `jumpHeight` 7.2 y `gravity` 196.2.

## Plataformas e interacción

PC y celular. No hay botones: solo caminar. El panel del HUD queda arriba a la derecha, lejos del chat y de los controles táctiles.

## Estado y economía

Se conserva entre sesiones:

- Las misiones completadas y el progreso de las activas: al volver, siguen donde quedaron.
- Las monedas y las gemas.
- La racha de la recompensa diaria.

Si la carga del perfil falla, el jugador puede caminar por la aldea, pero no avanza misiones ni gana monedas (nada se guarda).

| Fuente | Moneda | Cantidad |
| --- | --- | --- |
| Misiones | `coins` | 20 a 60 por misión |
| Misiones de segundo rango | `gems` | 1 |
| Recompensa diaria | `coins` (y `gems` desde el día 4) | 10, 15, 20, 25 |

Todavía no hay sumideros: la tienda queda para después (Suposición: el prototipo valida el loop de misiones antes que la economía).

## Parámetros ajustables

| Parámetro | Valor inicial | Uso |
| --- | --- | --- |
| `Zones.Cooldown` | 10 | Segundos antes de que la misma zona vuelva a contar |
| `Rewards.StreakWindowHours` | 48 | Horas desde la última recompensa diaria para que la racha siga |

## Monetización seleccionada

Ninguna (`monetization.enabled: []`).

## KPIs objetivo

| KPI | Definición | Objetivo | Cómo se mide | Decisión |
| --- | --- | --- | --- | --- |
| Conversión del onboarding | Jugadores nuevos que llegan a `first_quest_completed` / jugadores nuevos | Medir línea base | Funnel de onboarding | Acercar las zonas o simplificar la primera misión |
| Misiones por sesión | Eventos de progresión completados / sesiones | Medir línea base | Progresión por gremio | Ajustar objetivos y recompensas |

## Assets y servicios

Sin assets externos: todo se construye con Parts. Usa DataStores: para probar el guardado en Studio hay que activar el acceso a las APIs.

## Arquitectura

```text
src/shared/          Config.luau, Tuning.luau, Signal.luau, DataTypes.luau (generado), Levels.json
src/server/          Bootstrap.server.luau (entrada), LevelLoader.luau, Telemetry.luau
src/server/Data/     PlayerData y su servicio (plantillas de roblox-data-architect), DataSchema.json, Migrations.luau
src/server/Modules/  Zones/, Quests/ (con QuestData), Economy/ (con EconomyData), Rewards/ (con RewardData)
src/server/Bridges/  Zones_Quests/, Quests_Rewards/, Rewards_Economy/
src/server/Game/     init.luau (composición y onboarding), Content.luau (catálogo y recompensas)
src/client/          Hud.client.luau (interfaz mínima del builder)
```

Orden de inicio: `PlayerData.start` → `LevelLoader.applyPhysics` → `LevelLoader.build` → `Game.start`: `init` de Zones, Quests, Economy y Rewards → `connect` de los tres puentes → onboarding → `start` de los cuatro cores. Cada core espera el perfil de cada jugador antes de leer o escribir su sección.

La cadena de una misión: `Zones.entered` → `Zones_Quests` → `Quests.reportObjective` → `Quests.completed` → `Quests_Rewards` → `Rewards.granted` → `Rewards_Economy` → `Economy.add`.

Sin RemoteEvents: el cliente no envía nada. Las zonas se validan en el servidor (jugador vivo y una vez cada `Zones.Cooldown` segundos por zona).

Telemetría: `onboarding` en los tres pasos; `progressionStart` y `progressionComplete` por misión, con el gremio como camino; `economy` en cada movimiento de moneda (`Gameplay` o `TimedReward`).

### Mapa de módulos

| Módulo | Capa | Responsabilidad | API y eventos | Datos que posee | Excepción | Origen |
| --- | --- | --- | --- | --- | --- | --- |
| `Zones` | core | Detectar la entrada a las zonas de los niveles | `init({ built })`, `start()`; `entered(player, zoneId)` | — | — | `librería Zones@1.0.0` |
| `Quests` | core | Misiones con objetivos, requisitos y progreso guardado | `init({ catalog })`, `start()`, `reportObjective`, `isCompleted`; `started`, `progressed`, `completed` | `quests` | — | `librería Quests@1.0.0` |
| `Economy` | core | Monedas: saldo, atributos, leaderstats y telemetría | `init({ currencies })`, `start()`, `add`, `spend`, `balance`; `changed` | `economy` | — | `librería Economy@1.0.0` |
| `Rewards` | core | Entregar recompensas y la racha diaria | `init({ daily })`, `start()`, `grant`, `claimDaily`; `granted`, `dailyClaimed` | `rewards` | — | `librería Rewards@1.0.0` |
| `Zones_Quests` | puente | Una zona suma a un objetivo de misión | `connect({ objectiveByZone })` | — | — | `librería Zones_Quests@1.0.0` |
| `Quests_Rewards` | puente | Una misión completa entrega su recompensa | `connect({ rewardByQuest })` | — | — | `librería Quests_Rewards@1.0.0` |
| `Rewards_Economy` | puente | Una recompensa suma monedas | `connect()` | — | — | `librería Rewards_Economy@1.0.0` |
| `Game` | main | Contenido, arranque y onboarding | `start({ built })` | — | — | propio |

### Estado para la UI

| Atributo del jugador | Tipo | Lo escribe | Significado |
| --- | --- | --- | --- |
| `Coins` | número | `Economy` | Monedas |
| `Gems` | número | `Economy` | Gemas |
| `QuestSummary` | texto | `Quests` | Misiones activas con su progreso |
| `DailyStreak` | número | `Rewards` | Días seguidos de recompensa diaria |
| `DataStatus` | texto | `PlayerData` | `loading`, `ready` o `unavailable` |

La UI no envía acciones al servidor.

## Suposiciones y criterios de aceptación

- Al entrar por primera vez aparece "Conocé la aldea 0/2"; al visitar el bosque y la mina se completa, suma 20 monedas y aparecen las dos misiones de gremio.
- La recompensa diaria se entrega sola al cargar el perfil, una vez por día UTC.
- Al salir y volver (con acceso a las APIs en Studio), las monedas, la racha y el progreso de las misiones siguen iguales.
- Si el perfil no carga, el panel dice que el progreso no se puede guardar y nada avanza.

## Pendientes entre skills

Ninguno.
