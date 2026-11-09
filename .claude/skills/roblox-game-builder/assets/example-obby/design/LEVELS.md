# Niveles de ObbyEjemplo

Fuente: `GDD.md` (Brief de niveles). Datos: `src/shared/Levels.json`. Última validación: 2026-10-08, 0 errores, 0 advertencias.

## Métricas del personaje

| walkSpeed | jumpHeight | gravity | Alcance en plano | Subida útil | Salto cómodo (60 %) | Salto normal (80 %) |
| --- | --- | --- | --- | --- | --- | --- |
| 16 | 7.2 | 196.2 | 9.67 | 6.70 | 5.8 | 7.7 |

## Curva de dificultad

| # | id | Dificultad declarada | Saltos | Exigentes | Timing | Uso máximo | Mecánica nueva |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | nivel-1 | 1 | 6 | 0 | 0 | 43 % | Salto plano y primera subida |
| 2 | nivel-2 | 3 | 7 | 0 | 0 | 68 % | Peligro sobre plataforma y diagonal |
| 3 | nivel-3 | 4 | 7 | 0 | 2 | 67 % | Plataforma móvil y barra giratoria |

## Nivel por nivel

### nivel-1 · Primeros saltos

- **Intención:** aprender a saltar sin miedo a perder progreso.
- **Recorrido:** tres saltos planos de 3 a 4 studs hasta `cp1`, luego dos subidas de 1 stud y la meta.
- **Ritmo:** todo el nivel es descanso; el uso máximo es 43 %.
- **Riesgos justos:** la lava está 11 studs debajo y es de `Neon` naranja: se ve desde el spawn.

### nivel-2 · Lava y ritmo

- **Intención:** combinar saltos más largos con un peligro sobre una plataforma.
- **Recorrido:** saltos de 5,5 studs; `p2` tiene una franja de lava de 2 studs en el medio que se cruza con un salto corto; después de `cp1`, una diagonal de 6,3 studs (`p4` → `p5`).
- **Ritmo:** `cp1` separa la parte de la franja de la diagonal.
- **Riesgos justos:** la franja es del mismo color que la lava del piso.

### nivel-3 · Plataforma móvil

- **Intención:** introducir el timing con una plataforma que se desplaza y una barra que gira.
- **Recorrido:** `movil` va y vuelve 16 studs en 6 segundos entre `p1` y `giro`; en `giro` (10 × 10) gira una barra de 9 studs a 8 rpm; las esquinas de `giro` quedan fuera de su alcance para esperar el momento. Después de `cp1`, dos subidas de 2 studs.
- **Ritmo:** el pico es `movil` + `giro`; el tramo final es más simple.
- **Riesgos justos:** la barra es `Neon` naranja, lenta y no colisiona (solo daña al tocarla, sin empujar).
- **Notas para el builder:** `movil` y `barra` tienen `motion`; `LevelLoader` las mueve con constraints y el servidor es dueño de su física.

## Validación

`validate_levels.py`: 0 errores, 0 advertencias. Los saltos hacia y desde `movil` son de timing: alcanzables en un extremo del recorrido de la plataforma.

## Suposiciones y pendientes

- Suposición: `edgeAllowance` de 1 stud es conservador para el personaje por defecto; confirmar en Studio.
