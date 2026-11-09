# Datos del jugador: Valle de Gremios

Esquema: `src/server/Data/DataSchema.json` (versión 2). Persistencia: `persistent`. Clave: `player_{UserId}` en el DataStore `PlayerData`. Límites de Roblox verificados el 14 de octubre de 2026.

RPG de misiones con tres facciones, compañeros que se reclutan con fichas, inventario, recompensa diaria y una tienda con Developer Products. Basado en el diseño de datos de MyIsekai (UEFN): las misiones se guardan por ID y el catálogo vive en el código.

## Promesas del GDD

| Promesa | Dónde se guarda | Notas |
| --- | --- | --- |
| El jugador conserva sus monedas y gemas | `economy.wallet` | Monedas `coins` y `gems` |
| Las misiones completadas no se repiten y las activas siguen donde quedaron | `quests.completed`, `quests.active` | Progreso de cada objetivo en `objectives` |
| La reputación con cada facción abre misiones nuevas | `quests.reputation` | Los umbrales están en el catálogo |
| Los objetos y lo equipado se conservan | `inventory.stacks`, `inventory.items`, `inventory.equipped` | |
| Los compañeros conservan su experiencia y afinidad | `companions.recruited` | |
| Las fichas de reclutamiento no se pierden | `companions.tokens` | |
| La racha diaria se mantiene si el jugador vuelve al día siguiente | `rewards.daily` | Hora del servidor |
| Lo comprado con Robux no se pierde ni se entrega dos veces | `purchases.processed`, `entitlements.owned` | |
| El tutorial no se repite | `onboarding.flags` | |

## Dominios y dueños

| Sección | Dueño (core) | Qué guarda | Crecimiento |
| --- | --- | --- | --- |
| `meta` | `PlayerData` | Primera y última entrada, sesiones, tiempo de juego | Fijo |
| `onboarding` | `Onboarding` | Hitos del tutorial con su fecha | Hasta 50 banderas |
| `economy` | `Economy` | Saldo por moneda | Hasta 10 monedas |
| `quests` | `Quests` | Misiones activas, completadas y reputación | Hasta 10 activas y 1.000 completadas |
| `inventory` | `Inventory` | Apilables, únicos y equipado | 200 tipos apilables, 300 únicos |
| `companions` | `Companions` | Compañeros reclutados y fichas | Hasta 60 compañeros |
| `rewards` | `Rewards` | Racha diaria | Fijo |
| `stats` | `Stats` | Contadores para logros y KPIs | Hasta 50 contadores |
| `purchases` | `Shop` | Recibos ya entregados | Los últimos 200 |
| `entitlements` | `Shop` | Derechos que duran | Hasta 100 |

Cada sección la escribe solo su dueño. Por ejemplo, completar una misión que da monedas no toca `economy` desde `Quests`: el core `Quests` publica `completed`, el puente `Quests_Economy` lo escucha y llama a `Economy.add`, y `Game` le pasa cuántas monedas da cada misión.

## Modelo de clases

```text
PlayerData (núcleo: carga, bloqueo, autosave, migraciones)
└── section(player, nombre) → Section (get, update, changed)
    ├── QuestData       (core Quests)      isActive, isCompleted, start, addObjective, complete, reputationOf
    ├── WalletData      (core Economy)     balance, add, spend
    ├── InventoryData   (core Inventory)   count, addStack, removeStack, addItem, equip
    ├── CompanionData   (core Companions)  recruit, addXp, addAffinity, tokens, spendToken
    ├── DailyData       (core Rewards)     canClaim, claim
    ├── FlagData        (core Onboarding)  has, set
    ├── StatData        (core Stats)       increment, get
    └── ShopData        (core Shop)        hasProcessed, markProcessed, owns, grant
```

Cada fachada vive dentro de su core (`Modules/Quests/QuestData.luau`) y es la única que llama a `section(player, "quests")`. Es el equivalente de `quest_data_manager` de MyIsekai, sin el constructor de copia: el servicio completa los valores por defecto desde el esquema.

Eventos que publican los cores con esta información: `Quests.started`, `Quests.completed`, `Economy.changed`, `Inventory.changed`, `Companions.recruited`, `Rewards.claimed`.

## Secciones

### `meta`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `firstJoinAt` | time | 0 | — | Primera entrada |
| `lastJoinAt` | time | 0 | — | Última entrada |
| `sessions` | integer | 0 | ≥ 0 | Sesiones jugadas |
| `playTimeSec` | integer | 0 | ≥ 0 | Segundos jugados |

### `onboarding`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `flags` | map flagId → time | {} | 50 | Hitos cumplidos: `first_mission`, `second_mission`, `third_mission`, `first_travel`, `quest_screen_seen` |

### `economy`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `wallet` | map currencyId → integer | {} | 10 monedas, hasta 999.999.999.999 | Saldo de `coins` y `gems` |

### `quests`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `active` | map questId → { startedAt, objectives } | {} | 10 | Misiones en curso y el progreso de cada objetivo |
| `completed` | map questId → time | {} | 1.000 | Misiones terminadas y cuándo |
| `reputation` | map factionId → integer | {} | 12 facciones, hasta 100.000 | Reputación con cada facción |

### `inventory`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `stacks` | map itemId → integer | {} | 200 tipos, 9.999 cada uno | Materiales y consumibles |
| `items` | map uid → { itemId, level, acquiredAt } | {} | 300 | Armas y equipo únicos; el `uid` lo genera el servidor |
| `equipped` | map slot → uid | {} | 6 | Qué objeto único va en cada ranura |

### `companions`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `recruited` | map companionId → { recruitedAt, xp, affinity } | {} | 60 | Compañeros reclutados |
| `tokens` | map tokenId → integer | {} | 12 | Fichas por clase y rareza (`support_rare`, `striker_epic`) |

### `rewards`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `daily` | { streak, lastClaimAt } | { 0, 0 } | racha ≤ 3.650 | Racha de la recompensa diaria |

### `stats`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `counters` | map statId → integer | {} | 50 | `enemies_defeated`, `quests_completed`, `items_crafted` |

### `purchases`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `processed` | map purchaseId → time | {} | 200 | Recibos entregados; al pasar de 200 se borra el más viejo |

### `entitlements`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `owned` | map productKey → { grantedAt, source } | {} | 100 | Derechos que duran; `source` es `purchase`, `gift` o `event` |

## Seguimiento del progreso

- **Misiones:** una misión que no está en `active` ni en `completed` está disponible si el catálogo lo permite (facción, reputación, misión previa). `start` la agrega a `active`; cada objetivo suma en `objectives`; `complete` la mueve a `completed` con la fecha y suma reputación.
- **Onboarding:** `FlagData.set` devuelve si la bandera es nueva; solo entonces se emite `Telemetry.onboarding`.
- **Estadísticas:** los contadores alimentan logros y los KPIs del GDD; cada core que cuenta algo lo hace por el puente con `Stats`.
- **Racha diaria:** `canClaim` compara `lastClaimAt` con la hora del servidor; si pasaron más de 48 horas, la racha vuelve a 1.

## Estado de sesión

No se guarda: la posición del jugador, la zona actual, el combate en curso y los cooldowns de habilidades (core `Combat`), y la misión seguida en la UI (cliente).

## Ciclo de vida

- **Entrada:** `PlayerData` carga con `UpdateAsync` y toma el bloqueo de sesión; mientras tanto el estado es `loading` y la UI muestra "Cargando tu progreso". Al terminar, actualiza `meta` y publica `onLoaded`; recién ahí los cores atienden al jugador.
- **Autosave:** cada 180 segundos con desfase aleatorio por jugador, y solo si hubo cambios.
- **Salida y cierre:** guardado final y liberación del bloqueo en `PlayerRemoving` y en `BindToClose` (30 segundos, todos en paralelo).
- **Viajes:** antes de viajar al place de la mazmorra, `Travel.onBeforeTravel` llama a `PlayerData.save`.
- **Carga fallida:** el estado es `unavailable`. El jugador puede moverse pero no ganar, gastar ni comprar; nunca se guarda un perfil por defecto encima del real.

## Migraciones

| Versión | Cambio | Operaciones |
| --- | --- | --- |
| 1 | Primera versión | — |
| 2 | Monedas en un mapa por moneda; `quests.done` pasa a `quests.completed`; booleanos de onboarding pasan a banderas; secciones nuevas `companions`, `stats`, `purchases` y `entitlements` | `move` de `economy.coins` a `economy.wallet.coins`, `move` de `quests.done` a `quests.completed` y `custom` `flagsFromBooleans` |

Las secciones nuevas no necesitan operaciones: el servicio las completa con sus valores por defecto.

## Presupuesto

`check_data.py` estima 127.064 caracteres en el peor caso (3,0 % del límite por clave). La sección que más pesa es `quests`, por las 1.000 misiones completadas; si el catálogo pasara de 1.000 misiones, se subiría `maxEntries` antes que guardar historiales.

## Fallos y recuperación

Si un guardado falla, se reintenta en el próximo autosave y el jugador sigue jugando. Un perfil dañado se recupera desde las versiones anteriores de la clave, que duran 30 días; lo hace el dueño de la experiencia con Open Cloud o un script de Studio, nunca automáticamente.

## Borrado y privacidad

No se guardan nombres de usuario, correos ni texto escrito por el jugador. Para los pedidos de borrado, el dueño de la experiencia configura la plantilla de borrado de Roblox con la clave `player_{UserId}` en el DataStore `PlayerData`.

## Pruebas

- Studio con acceso a la API: entrar, completar una misión, salir y volver; simular una carga fallida y comprobar que no se sobrescribe el perfil; cerrar el servidor con jugadores; reset con `DataDebug`.
- Migración: cargar un perfil de la versión 1 (con `coins`, `done` y los tres booleanos) y comprobar el resultado.
- Experiencia publicada: dos servidores con el mismo jugador (el segundo espera el bloqueo) y el viaje a la mazmorra.

## Pendientes

- `data-architect → builder: crear los cores Onboarding, Economy, Quests, Inventory, Companions, Rewards, Stats y Shop con sus fachadas, y los puentes Quests_Economy y Quests_Stats (abierto)`.
- `data-architect → builder: implementar la migración custom flagsFromBooleans en Migrations.luau (abierto)`.
