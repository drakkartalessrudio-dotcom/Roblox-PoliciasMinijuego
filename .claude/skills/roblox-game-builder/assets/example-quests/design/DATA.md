# Datos del jugador: Aldea de Gremios

Esquema: `src/server/Data/DataSchema.json` (versión 2). Persistencia: `persistent`. Clave: `player_{UserId}` en el DataStore `PlayerData`. Límites de Roblox verificados el 14 de octubre de 2026.

## Promesas del GDD

| Promesa | Dónde se guarda | Notas |
| --- | --- | --- |
| Las misiones completadas no se repiten y las activas siguen donde quedaron | `quests.completed`, `quests.active` | Por id de misión; el catálogo vive en `Game/Content.luau` |
| El jugador conserva sus monedas y gemas | `economy.wallet` | Monedas `coins` y `gems` |
| La racha de la recompensa diaria se mantiene | `rewards.daily` | Hora del servidor |

## Dominios y dueños

| Sección | Dueño (core) | Qué guarda | Crecimiento |
| --- | --- | --- | --- |
| `meta` | `PlayerData` | Primera y última entrada, sesiones, tiempo de juego | Fijo |
| `quests` | `Quests` | Misiones activas con su progreso y misiones completadas | Hasta 20 activas y 500 completadas |
| `economy` | `Economy` | Saldo por moneda | Hasta 10 monedas |
| `rewards` | `Rewards` | Racha diaria | Fijo |

`Zones` no guarda nada: una visita a una zona es progreso de una misión y la guarda `Quests`.

## Modelo de clases

```text
PlayerData (núcleo) → section(player, "quests")  → QuestData   → Quests
                    → section(player, "economy") → EconomyData → Economy
                    → section(player, "rewards") → RewardData  → Rewards
```

Cada fachada vive dentro de su core y es la única que usa su sección: `QuestData` (`isActive`, `isCompleted`, `progress`, `start`, `addProgress`, `complete`), `EconomyData` (`balance`, `add`, `spend`) y `RewardData` (`daily`, `setDaily`). Las tres tipan lo que leen y escriben con `src/shared/DataTypes.luau`.

## Secciones

### `meta`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `firstJoinAt` | time | 0 | — | Primera entrada |
| `lastJoinAt` | time | 0 | — | Última entrada |
| `sessions` | integer | 0 | ≥ 0 | Sesiones |
| `playTimeSec` | integer | 0 | ≥ 0 | Segundos jugados |

### `quests`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `active` | map questId → { startedAt, objectives } | {} | 20 | Misiones en curso y el progreso de cada objetivo (hasta 8, hasta 1.000 cada uno) |
| `completed` | map questId → time | {} | 500 | Misiones terminadas y cuándo |

### `economy`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `wallet` | map currencyId → integer | {} | 10 monedas, hasta 999.999.999 | Saldo de `coins` y `gems` |

### `rewards`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `daily` | { streak, lastClaimAt } | { 0, 0 } | racha ≤ 3.650 | Racha y fecha de la última recompensa diaria |

## Seguimiento del progreso

Una misión que no está ni en `active` ni en `completed` está disponible si el jugador completó las misiones de su `requires` (en el catálogo). `Quests` la empieza sola, suma progreso con cada `reportObjective` y, cuando todos los objetivos llegan a su meta, la pasa a `completed`. La facción y la recompensa salen del catálogo: no se guardan.

## Estado de sesión

No se guarda: cuándo entró el jugador por última vez a cada zona (`Zones`, para el enfriamiento) y la posición.

## Ciclo de vida

`Bootstrap` llama a `PlayerData.start()` antes de construir el mundo. Cada core espera a que cargue el perfil antes de leer o escribir (`waitUntilReady` en su fachada): hasta entonces las zonas no suman y la recompensa diaria no se entrega. Se guarda cada 180 segundos si hubo cambios, al salir y al cerrar el servidor.

## Migraciones

| Versión | Cambio | Operaciones |
| --- | --- | --- |
| 1 | Primer prototipo: `economy.coins` y `quests.done` | — |
| 2 | Las monedas pasan a un mapa por moneda para sumar gemas; `quests.done` se llama `completed` | `move` de `economy.coins` a `economy.wallet.coins` y de `quests.done` a `quests.completed` |

La versión 1 está para mostrar cómo se migra: `check_data.py` simula un perfil de esa versión con `history["1"]` y comprueba que nada se pierda.

## Presupuesto

`check_data.py` estima 31.712 caracteres en el peor caso (0,8 % del límite por clave). La sección que más pesa es `quests`.

## Fallos y recuperación

Un guardado fallido se reintenta en el próximo autosave. Las versiones anteriores de la clave duran 30 días.

## Borrado y privacidad

No se guardan datos personales. Para los pedidos de borrado: plantilla de borrado de Roblox con la clave `player_{UserId}` en el DataStore `PlayerData`.

## Pruebas

En Studio con acceso a las APIs: completar "Conocé la aldea", salir y volver (las monedas y las misiones siguen), y `DataDebug.reset(player)` para empezar de cero. Sin acceso a las APIs, `PlayerData` usa memoria y lo avisa en el Output.

## Pendientes

Ninguno.
