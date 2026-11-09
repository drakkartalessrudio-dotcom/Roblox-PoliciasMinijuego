# Niveles: Aldea de Gremios

Fuente: `GDD.md` (Brief de niveles). Datos: `src/shared/Levels.json`, validado con `validate_levels.py` (0 errores, 0 advertencias).

## Física

`walkSpeed` 16, `jumpHeight` 7.2, `gravity` 196.2: los valores habituales de Roblox. No hay saltos que validar.

## Nivel 1: Aldea (`aldea`, hub)

- **Intención:** un lugar tranquilo donde las dos zonas de los gremios se ven desde el punto de aparición.
- **Recorrido:** el jugador aparece en la plaza (`inicio`, al sur del centro). El bosque queda al noroeste y la mina al noreste, cada una a unos 40 studs; dos postes de color marcan la entrada a cada una.
- **Zonas** (`kind: "zone"`, invisibles y sin colisión; su significado lo da `ZoneName`):

| Pieza | `ZoneName` | Para qué |
| --- | --- | --- |
| `plaza` | `plaza` | Centro de la aldea; no cuenta para misiones |
| `bosque` | `bosque` | Objetivo `bosque` de las misiones de leñadores |
| `mina` | `mina` | Objetivo `mina` de las misiones de mineros |

- **Límites:** cuatro muros de 4 studs encierran el área de 100 × 100.
- **Presupuesto:** 8 piezas sólidas y 3 zonas.
