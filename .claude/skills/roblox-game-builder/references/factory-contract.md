# Contrato de la fábrica

Cómo cooperan los skills de roblox-factory sobre un mismo juego. Cada skill escribe solo sus artefactos, lee los de los demás y deja un pedido en el GDD cuando necesita cambiar algo ajeno. Así varios skills pueden trabajar sobre el mismo proyecto sin deshacer el trabajo de otro.

## Skills y activación

El frontmatter de `GDD.md` decide qué skills participan. Carga solo los activados.

| Skill | Se activa cuando | Estado |
| --- | --- | --- |
| `roblox-game-builder` | Siempre que haya que construir, ampliar o arreglar el juego | Disponible |
| `roblox-game-designer` | El pedido parte de una idea sin GDD, o pide revisar loop, economía, progresión u onboarding | Disponible |
| `roblox-data-architect` | `design.data: true`, o el usuario pide guardar progreso, cambiar o migrar lo que se guarda, o revisar por qué se pierden datos | Disponible |
| `roblox-art-director` | `design.art: true`, o el usuario pide definir o cambiar cómo se ve el juego | Disponible |
| `roblox-level-designer` | `design.levels: true` | Disponible |
| `roblox-environment-artist` | `design.environment: true` (necesita `design.levels` y `design.art`), o el usuario pide decorar o ambientar los niveles | Disponible |
| `roblox-ui-designer` | `design.ui: true`, o el usuario pide crear o rehacer la interfaz | Disponible |
| `roblox-monetization-<clave>` | La clave está en `monetization.enabled` | Disponible |
| `roblox-analytics-dev` | `analytics.enabled: true`, o el usuario pide medir | Disponible |
| `roblox-liveops` | `liveops.enabled: true`, o el usuario pide eventos o ajustes en vivo | Disponible |

Un campo ausente vale `false` o `[]`. Si el usuario pide expresamente un sistema que el frontmatter no activa, actualiza el frontmatter antes de construir (ver la excepción en la tabla de dueños).

## Dueños de los artefactos

Un artefacto tiene un único dueño: el skill cuyas reglas lo gobiernan. Cuando un agente trabaja con un skill, escribe solo los artefactos de ese skill.

| Artefacto | Dueño | Lo leen |
| --- | --- | --- |
| `GDD.md`: frontmatter y secciones de diseño, incluida Parámetros ajustables | game designer (builder si no está instalado) | Todos |
| `GDD.md`: Monetización seleccionada | El game designer propone ofertas y beneficios; el módulo de cada clave completa el catálogo (key, ID real o "pendiente"), el flujo y las pruebas | Builder |
| `GDD.md`: Assets y servicios, Arquitectura (incluida Estado para la UI) | Builder; cada skill que usa un asset del usuario agrega su fila en Assets y servicios | Todos |
| `GDD.md`: Places y viajes (con varios places) | Game designer decide los places y los viajes; el builder agrega servidores, datos y fallos | Todos |
| `design/DATA.md`, `src/server/Data/DataSchema.json`, `src/server/Data/Migrations.luau`, `src/shared/DataTypes.luau` (generado con `gen_types.py`) y la clave `data` del frontmatter | Data architect | Builder, monetización, LiveOps, analíticas |
| `src/server/Data/PlayerData.luau`, `Session.luau`, `Profile.luau`, `Store.luau`, `DataDebug.luau` | Data architect (plantillas que el builder copia sin cambios) | Todos los cores, por su fachada |
| `src/<lado>/Modules/<Core>/<Core>Data.luau` (fachada de la sección de cada core) | Builder | Su core |
| `library.lock.json` y las copias de módulos de la [librería](module-library.md) (sin cambios locales) | Builder, con `library.py` | Todos |
| `design/ART.md`, `src/shared/Theme.json` | Art director | Todos |
| `design/LEVELS.md`, `src/shared/Levels.json` (incluido el `place` de cada nivel) | Level designer | Builder |
| `design/ENVIRONMENT.md`, `src/shared/Environment.json` | Environment artist | Builder |
| `assets/` (`reference/`, `models/`, `materials/`, `ASSETS.md`): referencias y assets propios | Usuario; los skills los leen y no los modifican | Art director, environment artist |
| `design/UI.md`, `src/client/UI/` (el kit `Kit/` se copia sin cambios de su plantilla) | UI designer | Builder |
| `src/shared/Config.luau`, `src/server/ServerConfig.luau` | Builder, con los valores que fija el GDD | Todos |
| `src/shared/Tuning.luau`, `src/server/Telemetry.luau`, `src/server/LevelLoader.luau`, `src/shared/Style.luau`, `src/server/EnvironmentLoader.luau`, `src/shared/Place.luau`, `src/server/Travel.luau`, `src/shared/Signal.luau` | Builder, copiados de sus plantillas sin cambiar la API ([puntos de enganche](hooks.md)) | Todos |
| `src/<lado>/Modules/`, `src/<lado>/Bridges/`, `src/<lado>/Game/` y el Mapa de módulos de la Arquitectura | Builder, con las capas de la [arquitectura de módulos](module-architecture.md) | Todos |
| `src/shared/Places.json`, `places/*.project.json` (con varios places) | Builder, con los places del GDD; los PlaceId los carga el usuario | Todos |
| Resto de `src/` (con `design.ui`, salvo `src/client/UI/`), `default.project.json`, `README.md`, `build/` | Builder | — |
| Servicios de compra (recibos, privilegios, catálogo) | Reglas del módulo de monetización correspondiente; el código lo escribe el builder dentro de su servicio de datos | Builder |
| `design/ANALYTICS.md`, `src/server/AnalyticsSchema.json`, `src/server/Analytics.luau` (plantilla con la misma API que `Telemetry`) | Analytics dev | Builder, LiveOps |
| `design/LIVEOPS.md`, `src/server/LiveSchema.json`, `src/shared/LiveConfig.luau` (plantilla con `getOverride` para `Tuning`) | LiveOps | Builder |

"Pendientes entre skills", "Suposiciones y criterios de aceptación" y las filas de assets del usuario en "Assets y servicios" son compartidas: cada skill agrega sus entradas sin borrar las de otros. Un asset del usuario se usa solo con su origen y licencia declarados; ningún skill inventa, busca ni baja assets.

**Excepción del frontmatter:** cualquier skill puede activar en el frontmatter un módulo que el usuario pidió expresamente, o desactivar uno cuyo skill no está instalado, y lo registra en Pendientes como cerrado. La clave `data` (`data.persistence`) es del data architect. Cualquier otro cambio del frontmatter es del game designer.

## Orden de trabajo

Para un juego nuevo:

1. **Game designer:** crea `GDD.md` con frontmatter, diseño (incluido qué se conserva entre sesiones), KPIs y brief de niveles.
2. **Data architect** (si `design.data`): `DATA.md`, `DataSchema.json`, `Migrations.luau` y `DataTypes.luau`. Todavía no hay Mapa de módulos: nombra el core dueño de cada sección y deja el pedido al builder para crearlo. La sección de un core que vendrá de la [librería](module-library.md) se toma de su `data/section.json` con `library_section.py`.
3. **Art director** (si `design.art`): estilo visual en `ART.md` y tokens en `Theme.json`.
4. **Level designer** (si `design.levels`): niveles como datos y su validación.
5. **Environment artist** (si `design.environment`): pase de arte de esos niveles con el tema, sin cambiar la geometría jugable.
6. **Módulos de monetización** seleccionados: completan en el GDD el catálogo, los flujos y las pruebas. No escriben código propio en este paso.
7. **Builder:** arquitectura en capas (con los cores dueños de las secciones de datos en el Mapa de módulos; antes de escribir un core o un puente, lo busca en la librería), código (incluidos el servicio de datos copiado, la fachada de cada sección y los servicios de compra, con las reglas de cada módulo), Estado para la UI, build y verificación.
8. **UI designer** (si `design.ui`): `UI.md` y las pantallas sobre el estado que publicó el builder. Puede escribir `UI.md` antes, desde el GDD, y pedir el estado que falte.
9. **Analytics dev** y **LiveOps** (si están activados): instrumentación y operación. Después, el builder vuelve a verificar el proyecto.

Para un cambio parcial, empieza por el dueño de lo que cambia y sigue la cadena solo hacia abajo. El skill [roblox-factory](../../roblox-factory/SKILL.md) tiene la guía de recorridos por tipo de pedido, el modo rápido para prototipos y un script que muestra el estado de cada etapa. Ajustar un nivel pasa por el level designer y luego por la verificación del builder; un arreglo de un script lo resuelve el builder solo.

## Si un skill activado no está instalado

- **Sin game designer:** el builder crea un GDD mínimo con la [plantilla](gdd-template.md) y marca sus suposiciones.
- **Sin data architect:** el builder guarda lo que el GDD promete con un único servicio de datos propio y las mismas reglas (una sección por core, IDs estables en mapas, límites, versión y migraciones, bloqueo de sesión, nunca guardar un perfil que no cargó), documentado en la Arquitectura. `design.data` pasa a `false` y anota `builder → data-architect: esquema y servicio pendientes (abierto)`. Las plantillas de `PlayerData` son del data architect: sin él instalado no hay de dónde copiarlas.
- **Sin art director:** el builder elige colores y fuentes en su propio código, como antes, y no crea `Theme.json`.
- **Sin environment artist:** los niveles quedan con el aspecto que les dio el level designer y el builder aplica `Style.applyLighting`; `design.environment` pasa a `false` con `builder → environment-artist: pase de arte pendiente (abierto)`. Sin niveles como datos o sin tema, el pase de arte espera al level designer o al art director.
- **Sin UI designer:** el builder hace la interfaz en su propio código respetando las zonas de Roblox (chat, barra superior, controles táctiles), cambia `design.ui` a `false` y anota `builder → ui-designer: interfaz pendiente (abierto)`.
- **Sin level designer:** el builder construye el mundo en su propio código, cambia `design.levels` a `false` y anota `builder → level-designer: niveles pendientes (abierto)`.
- **Sin un módulo de monetización seleccionado:** esa venta no se implementa; queda desactivada y registrada como pendiente. No improvises un flujo de compra.
- **Sin analytics dev o LiveOps:** el juego emite igual sus eventos con `Telemetry` y lee sus ajustes con `Tuning`; nadie los registra ni los cambia en vivo hasta que esos skills existan. El README lo indica como pendiente, y no impide la etiqueta `release-candidate`.

## Pendientes entre skills

Cuando un skill necesita un cambio en un artefacto ajeno, lo anota en la sección "Pendientes entre skills" del GDD con el formato `origen → destino: pedido (estado)`. Si no hay GDD, el pedido va en el documento propio del skill (por ejemplo, `LEVELS.md`).

- Si el skill dueño está instalado y el pedido no cambia una decisión del usuario: cárgalo, resuelve con sus reglas, valida y cierra el pedido.
- Si el pedido cambia una decisión del usuario, pregúntale antes.
- Si el skill dueño no está instalado, el pedido queda abierto en el GDD y se lista en el README.

Cierra cada pedido al resolverlo, para que el GDD muestre solo trabajo abierto.

## Reglas que ningún skill relaja

- El servidor es la autoridad sobre progreso, economía, resultados y beneficios pagados.
- Un único sistema de datos por juego, compartido por todos los módulos.
- Los módulos core son independientes: uno no requiere a otro. Si dos cores tienen que hablar, los une un puente `<Origen>_<Destino>`; lo propio del juego va en `Game` ([arquitectura de módulos](module-architecture.md)). Cualquier skill que escriba código en `src/` respeta las capas.
- No se inventan IDs, precios vigentes, promociones activas ni datos observados.
- La verificación es honesta: se separa lo diseñado, lo implementado, lo comprobado estáticamente, lo probado en Studio y lo probado en una experiencia publicada.
- Las políticas de Roblox y las decisiones expresas del usuario prevalecen sobre las preferencias de cualquier skill.
