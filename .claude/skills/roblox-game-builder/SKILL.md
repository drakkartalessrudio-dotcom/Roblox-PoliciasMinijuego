---
name: roblox-game-builder
description: Crear, ampliar o arreglar un juego Roblox completo a partir de una idea, un GDD o los niveles de la fábrica, con proyecto Luau/Rojo, integración de los módulos de monetización seleccionados, puntos de enganche de telemetría y ajustes en vivo, y verificación honesta. Para un cambio aislado de script, aplica solo las reglas técnicas pertinentes. Si el pedido es solo diseño (loop, economía, progresión, KPIs) corresponde a roblox-game-designer; si son solo niveles, a roblox-level-designer.
metadata:
  version: "4.4.2"
---

# Roblox Game Builder

Convierte una idea o GDD en un juego jugable de Roblox. Conserva el diseño pedido, construye un proyecto editable y comprueba por separado el código, el place y el comportamiento en Studio. Es el implementador de la fábrica: integra el GDD del game designer, los niveles del level designer y los módulos de monetización en un solo proyecto.

## Composición con otros skills

El frontmatter del GDD declara qué skills participan, y el [contrato de la fábrica](references/factory-contract.md) define qué artefactos escribe cada uno, el orden de trabajo y qué hacer si falta un skill. Léelo antes de crear o ampliar un juego.

- Carga **solo** los módulos que el GDD activa: los de `monetization.enabled`, entre [Developer Products](../roblox-monetization-developer-products/SKILL.md), [Game Passes](../roblox-monetization-game-passes/SKILL.md), [Creator Rewards](../roblox-monetization-creator-rewards/SKILL.md) y [Avatar UGC](../roblox-monetization-avatar-ugc/SKILL.md); [roblox-data-architect](../roblox-data-architect/SKILL.md) si `design.data` es `true`; [roblox-art-director](../roblox-art-director/SKILL.md) si `design.art` es `true`; [roblox-ui-designer](../roblox-ui-designer/SKILL.md) si `design.ui` es `true`; [roblox-level-designer](../roblox-level-designer/SKILL.md) si `design.levels` es `true`; [roblox-environment-artist](../roblox-environment-artist/SKILL.md) si `design.environment` es `true`; [roblox-analytics-dev](../roblox-analytics-dev/SKILL.md) si `analytics.enabled` es `true`; y [roblox-liveops](../roblox-liveops/SKILL.md) si `liveops.enabled` es `true`. `enabled: []` o `false` significa que el juego no solicita ese sistema. Si el usuario pidió expresamente un mecanismo ausente del frontmatter, agrégalo al GDD antes de construir.
- Para decisiones de experiencia de juego usa [roblox-game-designer](../roblox-game-designer/SKILL.md) si está instalado.
- Escribe solo los artefactos que el contrato te asigna. Si necesitas cambiar uno ajeno, como `Levels.json`, sigue la [regla de pendientes](references/factory-contract.md#pendientes-entre-skills): con el skill dueño instalado, resuélvelo con sus reglas y cierra el pedido; sin él, déjalo abierto en el GDD y en el README.

Responsabilidades: el GDD decide público, loop, contenido, economía, plataformas y catálogo; game design orienta claridad, progresión y balance; el level designer decide el layout de los niveles; los módulos de monetización definen sus flujos y pruebas; este builder integra arquitectura, código, proyecto, datos, seguridad, ejecución y entrega. El GDD no anula las garantías técnicas ni las políticas de Roblox. Registra cualquier decisión que cambie alcance o comportamiento.

Para un script o arreglo pequeño dentro de un juego existente, respeta su arquitectura y aplica las reglas pertinentes sin regenerar un juego ni su GDD. Un juego plano (sin `Modules/` ni `Game/`) no se reorganiza en capas salvo que el usuario lo pida; si lo pide, sigue [pasar un juego plano a capas](references/module-architecture.md#pasar-un-juego-plano-a-capas). Si el proyecto no tiene `GDD.md` con el frontmatter de la fábrica, no agregues puntos de enganche ni corras `check_game.py`: verifica solo el cambio.

## 1. Entender y acotar

- Si recibes una idea y [roblox-game-designer](../roblox-game-designer/SKILL.md) está instalado, úsalo primero para crear `GDD.md`. Si no está, crea `GDD.md` con la [plantilla](references/gdd-template.md). Marca las suposiciones; pregunta solo cuando una decisión del núcleo impida elegir una implementación razonable.
- Si el GDD viene del usuario o del game designer, conserva sus decisiones y no lo reescribas: completa Arquitectura y Assets. Un GDD pegado o en otro formato se guarda como `GDD.md` sin reescribir su contenido, y lo que falte se agrega en las secciones de la plantilla.
- Antes de programar, el GDD necesita el frontmatter de la fábrica, los pasos del funnel de onboarding, el camino de progresión, las monedas (si hay) y los parámetros ajustables: de ahí salen los nombres de `Telemetry` y los valores de Config. Si faltan, complétalos con el game designer si está instalado; si no, con nombres habituales del género, marcados como **Suposición**.
- Si `design.levels` es `true` y todavía no existe `src/shared/Levels.json`, genera los niveles con el level designer antes de programar. Si ese skill no está instalado, construye el mundo en tu propio código, cambia `design.levels` a `false` y anota `builder → level-designer: niveles pendientes (abierto)`.
- Si el GDD declara varios places (`project.places` como lista), el juego es una experiencia con varios places: lee [varios places](references/multi-place.md) antes de diseñar la arquitectura. Con un solo place, no agregues `Place` ni `Travel`.
- Registra `project.mode`: `prototype` para validar el loop con el menor alcance útil; `release-candidate` para una versión con los sistemas prometidos, recuperación y pruebas de lanzamiento. Si el usuario ya indicó intención de publicar o entregar un juego terminado, usa `release-candidate`. Un modo no cancela requisitos pedidos.
- Clasifica sistemas en **MVP** y **posterior**. Mantén en MVP el loop completo, feedback, controles en las plataformas objetivo, progreso prometido y cualquier monetización seleccionada. Reduce contenido repetido antes de eliminar una capacidad obligatoria. No impongas un máximo universal de places o de sistemas.
- Define criterios de aceptación observables: entrada, acción, recompensa/progreso, fallo o victoria y regreso si aplica. El juego debe funcionar con la población prevista, incluida la sesión en solitario cuando el diseño la prometa.
- Identifica IDs, assets, permisos, cuenta/experiencia publicada y configuración externa necesarios. Los valores desconocidos quedan como dependencias explícitas; no inventes IDs ni promociones activas.

## 2. Diseñar la arquitectura

En el GDD incluye un mapa breve de archivos y servicios, remotes (nombre, dirección, payload y validación), datos persistentes, estado de sesión, propiedad de cada regla, eventos de telemetría y orden de inicio. Agrega el **Mapa de módulos** (cada core, puente y `Game`, con su API, sus eventos y los datos que posee) y la tabla **Estado para la UI** con los atributos y remotes que la interfaz puede usar (ver [puntos de enganche](references/hooks.md#estado-para-la-ui)).

**Módulos.** Organiza el código en capas, como los proyectos de UEFN del usuario. Lee [arquitectura de módulos](references/module-architecture.md) antes de programar:

- Cada sistema del juego es un **core** en `src/<lado>/Modules/<Nombre>/`: no sabe en qué juego está, recibe su contenido en `init`, arranca en `start` y publica lo que pasa con `Signal`. Un core no requiere a otro core.
- Si dos cores tienen que hablar, los une un **puente** `src/<lado>/Bridges/<Origen>_<Destino>/`, que requiere solo esos dos: escucha a `Origen` y llama a `Destino`.
- **`Game`** (`src/<lado>/Game/`) es la composición de este juego: contenido, configuración de cada core, orden de arranque (`init` de los cores, `connect` de los puentes, `start` de los cores) y reacciones propias que mezclan módulos. `Bootstrap` prepara el núcleo y llama a `Game.start`.
- Si conviene que un core dependa de otro, decláralo como excepción en el Mapa de módulos con el motivo.
- **Librería de módulos:** antes de escribir un core o un puente, búscalo en la librería común con `library.py search`; si existe, cópialo con `library.py add` y no edites la copia; si hay que cambiarlo, mejóralo en la librería con `bump` y `release` y actualiza el juego con `update`. Al cerrar un juego, propón sus cores y puentes propios con `publish`. Ver [librería de módulos](references/module-library.md).

El [esqueleto](assets/skeleton) muestra dos cores unidos por un puente; el prototipo más chico tiene un core y `Game`. [Aldea de Gremios](assets/example-quests/README.md) es la referencia para un juego con varios sistemas: cuatro cores, tres puentes encadenados, `Game` con el catálogo y datos guardados.

Como punto de partida usa la [plantilla Rojo](assets/default.project.json). Al copiarla a la carpeta del juego, cambia `name` y comprueba las rutas del proyecto. Su jerarquía inicial es:

```text
<Juego>/
├── GDD.md
├── README.md
├── default.project.json
├── design/              → LEVELS.md y documentos de otros módulos (no entran al place)
├── src/
│   ├── shared/          → ReplicatedStorage.Shared: Config.luau, Tuning.luau, Signal.luau, Levels.json, Theme.json, Style.luau, Environment.json
│   ├── server/          → ServerScriptService.Server: Bootstrap.server.luau, Telemetry.luau, LevelLoader.luau, EnvironmentLoader.luau
│   │   ├── Modules/     → un core por sistema (Modules/<Nombre>/init.luau)
│   │   ├── Bridges/     → un puente por par de cores que hablan (Bridges/<Origen>_<Destino>/)
│   │   └── Game/        → composición del juego: contenido y arranque
│   └── client/          → StarterPlayer.StarterPlayerScripts.Client; mismas capas; UI/ es del UI designer si design.ui
└── build/               → archivo .rbxlx cuando se genere
```

La raíz de `src/server/` y `src/shared/` es el núcleo: las plantillas de la fábrica, Config y los datos. El código propio del juego va en `Modules/`, `Bridges/` o `Game/`.

**Puntos de enganche.** Copia de [assets/templates/src](assets/templates/src) `Tuning.luau` y `Telemetry.luau` siempre, `Signal.luau` cuando un core publique eventos, `LevelLoader.luau` cuando haya `Levels.json`, `Style.luau` cuando haya `Theme.json`, `EnvironmentLoader.luau` cuando haya `Environment.json`, y `Place.luau` y `Travel.luau` cuando el GDD declare varios places, sin cambiar su API. Si el juego guarda datos (`design.data` y `src/server/Data/DataSchema.json`), copia también las plantillas del servicio de datos del [data architect](../roblox-data-architect/assets/templates/src/server/Data) a `src/server/Data/`. Lee [puntos de enganche](references/hooks.md) antes de programar: explica cómo leer ajustes, qué eventos emitir y cuándo, y qué significa cada tipo de pieza de nivel. Con ellos, el level designer, el art director, el environment artist, las analíticas y LiveOps se conectan sin reescribir el juego.

Todo valor ajustable va en `src/shared/Config.luau`, con los valores de "Parámetros ajustables" del GDD, y se lee con `Tuning.get`. `src/server/ServerConfig.luau` guarda solo lo que no debe llegar al cliente, como límites antitrampa o tablas internas; LiveOps no lo ajusta. No pongas secretos en `ReplicatedStorage`; tampoco confíes en un valor compartido como prueba de propiedad, precio o recompensa.

Usa un único `Bootstrap.server.luau` como entrada del servidor: prepara el núcleo (datos, mundo, remotes) y llama a `Game.start`, en el orden de [puntos de enganche](references/hooks.md#orden-de-inicio). Crea los remotes y el mundo requerido antes de activar interacciones. Inicializa perfiles antes de permitir cambios económicos. Atiende jugadores ya presentes al conectar `PlayerAdded` y vuelve a conectar lógica dependiente del personaje en `CharacterAdded`. Evita bucles `WaitForChild` sin diagnóstico para dependencias que puedan faltar. Limpia conexiones, tareas y estado por jugador/ronda al terminar.

**Varios places.** Todos los places comparten el mismo `src/`: `default.project.json` es el place de inicio y cada otro place tiene `places/<place>.project.json` con las mismas carpetas y un `StringValue` `ReplicatedStorage.PlaceKey` con su clave. Copia también `Place.luau` y `Travel.luau`, escribe `src/shared/Places.json` con los places del GDD (PlaceId en 0 hasta que el usuario los cree) y documenta los viajes en la sección "Places y viajes". Cada place construye solo sus niveles (`LevelLoader.build` con `only = Place.levels(Levels)`) y arranca sus sistemas según `Place.role()`. Detalles, datos entre places y publicación: [varios places](references/multi-place.md).

La estructura puede crecer según el GDD. Si añades `src/character` u otros servicios, actualiza `default.project.json` (y cada proyecto de place) y verifica la jerarquía construida. Revisa los `require` contra rutas reales, por ejemplo `ReplicatedStorage.Shared` y `ServerScriptService.Server`; los nombres del ejemplo no son un sustituto del árbol generado.

## 3. Implementar el juego

### Estado y seguridad

- El servidor decide puntuación, moneda, daño, inventario, progreso, resultados y beneficios pagados. El cliente envía intención y presenta el estado autorizado.
- Cada remote e interacción disparable desde cliente valida tipo, límites, números finitos, permisos, contexto, distancia y frecuencia según el efecto. Valida también `ProximityPrompt`, `ClickDetector` y `.Touched`; un debounce solo controla frecuencia. No aceptes del cliente precios, cantidades de recompensa, checkpoints, `PurchaseId` ni una confirmación de compra. [Seguridad cliente/servidor](https://create.roblox.com/docs/scripting/security/client-server-boundary).
- Para contactos, identifica el personaje y jugador de manera fiable y verifica que la acción siga siendo válida en el servidor. Para efectos visuales enviados a otros clientes, valida antes de retransmitir.
- Controla errores de servicios y separa `loading`, `ready` y `unavailable` cuando la distinción cambie el juego. No conviertas un error de carga en progreso cero confirmado.

### Datos y economía

Guarda lo que el juego promete conservar: progreso, inventario, derechos adquiridos y cualquier historial necesario para evitar duplicaciones. Un prototipo sin datos persistentes prometidos puede omitir DataStore. Un producto pagado con beneficio persistente exige almacenamiento y recuperación adecuados, aunque el modo sea `prototype`.

Define esquema y versión de perfil, migraciones, carga fallida, guardado periódico, salida, cierre del servidor y coordinación de escrituras. Con `design.data`, el esquema, las secciones y sus dueños los define el [data architect](../roblox-data-architect/SKILL.md) en `design/DATA.md` y `src/server/Data/DataSchema.json`, y el servicio `PlayerData` (plantillas sin cambios) ya hace la carga con bloqueo de sesión, las migraciones, el autosave, el cierre y las compras idempotentes: tú llamas a `PlayerData.start()` en Bootstrap y escribes en cada core la fachada de su sección ([PlayerData](references/hooks.md#playerdata-el-servicio-de-datos)). Pídele al data architect los cambios del esquema con la regla de pendientes. Evita que dos servidores carguen y sobrescriban el mismo perfil; protege operaciones pagadas frente a reintentos concurrentes. Usa un único servicio de datos para el juego y sus módulos seleccionados. La [guía de Roblox para datos y compras](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing) cubre bloqueo de sesión y entrega atómica.

No guardes en DataStore por cada frame o click. Si falla una carga, comunica el estado, limita las acciones que dependan de guardar y evita sobrescribir el perfil real con valores por defecto. Toda compra debe seguir el módulo de monetización elegido; este skill no crea un segundo procesador de recibos.

### Mundo y eventos

- Con `Environment.json`, llama a `EnvironmentLoader.apply(built, Environment)` justo después de `LevelLoader.build`: viste los niveles, agrega la decoración y aplica la iluminación del tema, así que no llames también a `Style.applyLighting` ([puntos de enganche](references/hooks.md#environmentloader-el-pase-de-arte)). No cambies el aspecto de las piezas en tu código. Si `Environment.json` declara modelos o variantes de material del usuario, mapea `assets/models` a `ServerStorage.EnvironmentAssets` y `assets/materials` a `MaterialService` en `default.project.json`.
- Con `Levels.json`, construye el mundo con `LevelLoader` y aplica su física; implementa en tus sistemas la semántica de cada tipo de pieza (checkpoint, meta, peligro, coleccionable, zona) como indica [puntos de enganche](references/hooks.md#levelloader-el-mundo-desde-levelsjson). No dupliques la física en Config.
- Sin `Levels.json`, construye el mundo con Luau en un módulo propio cuando sea suficiente para el prototipo. Usa assets, terreno, modelos e interfaces existentes cuando el GDD los requiera y se puedan verificar. Comprueba derechos, origen e IDs; nunca inventes `rbxassetid://`.
- Emite con `Telemetry` los momentos del contrato usando los nombres del GDD: pasos de onboarding, inicio y fin de cada nivel o hito, movimientos de moneda ya aplicados y los eventos propios que pidan los KPIs.

### Interfaz y dispositivos

Con `design.ui`, la interfaz es del [UI designer](../roblox-ui-designer/SKILL.md): no escribas en `src/client/UI/`. Tu parte es que el servidor publique el estado que la UI muestra y documentarlo en **Estado para la UI**; si la UI pide un atributo o remote nuevo, agrégalo con las reglas de seguridad y actualiza la tabla.

Sin `design.ui`, o sin el UI designer instalado, la UI es tuya y respeta las zonas de Roblox: nada en la esquina superior izquierda (chat) ni en la barra superior (cada `ScreenGui` con `ScreenInsets.CoreUISafeInsets`), nada sobre las esquinas inferiores en celular (joystick y botón de salto), botones de 44 px o más y un atajo de gamepad para abrir y cerrar cada ventana.

Con `Theme.json`, colores, fuentes y medidas de la UI salen de `Style`, y `Theme.lighting.style` va a `default.project.json` (ver [puntos de enganche](references/hooks.md#style-el-tema-visual)). La UI debe mostrar objetivo, resultado, estado de carga/error y progreso legible. Las tiendas muestran el beneficio y precio vigentes mediante el módulo correspondiente. Conserva la UI a través de respawns cuando tenga sentido; evita duplicarla al crear otra vez `PlayerGui`.

Implementa controles accesibles en teclado/ratón, touch y gamepad **según las plataformas objetivo**. Ajusta navegación y tamaños a distintos viewports y cambios de input. Prueba con los emuladores pertinentes de Studio; no pospongas el control principal ni el cierre de una tienda por ser “UI móvil”. [Desarrollo multiplataforma](https://create.roblox.com/docs/projects/cross-platform).

Diseña un presupuesto de partes, NPCs, conexiones, efectos y tráfico de remotes para el juego concreto. Mide los cuellos de botella en ejecución antes de declararlo optimizado.

## 4. Construir y verificar

Si el juego sigue el contrato de la fábrica (tiene `GDD.md` con su frontmatter), revisa primero el proyecto contra el contrato:

```bash
python <skill-dir>/scripts/check_game.py <Juego>
```

En Windows, usa `python` o `py -3` si `python3` no existe. El script comprueba estructura, frontmatter, puntos de enganche, rutas de `Tuning.get` contra Config, `Levels.json` con el validador del level designer, el arte, la interfaz, el pase de arte, las analíticas y LiveOps con los validadores de sus skills, las capas de módulos con `check_modules.py` (también se puede correr solo) y errores frecuentes: requires a módulos inexistentes, APIs de servidor en el cliente, funciones obsoletas, IDs de assets no declarados en el GDD y más de un `ProcessReceipt`. Corrige todos los ERROR; cada WARN se corrige o se explica en el README. Las notas INFO señalan handlers que conviene revisar a mano.

Después, con Rojo 7.2 o superior disponible, ejecuta desde la carpeta del juego:

```bash
mkdir -p build
rojo build -o build/GameName.rbxlx
```

Usa el nombre real del juego y comprueba que el archivo se creó. Con varios places, construye un archivo por place: `rojo build places/<place>.project.json -o build/<Place>.rbxlx` para cada uno además del de inicio. Rojo convierte `Levels.json` en un ModuleScript. [Rojo: build](https://github.com/rojo-rbx/rojo.space/blob/master/docs/getting-started/new-game.mdx), [plantilla oficial de proyecto](https://github.com/rojo-rbx/rojo/blob/master/assets/project-templates/place/default.project.json).

Si `luau-lsp` está disponible, analiza el código contra los tipos de Roblox desde la carpeta del juego (las definiciones `globalTypes.None.d.luau` se descargan del repositorio de luau-lsp):

```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=<ruta>/globalTypes.None.d.luau --sourcemap=sourcemap.json --ignore="**/*.json" src
```

Corrige todos sus errores. `--ignore` excluye `Levels.json`: el analizador infiere tipos rígidos para datos JSON con piezas de distinta forma y da falsos positivos. `check_game.py`, el análisis o un build exitoso no prueban que el juego funcione.

Si tienes acceso a Studio, abre el place (cada place por separado si hay varios: los viajes entre places solo funcionan en la experiencia publicada) y comprueba el Output y el loop completo: ingreso inicial y tardío, dos clientes si hay multiplayer, respawn, pérdida y victoria, salida/reingreso, UI y controles en los dispositivos objetivo. Con niveles, recorre cada uno: saltos, checkpoints, piezas móviles y metas; con pase de arte, que ningún adorno tape un salto ni ataje una caída. Para progreso o compras, prueba carga fallida, guardado y recuperación; usa las pruebas adicionales de los módulos seleccionados. La configuración de Marketplace/DataStore de una experiencia publicada se verifica aparte en una experiencia de prueba. No realices compras con Robux sin autorización.

Si Studio o una herramienta de build no están disponibles, entrega los artefactos que sí pudiste crear y señala exactamente qué comprobación quedó pendiente. No describas como “probado en Studio” un proyecto que solo pasó revisión estática.

## 5. Entregar

Entrega `GDD.md`, `design/`, fuente Luau, `default.project.json` y `README.md`; agrega el `.rbxlx` y un zip del proyecto cuando hayas podido generarlos. El README explica cómo abrir y jugar, qué parámetros editar, qué sistemas quedaron posteriores, qué módulos activados quedaron pendientes (por ejemplo analíticas o LiveOps sin instalar) y qué IDs/configuración externa falta. Con varios places, agrega cómo construir cada place y los pasos de publicación del usuario (start place, places nuevos, PlaceId, tamaño de servidor). Incluye la versión de Rojo si se usó.

Resume la evidencia en niveles separados: **archivo/build**, **análisis estático** (incluido `check_game.py`), **niveles**, **Studio**, **datos/monetización** y **servicios publicados**. Para cada nivel indica realizado, resultado y pendiente. Un `release-candidate` solo recibe esa etiqueta si se implementaron todos los requisitos de su GDD; distingue verificaciones pendientes del estado de implementación. Un módulo activado cuyo skill todavía no existe, como las analíticas o LiveOps, no impide la etiqueta si el juego emite sus eventos con `Telemetry`, lee sus ajustes con `Tuning` y el README lo lista como pendiente.

## Ejemplo

[assets/example-obby](assets/example-obby/README.md) es un juego completo que sigue este flujo: GDD con frontmatter de la fábrica, `LEVELS.md` y `Levels.json` validados, `LevelLoader`, `Tuning`, `Telemetry`, un core de reglas (`Modules/Obby`) arrancado por `Game` y una interfaz hecha con el kit del UI designer que solo presenta el estado publicado. Míralo cuando dudes cómo encajan las piezas; no lo copies para otros géneros. [assets/example-places](assets/example-places/README.md) muestra una experiencia con dos places que comparten el código, con un core por place. [assets/skeleton](assets/skeleton) muestra dos cores unidos por un puente. [assets/example-quests](assets/example-quests/README.md) (Aldea de Gremios) junta todo en un juego con varios sistemas: misiones, monedas y recompensa diaria en cuatro cores con sus fachadas de datos, tres puentes y `Game`; tiene una prueba de punta a punta con Lune.
