# Plantilla de `design/DATA.md`

Copia esta estructura en `design/DATA.md` del juego. Cada sección explica una decisión; el detalle de tipos y límites vive en `src/server/Data/DataSchema.json`, que es la fuente única.

```markdown
# Datos del jugador: <Juego>

Esquema: `src/server/Data/DataSchema.json` (versión <N>). Persistencia: `persistent` | `memory`. Clave: `player_{UserId}` en el DataStore `<store>`. Límites de Roblox verificados el <fecha>.

## Promesas del GDD

Qué promete conservar el GDD y dónde se guarda. Una fila por promesa de "Estado y economía".

| Promesa | Dónde se guarda | Notas |
| --- | --- | --- |
| El jugador conserva sus monedas | `economy.wallet` | Moneda `coins` |

## Dominios y dueños

| Sección | Dueño (core) | Qué guarda | Crecimiento |
| --- | --- | --- | --- |
| `meta` | `PlayerData` | Fechas, sesiones y tiempo de juego | Fijo |
| `economy` | `Economy` | Saldo por moneda | Una clave por moneda (hasta 10) |

## Modelo de clases

Cómo se usa en ejecución: el servicio de datos carga el documento y cada core lo lee y escribe por una fachada de su dominio.

PlayerData (núcleo) → section(player, "quests") → QuestData (fachada del core Quests) → Quests

Para cada fachada: qué funciones expone (`isCompleted`, `start`, `complete`…) y qué eventos publica su core.

## Secciones

Una tabla por sección:

| Campo | Tipo | Por defecto | Límite | Significado |
| --- | --- | --- | --- | --- |

## Seguimiento del progreso

Qué patrones se usan (banderas, máquina de estados de misiones, estadísticas) y cómo se emiten los eventos de `Telemetry` a partir de ellos (por ejemplo, `onboarding` solo si la bandera no existía).

## Estado de sesión

Lo que no se guarda y quién lo tiene en memoria (ronda actual, cooldowns, posición).

## Ciclo de vida

Carga al entrar (con reintentos y bloqueo de sesión), autosave, guardado al salir, al cerrar el servidor y antes de un viaje entre places. Qué ve el jugador mientras carga y si la carga falla (estado `unavailable`: no se juega con datos por defecto que sobrescriban el perfil real).

## Migraciones

| Versión | Cambio | Operaciones |
| --- | --- | --- |
| 1 | Primera versión | — |

## Presupuesto

Tamaño máximo estimado por `check_data.py` y la sección que más pesa. Qué límite (`maxEntries`) se ajustaría primero si el juego crece.

## Fallos y recuperación

Qué pasa si un guardado falla, cómo se recupera un perfil dañado (las versiones anteriores de la clave duran 30 días) y quién puede hacerlo.

## Borrado y privacidad

Qué datos personales no se guardan. Cómo se cumple un pedido de borrado: la plantilla de borrado de Roblox con la clave `player_{UserId}` en el DataStore `<store>`, configurada por el dueño de la experiencia.

## Pruebas

Qué probar en Studio con acceso a la API (entrar, salir y volver; carga fallida; cierre del servidor; reset con `DataDebug`) y en una experiencia publicada (dos servidores, viajes).

## Pendientes

Pedidos a otros skills, con el formato del contrato: `data-architect → builder: crear el core Inventory (abierto)`.
```

`check_data.py` comprueba que cada ruta de "Promesas del GDD" exista en el esquema y que cada sección aparezca en el documento.
