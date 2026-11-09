# Datos del jugador: TravesurasBrainrot

Esquema: `src/server/Data/DataSchema.json` (versión 1). Persistencia: `persistent`. Clave: `player_{UserId}` en el DataStore `PlayerData`. Límites de Roblox verificados el 14 de octubre de 2026.

Simulador de travesuras con persecución por estrellas, niveles (1 a 50), mejoras, Ascensión con perks permanentes, Sala de Entrenamiento (AFK), misiones diarias y bandas co-op de sesión. Lo que el jugador conserva viene de "Estado y economía" del GDD; el catálogo (precios, efectos, listas de misiones, diseños de graffiti) vive en el código, y el perfil guarda IDs estables.

## Promesas del GDD

| Promesa | Dónde se guarda | Notas |
| --- | --- | --- |
| Conserva su nivel y XP | `progress.level`, `progress.xp` | Nivel 1–50; XP dentro del nivel |
| Conserva su Dinero depositado | `economy.wallet` | Moneda `dinero` |
| Conserva sus mejoras (incluidas Cinta, Batería y Gimnasio) | `upgrades.levels` | IDs `zapatillas`, `sigilo`, `bolsillos`, `manos`, `fortachon`, `cinta`, `bateria`, `gimnasio` |
| Conserva las herramientas desbloqueadas | `upgrades.tools` | IDs `tarta`, `banana`, `humo`, `patineta`, `senuelo` |
| Conserva sus Ascensiones y su multiplicador | `ascension.count` | El multiplicador se calcula con el catálogo a partir de `count` |
| Conserva sus Cerebros | `economy.wallet` | Moneda `cerebros`; la Ascensión no la reinicia |
| Conserva los perks comprados | `ascension.perks` | IDs `pies_de_rayo`, `sigilo_innato`, `capital_inicial`, `sangre_fria` |
| Conserva el álbum de graffitis | `album.designs` | 30 diseños normales + exclusivos de banda |
| Conserva cosméticos y distintivos | `cosmetics.owned`, `cosmetics.equipped` | Skins, auras, cintas, distintivo de Ascensión |
| Conserva misiones, racha y cartel en curso | `quests.daily`, `quests.weekly` | Hora del servidor (UTC) |
| Conserva el tiempo de entrenamiento AFK usado hoy | `training.dayStart`, `training.usedSeconds` | Tope diario; reinicia a las 00:00 UTC |
| El alijo calcula lo acumulado desde la última vez | `training.stashClaimedAt` | Se calcula al volver, con tope |
| Lo comprado con Robux no se pierde ni se entrega dos veces | `purchases.processed` | Los pases se consultan a Roblox (`UserOwnsGamePassAsync`), no se guardan |
| El tutorial no se repite | `progress.flags` | Bandera `tutorial_done` |
| Conserva estadísticas para misiones y logros | `stats.counters` | Arrestos, travesuras, derribos, rescates |

**No se promete ni se guarda:** el Botín sin depositar (se deposita al salir sin estrellas), estrellas y calor, policías activos, la banda (se arma en cada sesión), el estado del tutorial a medias, la posición y los cooldowns de herramientas y puntos de travesura.

## Dominios y dueños

| Sección | Dueño (core) | Qué guarda | Crecimiento |
| --- | --- | --- | --- |
| `meta` | `PlayerData` | Primera y última entrada, sesiones, tiempo de juego | Fijo |
| `progress` | `Progress` | Nivel, XP y banderas de hitos y onboarding | Hasta 40 banderas |
| `economy` | `Economy` | Saldo de `dinero` y `cerebros` | Hasta 4 monedas |
| `upgrades` | `Upgrades` | Nivel de cada mejora y herramientas compradas | 16 mejoras, 12 herramientas |
| `ascension` | `Ascension` | Ascensiones, perks y datos de la carrera actual | Fijo; 8 perks |
| `album` | `Mischief` | Diseños de graffiti desbloqueados | Hasta 80 diseños |
| `quests` | `Quests` | Misiones diarias con racha y cartel semanal | 6 misiones diarias activas |
| `training` | `Training` | Tiempo AFK usado hoy y alijo | Fijo |
| `cosmetics` | `Cosmetics` | Cosméticos y lo equipado | Hasta 150 cosméticos, 6 slots |
| `stats` | `Stats` | Contadores para misiones, logros y KPIs | Hasta 50 contadores |
| `purchases` | `Shop` | Recibos ya entregados | Los últimos 500 |

Cada sección la escribe solo su dueño. Por ejemplo, completar una travesura no toca `economy` desde `Mischief`: el core `Mischief` publica `completed` y el puente `Mischief_Economy` llama a `Economy.addLoot`. Cuando `Game` pasa el Botín a Dinero, solo `Economy` escribe `wallet`.

Los cores `Wanted`, `Cops` y `Band` no guardan nada: su estado es de sesión.

## Modelo de clases

```text
PlayerData (núcleo: carga, bloqueo, autosave, migraciones)
└── section(player, nombre) → Section (get, update, changed)
    ├── ProgressData   (core Progress)   level, addXp, hasFlag, setFlag
    ├── WalletData     (core Economy)    balance, add, spend
    ├── UpgradeData    (core Upgrades)   levelOf, setLevel, hasTool, grantTool, resetAll
    ├── AscensionData  (core Ascension)  count, perkLevel, setPerk, markSixStar
    ├── AlbumData      (core Mischief)   has, unlock
    ├── QuestData      (core Quests)     rollDay, progress, claim, streak, weeklyProgress
    ├── TrainingData   (core Training)   usedToday, addUsed, stashClaimedAt, claimStash
    ├── CosmeticData   (core Cosmetics)  owns, grant, equip, equippedIn
    ├── StatData       (core Stats)      increment, get
    └── (core Shop)        no tiene fachada: llama a PlayerData.grantPurchase desde ProcessReceipt
```

Cada fachada vive dentro de su core (`Modules/Quests/QuestData.luau`) y es la única que llama a `section(player, "quests")`. Eventos que publican los cores con esta información: `Progress.leveledUp`, `Economy.changed`, `Upgrades.changed`, `Ascension.ascended`, `Mischief.completed`, `Quests.claimed`, `Training.tick`, `Cosmetics.changed`.

## Secciones

### `meta`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `firstJoinAt` | time | 0 | — | Primera entrada |
| `lastJoinAt` | time | 0 | — | Última entrada |
| `sessions` | integer | 0 | ≥ 0 | Sesiones jugadas |
| `playTimeSec` | integer | 0 | ≥ 0 | Segundos jugados |

### `progress`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `level` | integer | 1 | 1–50 | Nivel del jugador |
| `xp` | integer | 0 | 0–100.000 | XP acumulada en el nivel actual |
| `flags` | map flagId → time | {} | 40 | `joined`, `first_mischief`, `first_star`, `first_escape`, `first_deposit`, `first_upgrade`, `first_level_up`, `tutorial_done`, `first_band`, `first_coop_mischief` y otros hitos |

### `economy`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `wallet` | map currencyId → integer | {} | 4 monedas, hasta 999.999.999.999 | Saldo de `dinero` y `cerebros` |

### `upgrades`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `levels` | map upgradeId → integer | {} | 16, valor 0–10 | Nivel de cada mejora; las de la Sala son `cinta` (1–10), `bateria` (1–5) y `gimnasio` (1–5) |
| `tools` | map toolId → time | {} | 12 | Herramientas compradas y fecha |

### `ascension`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `count` | integer | 0 | 0–10 | Ascensiones hechas |
| `perks` | map perkId → integer | {} | 8, valor 0–5 | Nivel de cada perk |
| `run.startedAt` | time | 0 | — | Inicio de la carrera actual |
| `run.reachedSixStar` | boolean | false | — | Alcanzó 6★ en esta carrera (+1 Cerebro al ascender) |

### `album`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `designs` | map designId → time | {} | 80 | Diseños de graffiti desbloqueados |

### `quests`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `daily.dayStart` | time | 0 | — | Inicio UTC del día de las misiones activas |
| `daily.streak` | integer | 0 | 0–3.650 | Racha de días con las 3 misiones completadas; se **pausa** si falta un día, no se pierde |
| `daily.lastCompletedDay` | time | 0 | — | Último día en que completó las 3 |
| `daily.active` | map questId → { progress, claimedAt } | {} | 6 | Misiones del día |
| `weekly.weekId` | string | "" | 12 caracteres | Semana del cartel Se Busca (por ejemplo `2026W44`) |
| `weekly.progress` | integer | 0 | 0–100.000 | Avance del cartel |
| `weekly.claimedAt` | time | 0 | — | Cuándo cobró el cartel |

### `training`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `dayStart` | time | 0 | — | Inicio UTC del día de `usedSeconds` |
| `usedSeconds` | integer | 0 | 0–86.400 | Segundos pagados hoy en la Sala |
| `stashClaimedAt` | time | 0 | — | Última vez que reclamó el alijo |

### `cosmetics`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `owned` | map cosmeticId → { grantedAt, source } | {} | 150 | Cosméticos; `source`: `shop`, `level`, `quest`, `gamepass`, `event` |
| `equipped` | map slot → cosmeticId | {} | 6 | Lo equipado por slot (skin, aura, cinta, etiqueta, estela, emote) |

### `stats`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `counters` | map statId → integer | {} | 50, hasta 999.999.999 | `mischief_total`, `arrests`, `cop_knockdowns`, `escapes`, `deposits`, `murals_painted`, `band_mischiefs`, `band_rescues`, `afk_seconds_total` |

**Logros (módulo `Achievements`): sin datos propios.** Cada logro es una meta sobre un contador de arriba (`escapes`, `stars5_reached`, `comisario_defeated`…), sobre el nivel más alto alcanzado (`progress.level`, o 50 si `ascension.count` > 0), sobre `ascension.count` o sobre el tamaño de `album.designs`. Por eso no cambian el esquema ni la versión (sigue en 1), no hay migración y un logro no se pierde con la Ascensión. Las parcelas del lobby y los viajes tampoco guardan nada: son estado de sesión.

### `purchases`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `processed` | map purchaseId → time | {} | 500 | Recibos ya entregados |

## Seguimiento del progreso

- **Banderas del onboarding:** `Telemetry.onboarding` se emite solo si la bandera no existía. Los pasos del funnel del GDD son banderas con los mismos nombres.
- **Mejoras:** un nivel por ID. Una mejora nueva es una clave nueva en `levels`, sin migración.
- **Misiones diarias:** `Quests.rollDay` compara `dayStart` con el inicio del día UTC; si pasó un día, descarta `active`, sortea tres del catálogo y, si el día anterior se completó, suma racha. Faltar un día no baja `streak`.
- **Ascensión:** es una operación de ejecución, no una migración. En **un solo tick sin esperas** `Ascension` suma `count`, `Economy` agrega los Cerebros, y se reinician `progress.level/xp`, `economy.wallet.dinero`, `upgrades.levels` y `upgrades.tools`; se conservan `cerebros`, `perks`, `album`, `cosmetics`, `quests`, `stats`, `flags` y `training`. Como todo es un solo documento, el guardado siguiente ve el cambio completo o no ve nada. Después de ascender, el servicio fuerza un guardado.
- **Alijo:** `Training.claimStash` calcula `min(ahora − stashClaimedAt, tope) × tasa` con la hora del servidor.
- **Sala AFK:** cada tick paga directo a `Economy` y suma a `usedSeconds`; no hay ganancia pendiente que guardar. Si el jugador se desconecta, el último tick ya está en el documento.

## Estado de sesión

Lo que no se guarda y quién lo tiene:

| Estado | Dueño | Nota |
| --- | --- | --- |
| Botín sin depositar | `Economy` (sesión) | Se deposita al salir sin estrellas; con estrellas se aplica la pérdida de arresto |
| Calor y estrellas, estado "Buscando" | `Wanted` | |
| Policías y su objetivo | `Cops` | |
| Banda, miembros, contagio de calor | `Band` | No se guarda; se arma en cada sesión |
| Travesura en curso, cooldowns de puntos y herramientas | `Mischief`, `Upgrades` | Cooldowns cortos |
| Check-in de la Sala, reto en curso y pausa | `Training` | Solo `usedSeconds` y `dayStart` persisten |
| Posición, personaje, UI | — | Se reconstruye al entrar |

## Ciclo de vida

- **Carga al entrar:** `PlayerData` carga con bloqueo de sesión y reintentos. Mientras carga, el jugador ve una pantalla corta de "Entrando a la ciudad" y no puede actuar.
- **Autosave:** cada 180 s si hubo cambios, al salir, al cerrar el servidor y justo después de una Ascensión o de una compra.
- **Salir:** si el jugador sale con estrellas, `Economy` aplica la pérdida de arresto al Botín antes del guardado; sin estrellas, lo deposita.
- **Carga fallida (`unavailable`):** el jugador puede jugar, pero no puede comprar, depositar ni guardar, y se le avisa; nunca se escribe un perfil que no cargó.
- **Un solo place:** el documento es de toda la experiencia.

## Migraciones

| Versión | Cambio | Operaciones |
| --- | --- | --- |
| 1 | Primera versión | — |

## Presupuesto

Tamaño máximo estimado por `check_data.py`: 49.215 caracteres en el peor caso (1,2 % del límite de 4.194.304 por clave); la sección que más pesa es `purchases`. Si el juego crece, lo primero que se ajusta es `purchases.processed` (hay que podar los recibos más viejos al llegar a 450) y `cosmetics.owned`.

## Fallos y recuperación

- Si un guardado falla, el servicio lo reintenta con el siguiente ciclo y no suelta el bloqueo; el jugador sigue jugando en memoria.
- Un perfil dañado se recupera con las versiones anteriores de la clave (30 días) desde Creator Hub; solo el dueño de la experiencia puede hacerlo.
- Las compras se registran en la misma escritura que el beneficio (`grantPurchase`); si el guardado falla, el recibo no se confirma y Roblox lo reenvía.

## Borrado y privacidad

No se guardan nombres de usuario, correos ni texto libre del jugador: los nombres de banda **no** se guardan. El UserId solo está en la clave `player_{UserId}`. Un pedido de borrado se cumple con la plantilla de borrado de Roblox sobre esa clave en el DataStore `PlayerData`, configurada por el dueño de la experiencia.

## Pruebas

En Studio con acceso a la API: entrar, salir y volver (nivel, Dinero, mejoras); carga fallida (no se puede comprar); cierre del servidor; Ascensión (resetea lo correcto y conserva Cerebros y perks); cambio de día UTC (misiones, tope de la Sala, racha pausada); reset con `DataDebug`. En una experiencia publicada: dos servidores con el mismo jugador, compra repetida del mismo recibo y reclamo del alijo.

## Pendientes

- data-architect → builder: crear los cores `Progress`, `Economy`, `Upgrades`, `Ascension`, `Quests`, `Training`, `Cosmetics`, `Stats` y `Shop` con sus secciones, y `Mischief` con la sección `album` (cerrado: creados con sus fachadas)
- data-architect → builder: copiar las plantillas del servicio de datos (`PlayerData`, `Session`, `Profile`, `Store`, `DataDebug`) sin cambios a `src/server/Data/` (cerrado)
- data-architect → builder: `Shop` poda los recibos más antiguos de `purchases.processed` al llegar a 450 (cerrado: lo hace `PlayerData.grantPurchase`, que borra el más viejo al llegar al límite)
- data-architect → builder: la Ascensión se aplica en un solo tick sin esperas y fuerza un guardado después (cerrado: `Reactions` llama a `PlayerData.save`)
