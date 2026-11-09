# KPIs objetivo

Cómo elegir pocos indicadores que digan si el diseño funciona y qué cambiar si no. Verificado el 8 de octubre de 2026 contra la [documentación de Creator Analytics](https://create.roblox.com/docs/production/analytics).

## Principios

- **Pocos y ligados a decisiones.** Entre 3 y 6 KPIs. Si un número no cambiaría ninguna decisión, no es un KPI del juego.
- **Definición completa.** Qué se cuenta, sobre qué total (denominador) y en qué ventana de tiempo. "Retención" sin ventana no se puede comparar.
- **Diseñado no es observado.** El GDD contiene objetivos e hipótesis; los valores observados llegan después de publicar. No los mezcles.
- **Objetivos honestos.** Sin datos previos, escribe "medir línea base" o una hipótesis explícita con su razonamiento. No presentes cifras de la industria como hechos.

## Fuentes de datos

- **Creator Analytics** ya ofrece paneles de retención, engagement, monetización y adquisición, sin código adicional. Con 100 o más usuarios activos diarios ofrece comparativas con juegos similares: úsalas para calibrar objetivos cuando estén disponibles.
- **Eventos del juego**: funnels (onboarding y otros), progresión, economía y eventos propios. Los emite el servidor en momentos definidos del juego; cuando `analytics.enabled` es `true`, roblox-analytics-dev los implementa a partir de esta sección del GDD.

## Catálogo de KPIs

| KPI | Definición sugerida | Fuente | Decisión que informa |
| --- | --- | --- | --- |
| Conversión del onboarding | Jugadores nuevos que llegan al último paso del funnel de onboarding en su primera sesión, sobre los jugadores nuevos que entraron | Funnel de onboarding | Rediseñar los primeros 60 segundos |
| Abandono por paso | Porcentaje que no pasa de cada paso del funnel | Funnel de onboarding | Qué paso simplificar primero |
| Retención D1 y D7 | Jugadores nuevos de un día que vuelven 1 y 7 días después | Creator Analytics | Motivo de regreso y progresión |
| Duración de sesión | Tiempo medio por sesión | Creator Analytics | Ritmo y contenido de la sesión |
| Embudo de progresión | Porcentaje de jugadores que completa cada nivel o hito | Eventos de progresión | Dónde está el pico de dificultad |
| Salud de la economía | Moneda ganada y gastada por sesión; tiempo real hasta cada hito | Eventos de economía | Ajustar costos y recompensas |
| Conversión de compra | Compradores sobre jugadores activos, por oferta | Creator Analytics y el módulo de monetización | Solo si hay monetización activada |

## Cómo escribirlos en el GDD

| KPI | Definición | Objetivo inicial | Cómo se mide | Decisión si no se cumple |
| --- | --- | --- | --- | --- |
| Conversión del onboarding | Nuevos que llegan a `first_reward` en su primera sesión / nuevos que entraron | Medir línea base la primera semana | Funnel de onboarding | Acortar el camino hasta la primera recompensa |
| Progresión del nivel 1 | Jugadores que completan el nivel 1 / jugadores que lo empiezan | Hipótesis: la mayoría lo completa, porque enseña sin castigar | Eventos de progresión | Bajar la dificultad del nivel 1 |

Además de la tabla, deja listos los nombres que usará la medición: pasos del funnel de onboarding, nombre del camino de progresión (por ejemplo `Obby`) y nombres de cada moneda. Cambiarlos después rompe la comparación entre versiones.
