# Datos del jugador: ObbyEjemplo

Esquema: `src/server/Data/DataSchema.json` (versión 1). Persistencia: `persistent`. Clave: `player_{UserId}` en el DataStore `PlayerData`. Límites de Roblox verificados el 14 de octubre de 2026.

## Promesas del GDD

| Promesa | Dónde se guarda | Notas |
| --- | --- | --- |
| Al volver, el jugador sigue desde el último checkpoint que alcanzó | `obby.current` | Nivel por su `id` de `Levels.json` y número de checkpoint |
| Se guarda el mejor tiempo de cada nivel | `obby.levels` | En milisegundos |
| Se sabe si el jugador terminó el obby | `obby.finishedAt` | La primera vez |

## Dominios y dueños

| Sección | Dueño (core) | Qué guarda | Crecimiento |
| --- | --- | --- | --- |
| `meta` | `PlayerData` | Primera y última entrada, sesiones, tiempo de juego | Fijo |
| `obby` | `Obby` | Nivel y checkpoint actuales, mejor tiempo por nivel, cuándo terminó | Un registro por nivel (hasta 100) |

## Modelo de clases

```text
PlayerData (núcleo) → section(player, "obby") → ObbyData (fachada del core Obby) → Obby
```

`ObbyData` (`src/server/Modules/Obby/ObbyData.luau`) es el único archivo que usa la sección: `waitUntilReady`, `current`, `setCurrent`, `completeLevel`, `bestTime` y `finish`. Los tipos vienen de `src/shared/DataTypes.luau`, generado con `gen_types.py`.

## Secciones

### `meta`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `firstJoinAt` | time | 0 | — | Primera entrada |
| `lastJoinAt` | time | 0 | — | Última entrada |
| `sessions` | integer | 0 | ≥ 0 | Sesiones |
| `playTimeSec` | integer | 0 | ≥ 0 | Segundos jugados |

### `obby`

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |
| `current` | { levelId, checkpoint } | { "", 0 } | id de 32, checkpoint ≤ 100 | Dónde quedó; `""` si nunca avanzó |
| `levels` | map levelId → { completedAt, bestTimeMs } | {} | 100 niveles | Niveles completados y mejor tiempo |
| `finishedAt` | time | 0 | — | Cuándo terminó el obby por primera vez |

## Seguimiento del progreso

Los niveles se guardan por su `id` de `Levels.json` (`nivel-1`, `nivel-2`…), nunca por su posición: el level designer puede reordenar o agregar niveles sin migrar perfiles. Si un `id` guardado ya no existe, el jugador empieza desde el nivel 1.

## Estado de sesión

No se guarda: la etapa de leaderstats, los cooldowns de los peligros y el tiempo del nivel en curso.

## Ciclo de vida

`Bootstrap` llama a `PlayerData.start()` antes de construir el mundo. Al entrar, el jugador empieza en el nivel 1 sin guardar nada; cuando su perfil carga, `Obby` lo lleva al nivel y checkpoint guardados. Se guarda cada 180 segundos si hubo cambios, al salir y al cerrar el servidor. Si la carga falla, juega desde el nivel 1 y nada se guarda (atributo `DataStatus` en `unavailable`).

## Migraciones

| Versión | Cambio | Operaciones |
| --- | --- | --- |
| 1 | Primera versión | — |

## Presupuesto

`check_data.py` estima 9.706 caracteres en el peor caso (0,2 % del límite por clave).

## Fallos y recuperación

Un guardado fallido se reintenta en el próximo autosave. Las versiones anteriores de la clave duran 30 días.

## Borrado y privacidad

No se guardan datos personales. Para los pedidos de borrado: plantilla de borrado de Roblox con la clave `player_{UserId}` en el DataStore `PlayerData`.

## Pruebas

En Studio con acceso a las APIs (Game Settings → Security): llegar a un checkpoint del nivel 2, salir, volver y aparecer ahí; `DataDebug.reset(player)` para empezar de cero. Sin acceso a las APIs, `PlayerData` usa memoria y lo avisa en el Output.

## Pendientes

Ninguno.
