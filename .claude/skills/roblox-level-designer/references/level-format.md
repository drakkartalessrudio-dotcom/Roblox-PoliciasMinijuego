# Formato de niveles: `Levels.json` (schemaVersion 1)

`src/shared/Levels.json` describe los niveles del juego como datos. Rojo lo convierte en el ModuleScript `ReplicatedStorage.Shared.Levels`, que devuelve la misma estructura como tabla Luau (las listas empiezan en el índice 1). El builder construye las piezas a partir de él; el validador `scripts/validate_levels.py` lo revisa antes.

Ejemplo completo: [assets/levels.example.json](../assets/levels.example.json), un obby de tres niveles.

## Convenciones

- Unidades en studs; ángulos en grados.
- `position` es el **centro** de la pieza, relativo al `origin` de su nivel.
- `rotation` usa el mismo orden que `CFrame.Angles(rx, ry, rz)`. Con rotaciones que no son múltiplos de 90°, el validador solo puede aproximar los saltos.
- Los ids usan letras, números, `_` o `-`. Son estables: el código del juego y la medición pueden referirse a ellos.
- JSON no admite comentarios. La intención va en `LEVELS.md` o en el campo `note` de cada pieza.

## Raíz

| Campo | Obligatorio | Descripción |
| --- | --- | --- |
| `schemaVersion` | Sí | Siempre `1` en este formato |
| `physics` | Sí | `walkSpeed` (studs/s), `jumpHeight` (studs) y `gravity` (studs/s²). El juego los aplica explícitamente |
| `defaults` | No | `material` y `color` para las piezas que no los definen |
| `budget` | No | `maxParts`: piezas máximas antes de que el validador avise (por defecto 2000) |
| `validation` | No | Calibración del validador: `demandingRatio` (0.8; por encima, el salto es exigente), `onboardingRatio` (0.6; máximo en el primer nivel), `edgeAllowance` (1.0 stud que el personaje gana en los bordes), `heightMargin` (0.5 stud que se resta a la altura de salto) y `maxJumpsBetweenCheckpoints` (10) |
| `levels` | Sí | Lista de niveles, en el orden en que se juegan |

## Nivel

| Campo | Obligatorio | Descripción |
| --- | --- | --- |
| `id`, `name` | Sí | Identificador estable y nombre visible |
| `layout` | Sí | `linear` (recorrido con meta), `arena`, `hub`, `plots` o `free` |
| `difficulty` | En `linear` | Dificultad buscada, de 1 a 10, la del brief |
| `expectedSeconds` | No | Tiempo esperado para completarlo |
| `place` | Con varios places | Clave del place del GDD donde se juega el nivel; sin `place`, va al place de inicio. Cada place es un mundo aparte |
| `origin` | No | Desplazamiento del nivel; por defecto `[0, 0, 0]` |
| `start` | Sí | Id de la pieza donde el jugador entra al nivel y reaparece si no tocó checkpoints. Debe ser `spawn`, `platform` o `checkpoint` |
| `path` | En `linear` | Ids en el orden en que se recorren, empezando por `start`. Solo `spawn`, `platform`, `checkpoint`, `goal` o `truss` |
| `pieces` | Sí | Lista de piezas |

## Pieza

Campos comunes:

| Campo | Obligatorio | Descripción |
| --- | --- | --- |
| `id`, `kind` | Sí | Id único en el nivel y tipo (tabla siguiente) |
| `position`, `size` | Sí | `[x, y, z]`; cada eje de `size` entre 0 y 2048 |
| `rotation` | No | `[rx, ry, rz]` en grados |
| `material`, `color`, `transparency` | No | Nombre de `Enum.Material`, color `#RRGGBB` y transparencia de 0 a 1 |
| `shape` | No | `Block`, `Ball` o `Cylinder` (no se aplica a `spawn` ni `truss`) |
| `collide` | No | Sobrescribe si la pieza bloquea el paso |
| `motion` | No | Movimiento; ver abajo. Solo en `platform`, `hazard`, `wall` y `prop` |
| `note` | No | Intención de diseño; el juego la ignora |

## Tipos de pieza

| `kind` | Qué significa en el juego | Campos propios |
| --- | --- | --- |
| `spawn` | Lugar donde aparecen los jugadores al entrar al juego | `enabled` (por defecto `true`); `false` lo deja como punto de aparición que usa la lógica del juego, por ejemplo al empezar una ronda |
| `platform` | Superficie para pararse | — |
| `checkpoint` | Al tocarlo, el jugador reaparece ahí si muere | `order`: entero desde 1, único y consecutivo en el nivel |
| `goal` | Al tocarlo, se completa el nivel | — |
| `truss` | Escalera trepable (TrussPart). Mide 2 × 2 × N studs, con N par de 2 a 512; Roblox cambia cualquier otro tamaño | — |
| `wall` | Bloquea el paso; no se recorre | — |
| `hazard` | Daña al tocarlo. Sin `damage`, mata (convención de la fábrica) | `damage` (opcional, para peligros que no matan) |
| `collectible` | Se recoge al tocarlo; no bloquea | `value` (opcional) |
| `zone` | Volumen invisible que la lógica del juego usa (lobby, parcela, área de monedas) | `name` (obligatorio) |
| `prop` | Decoración | — |

## Movimiento

```json
{ "type": "linear", "offset": [0, 0, -16], "period": 6 }
```

Va y vuelve entre `position` y `position + offset`; `period` son los segundos de una ida y vuelta completa. El juego mueve la pieza con física para que arrastre a los jugadores que están encima.

```json
{ "type": "spin", "axis": "Y", "rpm": 8 }
```

Gira sobre su centro alrededor del eje del mundo indicado. Úsalo para barras y molinos peligrosos, con `collide: false`. El validador no evalúa saltos hacia o desde piezas giratorias; quedan para probar en Studio.

## Qué valida el script

- Estructura y tipos de todos los campos, ids únicos y referencias de `start` y `path`. Tamaño de los `truss`.
- Al menos un `spawn` habilitado (aviso si hay varios: cada jugador aparece en uno al azar). Con varios places, por place.
- Checkpoints con `order` único y consecutivo, y dentro del recorrido.
- `spawn`, `checkpoint` y `goal` que se superponen con un peligro (error) o lo tocan (aviso).
- Cada salto del recorrido: imposible (error), exigente (aviso), timing con piezas móviles, escaleras y piezas giratorias sin validar.
- Destinos que quedan sobre el origen en planta (avisa: la cabeza puede chocar al saltar).
- Saltos incómodos en el primer nivel, demasiados saltos sin checkpoint, falta de un peligro debajo del área del recorrido, niveles superpuestos (solo dentro del mismo place) y presupuesto de piezas.
