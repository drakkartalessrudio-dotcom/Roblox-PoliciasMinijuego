# Plantilla de GDD para la fábrica Roblox

Usa esta estructura al iniciar un juego desde una idea. Si el usuario trae otro formato, conserva su contenido y agrega solo los campos necesarios. Los valores de ejemplo describen la estructura, no decisiones obligatorias para todos los juegos.

Cada sección indica su dueño según el [contrato de la fábrica](factory-contract.md). Si el skill dueño no está instalado, el builder completa una versión mínima de la sección.

```yaml
---
project:
  name: NombreDelJuego
  mode: prototype # o release-candidate
  genre: obby # referencia principal: obby, simulator, tycoon, rounds, survival u otro
  places: 1 # o una lista de places: [{ id: vestibulo, role: start, maxPlayers: 30 }, { id: arena, role: match, maxPlayers: 12 }]
  platforms: [desktop, mobile] # solo plataformas objetivo: desktop, mobile, tablet, console, vr
design:
  levels: false # true: roblox-level-designer escribe design/LEVELS.md y src/shared/Levels.json
  art: false # true: roblox-art-director escribe design/ART.md y src/shared/Theme.json
  environment: false # true: roblox-environment-artist escribe design/ENVIRONMENT.md y src/shared/Environment.json (necesita levels y art)
  ui: false # true: roblox-ui-designer escribe design/UI.md y src/client/UI
  data: false # true: roblox-data-architect escribe design/DATA.md y src/server/Data/DataSchema.json
data:
  persistence: memory # o persistent (DataStore); la decide roblox-data-architect
monetization:
  enabled: [] # developer-products, game-passes, creator-rewards, avatar-ugc
analytics:
  enabled: false # true: instrumentar los KPIs objetivo con roblox-analytics-dev
liveops:
  enabled: false # true: operar eventos y ajustes en vivo con roblox-liveops; requiere persistencia
---
```

Los campos de `design` (salvo `levels`, que ya existía), `analytics` y `liveops` son opcionales: si faltan, valen `false`, y el juego se construye sin esos módulos. Si falta `data.persistence`, el juego no guarda nada entre sesiones (`memory`).

## Concepto

*Dueño: game designer.* Una frase que describa la fantasía del jugador y la acción principal. Hasta tres pilares de diseño que sirvan para decidir qué entra y qué no. Público objetivo y duración esperada de una sesión, si ya se conocen.

## Loop principal

*Dueño: game designer.*

1. El jugador entra y recibe un objetivo visible.
2. Realiza una acción con una decisión significativa.
3. Obtiene feedback, recompensa o una consecuencia.
4. Decide repetir, progresar, cambiar de actividad o salir.

Reemplaza estos pasos por el loop real. Define condiciones de progreso, victoria, pérdida, respawn e ingreso durante una partida.

## Onboarding

*Dueño: game designer.* Qué ve, qué hace y qué recibe el jugador nuevo en sus primeros 60 segundos. Lista los pasos del funnel de onboarding con un nombre estable en `snake_case` (por ejemplo `1 joined`, `2 first_action`, `3 first_reward`): el builder los emite con `Telemetry.onboarding` y la medición depende de esos nombres, así que no los cambies sin registrarlo.

## Progresión

*Dueño: game designer.* Metas de corto, medio y largo plazo; qué se desbloquea y cuándo; puntos naturales de salida y motivo para volver.

## Contenido y alcance

*Dueño: game designer.* Sistemas y contenido **MVP**. Sistemas **posteriores**. Cantidad inicial de niveles, mapas, rondas, NPCs o ítems cuando el diseño los necesite. Explica cómo funciona en solitario y con la población prevista, incluido el máximo de jugadores por servidor.

## Brief de niveles

*Dueño: game designer. Solo si `design.levels` es `true`.* Lista de niveles o mapas con objetivo, mecánica que introduce, dificultad buscada (1 a 10) y tiempo esperado; cadencia de checkpoints o puntos de reaparición; restricciones de tamaño o presupuesto. El level designer lo convierte en `design/LEVELS.md` y `src/shared/Levels.json`.

## Física y métricas del personaje

*Dueño: game designer.* Velocidad de marcha (`walkSpeed`), altura de salto (`jumpHeight`) y gravedad que el juego fija explícitamente; no dependas de los valores por defecto del place. Referencia habitual de Roblox: 16 studs/s, 7.2 studs y 196.2 studs/s². Si hay niveles, la fuente única de estos valores es `Levels.json` y esta sección explica la intención.

## Plataformas e interacción

*Dueño: game designer; el builder agrega detalles técnicos.* Controles, UI principal, navegación, accesibilidad básica y necesidades de touch/gamepad para las plataformas seleccionadas.

## Estado y economía

*Dueño: game designer.* Datos que se conservan, como una lista de promesas al jugador ("conserva sus monedas", "sigue desde el último checkpoint", "lo comprado con Robux no se pierde"): qué conserva entre sesiones y qué pasa si una carga falla; cómo se guarda lo decide el data architect en `design/DATA.md`. Datos temporales, monedas con su tabla de fuentes y sumideros, tiempo estimado hasta cada hito, límites y balance. Si no hay moneda o datos persistentes, indícalo.

## Parámetros ajustables

*Dueño: game designer; el builder agrega los parámetros técnicos que necesite.* Todos los números que alguien querría ajustar sin programar, en todos los juegos y no solo en los que tienen economía. El builder los copia a `src/shared/Config.luau` y el juego los lee con `Tuning.get`.

| Parámetro | Valor inicial | Uso |
| --- | --- | --- |
| `Round.Duration` | 60 | Segundos de cada ronda |

## Monetización seleccionada

*Dueño compartido: el game designer propone ofertas, beneficios y la hipótesis comercial; el módulo de cada clave completa el catálogo, el flujo y las pruebas.* Por cada clave de `monetization.enabled`, registra catálogo/beneficio o hipótesis de engagement, cómo se presenta, dependencias externas, IDs reales conocidos y pruebas de aceptación. Si los IDs faltan, marca cada oferta pendiente y mantén su compra desactivada.

## KPIs objetivo

*Dueño: game designer. El builder emite los eventos con `Telemetry`; roblox-analytics-dev los registra cuando `analytics.enabled` es `true`.*

| KPI | Definición | Objetivo inicial | Cómo se mide | Decisión si no se cumple |
| --- | --- | --- | --- | --- |
| Conversión del onboarding | Jugadores nuevos que completan el último paso del funnel en su primera sesión | Línea base o hipótesis explícita | Funnel de onboarding | Revisar los primeros 60 segundos |

Un objetivo sin datos previos es una hipótesis: márcalo como tal o escribe "medir línea base". No presentes cifras de la industria como hechos.

## Assets y servicios

*Dueño: builder; cada skill que usa un asset del usuario agrega su fila.* Assets aportados o verificados (modelos de `assets/models`, variantes de `assets/materials`, IDs de texturas, sonidos y animaciones), con origen, licencia y permisos; publicación y configuración requerida en Creator Hub. Separa dependencias disponibles de pendientes.

## Places y viajes

*Dueño: game designer; el builder agrega los detalles técnicos. Solo si `project.places` es una lista.* Qué tiene cada place (rol, jugadores, niveles o zonas) y una tabla de viajes: de qué place a cuál, cuándo, en qué tipo de servidor (público o reservado para el grupo), qué datos viajan (el progreso siempre por DataStore) y qué pasa si el viaje falla. Ver [varios places](multi-place.md).

## Arquitectura

*Dueño: builder.* Árbol de archivos y servicios. Orden de inicio. Remotes con dirección, payload y validación. Propiedad de las reglas entre servidor y cliente. Eventos de telemetría que emite cada sistema. Estrategia de datos y presupuestos de rendimiento relevantes.

### Mapa de módulos

Una fila por módulo core, puente y `Game`, con las columnas `Módulo`, `Capa` (`core`, `puente` o `main`), `Responsabilidad`, `API y eventos`, `Datos que posee`, `Excepción` (los cores de los que depende directamente, con el motivo, o `—`) y `Origen` (`librería <Nombre>@<versión>` o `propio`; ver [librería de módulos](module-library.md)). Reglas y ejemplo en [arquitectura de módulos](module-architecture.md#mapa-de-módulos).

### Estado para la UI

Atributos que escribe el servidor (de jugador o compartidos) con tipo, quién los escribe y significado, y remotes que la UI puede usar con su validación. La UI solo muestra este estado y envía intenciones.

## Suposiciones y criterios de aceptación

*Cada skill agrega las suyas.* Suposiciones hechas para completar vacíos. Casos observables que demuestran el loop, persistencia, multiplayer, UI y monetización elegida. Marca cualquier decisión que requiera información del usuario antes de activar una venta o publicar.

## Pendientes entre skills

*Todos.* Pedidos de un skill al dueño de otro artefacto, con el formato `origen → destino: pedido (estado)`. Por ejemplo: `level-designer → game-designer: el brief pide 12 niveles en 5 minutos; propongo 8 (abierto)`. Cierra cada pedido al resolverlo.
