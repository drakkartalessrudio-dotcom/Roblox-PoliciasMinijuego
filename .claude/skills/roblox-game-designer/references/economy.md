# Economía del juego

Cómo diseñar monedas, costos y recompensas para que el progreso se sienta constante, sin muros ni inflación. Úsalo cuando el juego tenga una moneda, un recurso acumulable o mejoras con costo.

## 1. Monedas

Para cada moneda define nombre, cómo se obtiene, en qué se gasta, si se conserva entre sesiones y si se puede **comprar con Robux**. Una moneda comprable con Robux que permite obtener premios aleatorios queda sujeta a la política de aleatoriedad pagada, aunque también se gane jugando; el módulo de Developer Products tiene las reglas. Si una sola moneda alcanza, usa una sola.

## 2. Fuentes y sumideros

| Fuente | Cantidad | Frecuencia | Condición | Límite |
| --- | --- | --- | --- | --- |
| Moneda recogida | 1 | ~20 por minuto en la zona 1 | Tocarla | Reaparece cada 10 s |

| Sumidero | Costo | Qué da | ¿Repetible? | Se desbloquea |
| --- | --- | --- | --- | --- |
| Mejora de velocidad nivel n | 50 × 1,4ⁿ | +1 de velocidad | Sí, hasta nivel 10 | Desde el inicio |

Cada fuente ilimitada necesita al menos un sumidero repetible o un tope; si no, el dinero se acumula, los precios dejan de importar y las decisiones desaparecen.

## 3. Tiempo hasta cada hito

Estima el ingreso por minuto en cada etapa del juego y calcula `tiempo = costo / ingreso por minuto` para los hitos importantes.

| Hito | Costo | Ingreso por minuto en ese momento | Minutos | Acumulado |
| --- | --- | --- | --- | --- |
| Primera mejora | 50 | 20 | 2,5 | 2,5 |
| Zona 2 | 1000 | 120 | 8,3 | 10,8 |

Qué revisar en la tabla:

- La **primera compra** llega dentro de la primera sesión, idealmente en los primeros minutos: es parte del onboarding.
- Los intervalos crecen de forma gradual. Un salto brusco (de 3 a 30 minutos entre hitos seguidos) es un muro: el jugador deja de ver progreso.
- Después del último sumidero hay algo que hacer: reinicio con ventaja (rebirth), coleccionables o metas sociales. Si no, la economía termina antes que el juego.

Estas cifras son estimaciones de diseño: márcalas como tales en el GDD y ajústalas con datos reales.

## 4. Curvas de costo

Un costo exponencial (`costo_n = base × factor^n`) mantiene relevante cada mejora mientras el ingreso crece. Un factor entre 1,1 y 1,5 por nivel es un punto de partida habitual; factores altos generan muros rápido. Elige el factor mirando la tabla de tiempos, no al revés.

Combina con mejoras de ingreso para que el tiempo entre compras crezca despacio. Si el ingreso crece linealmente y el costo exponencialmente, la brecha se abre rápido.

## 5. Multiplicadores

Escribe la regla de apilamiento: se suman (`1 + 0,5 + 1 = 2,5`), se multiplican (`1,5 × 2 = 3`) o se toma el mayor. Define un tope si hace falta. La misma regla aplica a mejoras, eventos y beneficios pagados, y la descripción que ve el jugador debe coincidir con el cálculo. Los multiplicadores que se multiplican entre sí rompen la economía rápido.

## 6. Tiempo fuera del juego

Las recompensas por regresar no deben castigar la ausencia: perder una racha por faltar un día suele expulsar jugadores. Si hay ganancias mientras el jugador no está, ponles tope y calcúlalas en el servidor con la hora del servidor.

## 7. Parámetros para el builder

Lleva los valores de la economía a la sección "Parámetros ajustables" del GDD, con nombres que el builder pueda usar en `Config.luau`:

| Parámetro | Valor inicial | Uso |
| --- | --- | --- |
| `Economy.CoinValue` | 1 | Monedas por moneda recogida |
| `Upgrades.Speed.BaseCost` | 50 | Costo del nivel 1 |
| `Upgrades.Speed.CostFactor` | 1,4 | Crecimiento por nivel |

Todos los números que un diseñador querría ajustar deben estar en esta tabla; nada ajustable queda escrito solo en el texto.
