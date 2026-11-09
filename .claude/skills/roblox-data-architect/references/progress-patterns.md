# Patrones de progreso

Cómo guardar lo que un jugador hizo para que el juego pueda crecer sin migraciones constantes. La idea central viene del sistema de misiones de MyIsekai (UEFN): **el catálogo vive en el código y el perfil guarda IDs estables**. Agregar misiones, niveles o items no cambia el esquema.

## Patrones

| Qué | Cómo se guarda | Por qué |
| --- | --- | --- |
| Hitos y onboarding | `flags: map flagId → time` | La fecha dice si ya pasó y cuándo; un paso nuevo es un ID nuevo, no un campo nuevo. `Telemetry.onboarding` se emite solo si la bandera no existía |
| Niveles | `levels: map levelId → { completedAt: time, bestTimeMs: integer, stars: integer }` | El `id` de `Levels.json` es estable; el orden de los niveles puede cambiar |
| Checkpoint actual | `current: { levelId: string, checkpoint: integer }` | Solo si el GDD promete continuar donde se dejó |
| Misiones | `active: map questId → { startedAt, objectives: map objectiveId → integer }`, `completed: map questId → time` | Una máquina de estados por ID: disponible (no está), activa, completada. La facción, las recompensas y los requisitos salen del catálogo |
| Misiones que se repiten | `completed` guarda la última vez; el catálogo dice cada cuánto se repite | No hace falta un historial |
| Moneda | `wallet: map currencyId → integer (min 0)` | Una moneda nueva es una clave nueva. Cada cambio pasa por el core de economía y `Telemetry.economy` |
| Inventario apilable | `stacks: map itemId → integer` | Pociones, materiales |
| Items únicos | `items: map uid → { itemId, level, … }` | Cada copia tiene su estado; `uid` lo genera el servidor (`HttpService:GenerateGUID(false)`) |
| Equipado | `equipped: map slot → uid` | El slot es un ID (`"weapon"`, `"pet1"`) |
| Mejoras y nodos comprados | `upgrades: map upgradeId → integer` (nivel) | Un tycoon o un árbol de habilidades |
| Recompensa diaria | `daily: { streak: integer, lastClaimAt: time }` | Con la hora del servidor, nunca la del cliente |
| Estadísticas | `stats: map statId → integer` | Para logros y para los KPIs; un contador nuevo es una clave nueva |
| Logros | `achievements: map achievementId → time` | Igual que las banderas |
| Recibos de compras | `processed: map purchaseId → time` (rol `purchases`), con `maxEntries` alto | Hace idempotente `ProcessReceipt`: un recibo que ya está no se entrega dos veces |
| Derechos pagados | `owned: map key → { grantedAt: time, source: enum }` (rol `entitlements`) | Lo que se compró una vez y dura |
| Meta | `firstJoinAt`, `lastJoinAt`, `sessions`, `playTimeSec` (rol `meta`, dueño `PlayerData`) | Retención, cohortes y "primera vez" |

## Lo que se evita

Encontrado al revisar MyIsekai. Ninguno rompe el juego hoy; todos lo hacen más caro de cambiar.

| Antipatrón | Problema | En su lugar |
| --- | --- | --- |
| Un booleano por paso (`bIsTakenFirstMission`, `…Second…`, `…Third…`) | Cada paso nuevo cambia el esquema y suma código | `flags: map flagId → time` |
| Arreglos por posición (`Assistants[clase][id]`, rarezas por índice) | Insertar o reordenar corre todos los datos guardados | Mapas por ID estable |
| Un perfil general con campos de varios dominios (moneda, gacha y campos de otro juego) | El perfil crece con cada sistema y nadie sabe de quién es cada campo | Una sección por core, con dueño |
| Un constructor de copia escrito campo por campo | Un campo olvidado vuelve a su valor por defecto en cada guardado (en MyIsekai, `Version`) | El servicio completa los valores por defecto desde el esquema |
| Cada setter repite la rama de modo (single o coop) | Una rama invertida no guarda y nadie lo nota | Una sola vía de escritura: `section:update(fn)` |
| Escribir el almacenamiento directo desde un sistema | Se saltea el guardado coordinado y el bloqueo | Solo el servicio de datos toca `DataStoreService` |
| Guardar texto calculable (nombres, descripciones, precios del catálogo) | Se desincroniza con el catálogo | Guardar el ID y leer el resto del catálogo |
| Guardar marcas de tiempo del cliente | El jugador cambia la hora del dispositivo | `os.time()` del servidor |

## Qué no se guarda

- Lo que se reconstruye al entrar: la ronda actual, el personaje, el estado de la UI, cooldowns cortos.
- Lo que vive en otro lado: la posesión de un Game Pass (Roblox la responde con `UserOwnsGamePassAsync`), el nombre del jugador, sus amigos.
- Datos personales: el UserId ya está en la clave; no guardes nombres de usuario, correos ni texto libre del jugador.

## Por género

| Género | Secciones habituales |
| --- | --- |
| Obby | `levels` (mejor tiempo por nivel), `current` si se continúa, `stats` (muertes) |
| Simulador | `wallet`, `upgrades`, `pets` (únicos con `uid`), `equipped`, `stats`, `rebirths` |
| Tycoon | `wallet`, `upgrades` (nodos comprados por ID), `stats` |
| Rondas | `wallet`, `stats` (victorias, partidas), `owned` (cosméticos), sin estado de ronda |
| RPG con misiones | `quests`, `inventory`, `wallet`, `flags`, `daily`, `stats` |
| Supervivencia por oleadas | `stats` (mejor oleada), `wallet`, `owned`, sin estado de partida |

Con varios places, el documento es uno solo para toda la experiencia: cada place lee y escribe las mismas secciones.
