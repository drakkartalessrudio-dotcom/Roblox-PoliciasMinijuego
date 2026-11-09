---
name: roblox-monetization-creator-rewards
description: Diseñar engagement y medir Creator Rewards de Roblox cuando el GDD selecciona ingresos por participación o captación. Aplica el programa vigente y distingue métricas del juego de recompensas calculadas por Roblox. También para preguntas sobre cómo funciona Creator Rewards aunque no haya GDD.
metadata:
  version: "1.2.0"
  last_verified: "2026-10-07"
---

# Monetización con Creator Rewards

Construye una experiencia a la que el jugador quiera volver y mide sus resultados. Roblox calcula las recompensas; el juego no concede ni reclama estos pagos por código.

## Integración y alcance

- Sigue el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md). Las secciones Onboarding, Progresión y KPIs del GDD son de [roblox-game-designer](../roblox-game-designer/SKILL.md): revísalas con los criterios de este módulo y, si el designer está instalado, propón los cambios con la regla de pendientes del contrato; si no, complétalas. El código lo escribe [roblox-game-builder](../roblox-game-builder/SKILL.md).
- Los eventos se emiten con `Telemetry` ([puntos de enganche](../roblox-game-builder/references/hooks.md)); no crees un sistema de eventos paralelo.
- Activa este módulo cuando `monetization.enabled` incluya `creator-rewards`, o cuando el usuario pida diseñar para ese programa; registra la selección en el GDD. Sin GDD, aplica sus reglas a la pregunta o al arreglo concreto.
- No agregues compras, pases, UGC ni anuncios por cargar este skill. Cada mecanismo adicional necesita su selección explícita en el diseño.
- No modifiques el loop aprobado solo para extender la duración. Propón cambios que agreguen decisiones, cooperación o contenido con valor para el jugador.

## Referencia vigente, no una constante de negocio

Verificado el **7 de octubre de 2026**: Creator Rewards sustituyó Engagement Based Payouts y Creator Affiliate; no es un pago lineal por horas Premium.

| Componente | Condiciones resumidas |
| --- | --- |
| Daily Engagement | 5 Robux por Active Spender/día cuando esta es una de sus primeras tres experiencias con al menos 10 minutos jugados ese día |
| Active Spender | Compras calificadas por al menos USD 9,99 en los últimos 60 días; excluye usuarios nuevos o reactivados durante ese período |
| Audience Expansion | 35% de los primeros USD 100 de compras calificadas durante 60 días, con atribución válida de usuario nuevo/reactivado y promedio de 100+ DAU durante los 60 días siguientes |
| Elegibilidad de expansión | Cuenta verificada, en buen estado y cuenta DevEx válida; comprobar el caso de propiedad por comunidad |
| Liquidación | Recompensas en Earned Robux con retención de 60 días; conversión a dinero sujeta a DevEx |

Esta tabla es una referencia fechada. Revisa las definiciones, atribución y condiciones completas antes de planificar ingresos o publicar. [Creator Rewards oficial](https://create.roblox.com/docs/creator-rewards).

## Diseño de sesiones

Revisa en las secciones Onboarding y Progresión del GDD la primera sesión, el motivo de regreso y las actividades posteriores a dominar el loop. El umbral del programa no impone una duración mínima artificial a una ronda.

- **Entrada:** el jugador entiende qué hacer y puede actuar sin esperar una explicación larga. Muestra el primer objetivo y una recompensa legible.
- **Progresión:** alterna objetivos cortos con una meta mayor; desbloquea decisiones o variaciones, en lugar de aumentar solamente tiempos de espera.
- **Repetición:** ofrece una siguiente actividad opcional y un punto natural para salir. Una partida breve puede formar parte de varias rondas voluntarias.
- **Interacción social:** si corresponde al género, facilita cooperación o roleplay con contenido que funcione también con poca población.
- **Regreso:** conserva progreso cuando sea parte del diseño. Define fechas y reinicios mediante el servidor; no castigues desproporcionadamente al jugador por perder un día.
- **Contenido:** usa combinaciones, mapas o desafíos que sostengan variedad dentro del presupuesto. No agregues un sistema de live ops si no hay capacidad para mantenerlo.

Trata los objetivos de duración y retención como hipótesis a probar, no como garantías. Si los jugadores abandonan por no entender el juego, corrige esa causa antes de alargarlo.

## Actividad auténtica

Roblox prohíbe actividad artificial, automatizaciones, manipulación de teleports y promoción de cuentas alternativas para conseguir recompensas. [Condiciones de Creator Rewards](https://create.roblox.com/docs/creator-rewards#what-terms-apply-to-creator-rewards).

No implementes anti-idle, bots, loops de reconexión ni incentivos para mantener una sesión vacía con el fin de generar ingresos. Si el género tiene mecánicas idle o AFK legítimas, documenta su función de juego; no prometas que ese tiempo calificará o incrementará recompensas.

No uses `MembershipType` ni compras de pases para inferir Active Spender. No existe en este diseño un API de juego que identifique toda la elegibilidad, orden de experiencias o gasto global del usuario. Tampoco muestres a jugadores una supuesta contribución monetaria individual al creador.

## Medición

Define qué eventos necesita la medición y en qué momento del servidor ocurren. Se emiten con `Telemetry` usando los nombres del GDD (pasos de onboarding, progresión y eventos propios):

| Evento o métrica | Uso |
| --- | --- |
| Ingreso y objetivo inicial completado | Detectar dónde se pierde la primera sesión |
| Primer loop completado y repetición voluntaria | Comprobar comprensión y deseo de seguir |
| Participación y salida por actividad | Identificar tiempos muertos y fricción |
| Duración por cohortes | Separar cambios de contenido de cambios de audiencia |
| Retención D1/D7 | Evaluar regreso con definiciones y ventanas consistentes |
| Progreso perdido o errores | Detectar problemas técnicos que afectan retorno |

Usa Creator Analytics para métricas disponibles y eventos propios solo para vacíos concretos. Si el juego activa `analytics.enabled`, [roblox-analytics-dev](../roblox-analytics-dev/SKILL.md) convierte lo que pidas aquí en eventos dentro de los límites de Roblox: este módulo decide qué medir para el programa y lo pide con la regla de pendientes. No escribas un DataStore por segundo ni recolectes datos sensibles para medir sesiones. El cliente puede aportar señales de UI; resultados de juego deben validarse en el servidor.

Las sesiones observadas por el juego no prueban recompensa. Consulta el panel **Monetization → Creator Rewards** para la atribución e ingresos reales. [Panel de recompensas](https://create.roblox.com/docs/creator-rewards#access-reward-data).

## Captación, si el GDD la requiere

Prepara la configuración de enlaces de atribución y una estrategia de llegada coherente con el juego. Compara adquisición, activación y regreso; no cuentes clicks como usuarios atribuidos ni como ingresos. Mantén campañas y publicación externa dentro de lo solicitado por el usuario.

Si la experiencia todavía no cumple requisitos de expansión, identifica esa dependencia y prioriza validar el juego. No construyas un panel que calcule una recompensa ficticia multiplicando visitantes por una tarifa.

## Pruebas de aceptación

- Un jugador nuevo entiende y completa el primer loop; puede continuar o salir en puntos naturales.
- El juego sigue funcionando solo, con pocos jugadores y con entrada durante una ronda.
- Salir y reingresar conserva el progreso prometido; fallos de carga no lo sobrescriben.
- Los eventos de onboarding se emiten una vez por intento definido, sin duplicación por respawn.
- Tiempo de sesión, participación y reconexiones siguen la definición documentada; actividad AFK no se etiqueta automáticamente como ingreso calificable.
- Las métricas de retención usan cohortes y denominadores explícitos; no se presentan como observadas antes de tener datos.
- Las pruebas locales de instrumentación no generan visitas o engagement artificial en producción.

## Entrega del agente

Incluye el mapa de primera sesión y regreso, instrumentación necesaria, definición de cohortes y un experimento concreto para la principal hipótesis de engagement. Documenta la elegibilidad pendiente y la fecha de revisión de reglas.

Separa en el informe datos observados, hipótesis y resultados de Roblox. Si no puedes revisar las fuentes vigentes, entrega el diseño e instrumentación y marca las proyecciones comerciales como pendientes de verificar.
