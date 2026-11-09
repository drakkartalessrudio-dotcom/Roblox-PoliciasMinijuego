# Plantilla de `design/LEVELS.md`

Copia esta estructura en `<Juego>/design/LEVELS.md` y reemplaza los ejemplos.

```markdown
# Niveles de <Juego>

Fuente: `GDD.md` (Brief de niveles). Datos: `src/shared/Levels.json`. Última validación: <fecha>, <N> errores, <N> advertencias.

## Métricas del personaje

| walkSpeed | jumpHeight | gravity | Alcance en plano | Subida útil | Salto cómodo (60 %) | Salto normal (80 %) |
| --- | --- | --- | --- | --- | --- | --- |
| 16 | 7.2 | 196.2 | 9.67 | 6.70 | 5.8 | 7.7 |

## Curva de dificultad

<Tabla que imprime validate_levels.py, con una columna extra de mecánica nueva>

| # | id | Dificultad declarada | Saltos | Exigentes | Timing | Uso máximo | Mecánica nueva |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | nivel-1 | 1 | 6 | 0 | 0 | 43 % | Saltar |

## Nivel por nivel

### nivel-1 · Primeros saltos

- **Intención:** qué aprende o demuestra el jugador.
- **Recorrido:** introducción, práctica, combinación y cierre, con los ids de las piezas clave.
- **Ritmo:** dónde están los descansos y los picos.
- **Riesgos justos:** por qué cada peligro se ve venir.
- **Notas para el builder:** piezas con comportamiento especial, nombres de zonas, lógica fuera del formato.

## Validación

<Resultado del validador. Cada advertencia que queda, con su justificación.>

## Suposiciones y pendientes

<Suposiciones propias y pedidos a otros skills con el formato del GDD: origen → destino: pedido (estado).>
```
