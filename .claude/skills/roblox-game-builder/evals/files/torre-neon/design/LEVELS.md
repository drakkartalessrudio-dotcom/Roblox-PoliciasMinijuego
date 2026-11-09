# Niveles de TorreNeon

Fuente: `GDD.md` (Brief de niveles). Datos: `src/shared/Levels.json`. Última validación: 2026-10-08, 0 errores, 0 advertencias.

## Métricas del personaje

| walkSpeed | jumpHeight | gravity | Alcance en plano | Subida útil | Salto cómodo (60 %) | Salto normal (80 %) |
| --- | --- | --- | --- | --- | --- | --- |
| 16 | 7.2 | 196.2 | 9.67 | 6.70 | 5.8 | 7.7 |

## Curva de dificultad

| # | id | Dificultad declarada | Saltos | Exigentes | Timing | Mecánica nueva |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | base | 2 | 3 | 0 | 0 | Subidas y escalera |
| 2 | ascensor | 3 | 5 | 0 | 2 | Plataforma vertical |

## Nivel por nivel

### base · Base de la torre

- **Intención:** subir con saltos cómodos y aprender a trepar.
- **Recorrido:** `inicio` → `p1` → `p2` (subidas de 1 y 2 studs) → `cp1` → `escalera` (trepar 10 studs) → `meta`.
- **Cristal:** `cristal-1` flota sobre `p1`; se toma al pasar.
- **Notas para el builder:** `escalera` es un TrussPart; la meta está sobre su extremo superior.

### ascensor · Ascensor de neón

- **Intención:** esperar el momento justo para subir.
- **Recorrido:** `entrada` → `elevador` (sube 12 studs y baja, ciclo de 8 s) → `alto` → `cp1` → `p3` → `meta`.
- **Cristal:** `cristal-2` sobre `cp1`.
- **Notas para el builder:** `elevador` tiene `motion` lineal vertical; `LevelLoader` lo mueve con física.

## Validación

`validate_levels.py`: 0 errores, 0 advertencias.
