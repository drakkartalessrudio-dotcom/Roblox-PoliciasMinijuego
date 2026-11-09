---
project:
  name: ObbyEjemplo
  mode: prototype
  genre: obby
  places: 1
  platforms: [desktop, mobile]
design:
  levels: true
  art: true
  environment: true
  ui: true
  data: true
data:
  persistence: persistent
monetization:
  enabled: []
analytics:
  enabled: false
liveops:
  enabled: false
---

# ObbyEjemplo

Juego de ejemplo de la fábrica: muestra cómo se unen el GDD, los niveles como datos y los puntos de enganche del builder. Es pequeño a propósito.

## Concepto

Un obby sobre lava en tres niveles cortos: el jugador salta de plataforma en plataforma hasta la meta de cada nivel. Público general; sesiones de 3 a 5 minutos.

Pilares:

1. **Saltos legibles:** cada salto se puede medir con la vista antes de intentarlo.
2. **Error barato:** caer cuesta pocos segundos gracias a checkpoints y lava cercana.
3. **Progreso visible:** el jugador siempre sabe en qué nivel y checkpoint está.

## Loop principal

1. Aparece en la plataforma inicial y ve el objetivo en pantalla.
2. Salta hacia la siguiente plataforma, eligiendo cuándo y desde dónde saltar.
3. Si toca la lava, reaparece en el último checkpoint; si llega a un checkpoint, lo guarda.
4. Al tocar la meta pasa al siguiente nivel; tras el tercero, el obby queda completo.

Ingreso tardío: cada jugador avanza por su cuenta, así que entrar con otros jugadores ya en curso no cambia nada.

## Onboarding

En los primeros segundos el jugador lee "Salta de plataforma en plataforma y evita la lava" y tiene un salto de 3 studs delante. El primer checkpoint está a tres saltos cómodos. El nivel 1 no tiene saltos de más del 60 % de la capacidad.

Funnel: `1 joined`, `2 first_checkpoint`, `3 level_1_complete`.

## Progresión

Tres niveles con dificultad 1, 3 y 4: saltos básicos, peligros sobre plataformas y diagonales, y por último plataforma móvil y barra giratoria. Al terminar, el HUD lo celebra. Motivo para volver: ninguno en este prototipo (posterior).

## Contenido y alcance

MVP: 3 niveles, checkpoints, lava, plataforma móvil, barra giratoria, HUD de progreso y leaderstats "Etapa". Máximo 10 jugadores por servidor.

Posterior: guardar progreso, tabla de tiempos, más niveles, cosméticos.

## Brief de niveles

| # | Objetivo | Mecánica nueva | Dificultad | Tiempo esperado |
| --- | --- | --- | --- | --- |
| 1 | Aprender a saltar | Salto plano y primera subida | 1 | 40 s |
| 2 | Lava y ritmo | Peligro sobre plataforma y salto en diagonal | 3 | 60 s |
| 3 | Plataforma móvil | Plataforma que se desplaza y barra giratoria | 4 | 75 s |

Un checkpoint por nivel y lava debajo de todo el recorrido. Los niveles están en `design/LEVELS.md` y `src/shared/Levels.json`.

## Física y métricas del personaje

walkSpeed 16, jumpHeight 7.2 y gravity 196.2, aplicados explícitamente por `LevelLoader`. Fuente única: `Levels.json`.

## Plataformas e interacción

PC: WASD y espacio. Móvil: joystick y botón de salto de Roblox. El HUD usa las zonas seguras de pantalla y texto escalado.

## Estado y economía

Sin moneda. Se conserva dónde quedó cada jugador (nivel y checkpoint) y su mejor tiempo en cada nivel: al volver, sigue desde el último checkpoint que alcanzó. Si la carga del perfil falla, juega desde el nivel 1 y nada se guarda. El detalle está en `design/DATA.md`.

## Parámetros ajustables

| Parámetro | Valor inicial | Uso |
| --- | --- | --- |
| `Hazards.Damage` | 100 | Daño de un peligro sin daño propio; 100 mata al personaje por defecto |
| `Hazards.TouchCooldown` | 0.5 | Segundos entre daños del mismo peligro al mismo jugador |
| `Respawn.Time` | 1.5 | Segundos entre morir y reaparecer |
| `Respawn.HeightOffset` | 3 | Studs sobre el checkpoint donde reaparece el personaje |
| `Hud.HintText` | "Salta de plataforma en plataforma y evita la lava" | Mensaje inicial |
| `Hud.HintSeconds` | 8 | Duración del mensaje inicial |

## Monetización seleccionada

Ninguna (`monetization.enabled: []`).

## KPIs objetivo

| KPI | Definición | Objetivo inicial | Cómo se mide | Decisión si no se cumple |
| --- | --- | --- | --- | --- |
| Conversión del onboarding | Jugadores nuevos que llegan a `level_1_complete` / jugadores nuevos que entraron | Medir línea base | Funnel de onboarding | Acortar o facilitar el nivel 1 |
| Progresión por nivel | Jugadores que completan cada nivel / jugadores que lo empiezan, camino `Obby` | Hipótesis: el nivel 1 lo completa la mayoría | Eventos de progresión | Revisar el salto con más muertes del nivel |
| Muertes por nivel | Eventos `death` por nivel / jugadores que lo empiezan | Medir línea base | Evento propio `death` | Buscar el obstáculo injusto |

## Assets y servicios

Sin assets externos ni IDs: todo se construye con Parts. Sin servicios publicados. Estilo visual en `design/ART.md` y `src/shared/Theme.json` ("Noche volcánica").

## Arquitectura

```text
src/shared/          Config.luau (ajustes), Tuning.luau (lectura de ajustes), Signal.luau (eventos entre módulos), DataTypes.luau (tipos del perfil, generados), Levels.json (niveles),
                     Theme.json (tema), Style.luau (lectura del tema), Environment.json (pase de arte)
src/server/          Bootstrap.server.luau (entrada), LevelLoader.luau (mundo), EnvironmentLoader.luau (pase de arte), Telemetry.luau (eventos)
src/server/Data/     PlayerData.luau y su servicio (plantillas de roblox-data-architect), DataSchema.json, Migrations.luau
src/server/Modules/  Obby/ (core: reglas del obby; ObbyData.luau es la fachada de su sección del perfil)
src/server/Game/     init.luau (composición: configura y arranca Obby)
src/client/          UI/ (interfaz: kit de la fábrica y pantallas Hud y Help; dueño: UI designer)
```

Orden de inicio: `PlayerData.start` (empieza a cargar los perfiles) → `LevelLoader.applyPhysics` → `LevelLoader.build` → `EnvironmentLoader.apply` (iluminación, aspecto de las piezas, decoración, terreno y luces) → `Game.start` → `Obby.init` con los niveles construidos → `Obby.start` (conecta peligros, checkpoints y metas; atiende jugadores ya presentes).

### Mapa de módulos

| Módulo | Capa | Responsabilidad | API y eventos | Datos que posee | Excepción |
| --- | --- | --- | --- | --- | --- |
| `Obby` | core | Peligros, checkpoints, metas, leaderstats y telemetría del recorrido | `init({ built, physics })`, `start()`; `levelCompleted(player, nivel)`, `finished(player, segundos)` | `obby` | — |
| `Game` | main | Configura y arranca `Obby` con el mundo que construye Bootstrap | `start({ built, physics })` | — | — |

Sin RemoteEvents: el cliente no envía nada. El servidor publica el estado en atributos del jugador y en leaderstats.

### Estado para la UI

| Atributo del jugador | Tipo | Lo escribe | Significado |
| --- | --- | --- | --- |
| `Level` | número | `Obby` | Nivel actual, desde 1 |
| `LevelCount` | número | `Obby` | Cantidad de niveles |
| `Checkpoint` | número | `Obby` | Último checkpoint del nivel actual (0 si ninguno) |
| `Finished` | booleano | `Obby` | El jugador terminó el obby |
| `DataStatus` | texto | `PlayerData` | `loading`, `ready` o `unavailable`: si el progreso se está cargando o no se puede guardar |

La UI no envía acciones al servidor. Peligros, checkpoints y metas se validan en el servidor: jugador vivo, nivel actual y checkpoints solo hacia adelante.

Telemetría: `onboarding` en entrada, primer checkpoint y nivel 1 completo; `progressionStart` y `progressionComplete` por nivel; `custom` para `death` y `obby_finished`.

Presupuesto: 28 piezas de nivel y 193 de decoración (ver `design/ENVIRONMENT.md`); dos piezas con física (plataforma móvil y barra).

## Suposiciones y criterios de aceptación

- Suposición: un jugador que cae a la lava pierde todo el nivel desde el último checkpoint, no desde el inicio.
- Al morir, el jugador reaparece sobre su último checkpoint del nivel actual.
- La plataforma móvil lleva al jugador de un lado al otro del hueco sin que se resbale.
- Tocar la meta de un nivel lleva al inicio del siguiente y actualiza el HUD y la Etapa.
- Dos jugadores avanzan de forma independiente.

## Pendientes entre skills

Ninguno.
