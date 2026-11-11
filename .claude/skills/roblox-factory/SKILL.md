---
name: roblox-factory
description: Coordinar la fábrica de juegos Roblox de punta a punta. Decide qué skills usar y en qué orden según el pedido (juego nuevo, prototipo rápido, cambio parcial en un juego existente, mejorar cómo se ve un juego), revisa el estado de un juego de la fábrica con un script que recorre todas las etapas y sus validadores, y arma la entrega final. Úsalo cuando el pedido abarque varias etapas (diseño, datos guardados, arte, niveles, pase de arte, código, interfaz, monetización, audio, analíticas, LiveOps), cuando el usuario quiera que su juego se vea profesional y eso toque varias partes (estilo, niveles y UI), cuando quiera reutilizar sistemas de la librería común de módulos, mejorarla o publicar en ella los módulos de un juego, cuando pregunte qué le falta a su juego, en qué estado está o qué skill usar, o cuando quiera ir de la idea a un juego listo para publicar. Para un pedido de una sola etapa, usa directamente el skill de esa etapa.
metadata:
  version: "1.6.0"
---

# Roblox Factory

Coordina los skills de la fábrica para que cada pedido recorra solo las etapas que necesita, en el orden correcto, y termine con una entrega verificada. No reemplaza las reglas de ningún skill: decide a quién llamar, en qué orden, y comprueba que el resultado de cada etapa esté listo para la siguiente.

## Mapa de la fábrica

| Etapa | Skill | Produce | Se valida con |
| --- | --- | --- | --- |
| Diseño | [roblox-game-designer](../roblox-game-designer/SKILL.md) | `GDD.md` | Autorrevisión del skill |
| Datos | [roblox-data-architect](../roblox-data-architect/SKILL.md) | `design/DATA.md`, `src/server/Data/DataSchema.json`, `Migrations.luau`, `src/shared/DataTypes.luau` | `check_data.py` |
| Arte | [roblox-art-director](../roblox-art-director/SKILL.md) | `design/ART.md`, `src/shared/Theme.json` | `check_art.py` |
| Niveles | [roblox-level-designer](../roblox-level-designer/SKILL.md) | `design/LEVELS.md`, `src/shared/Levels.json` | `validate_levels.py` |
| Entorno | [roblox-environment-artist](../roblox-environment-artist/SKILL.md) | `design/ENVIRONMENT.md`, `src/shared/Environment.json` | `check_environment.py` |
| Vehículos 3D | [roblox-vehicle-modeler](../roblox-vehicle-modeler/SKILL.md) | `<Auto>.spec.json`, FBX por piezas y `manifest.json` en studs y ejes de Roblox, `src/shared/VehicleModels.json` y las plantillas de ensamblado | `check_vehicle.py` (queda fuera de `factory_status.py`) |
| Audio | [roblox-audio-designer](../roblox-audio-designer/SKILL.md) | `design/AUDIO.md`, `src/shared/Audio.json` (buses, assets y cues), `src/shared/SoundBank.luau`, archivos en `assets/audio/` listos para subir | `check_audio.py` (queda fuera de `factory_status.py`) |
| Monetización | [Developer Products](../roblox-monetization-developer-products/SKILL.md), [Game Passes](../roblox-monetization-game-passes/SKILL.md), [Creator Rewards](../roblox-monetization-creator-rewards/SKILL.md), [Avatar UGC](../roblox-monetization-avatar-ugc/SKILL.md) | Catálogo, flujos y pruebas en el GDD | Pruebas de cada módulo |
| Código | [roblox-game-builder](../roblox-game-builder/SKILL.md) | `src/` en capas (cores, puentes y `Game`), servicio de datos copiado, proyecto Rojo, README | `check_game.py` (con `check_modules.py`), luau-lsp, `rojo build` |
| Librería | [roblox-game-builder](../roblox-game-builder/references/module-library.md) | Copias de [Roblox-Library](https://github.com/drakkartalessrudio-dotcom/Roblox-Library) con `library.lock.json`; módulos nuevos y versiones en branches de la librería | `library.py status`, `check_library.py`, `run_tests.py` |
| UI | [roblox-ui-designer](../roblox-ui-designer/SKILL.md) | `design/UI.md`, `src/client/UI/` | `check_ui.py` |
| Analíticas | [roblox-analytics-dev](../roblox-analytics-dev/SKILL.md) | `design/ANALYTICS.md`, esquema y módulo | `check_analytics.py` |
| LiveOps | [roblox-liveops](../roblox-liveops/SKILL.md) | `design/LIVEOPS.md`, esquema y módulo | `check_liveops.py` |

Quién escribe cada archivo y qué hacer si falta un skill está en el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md). Los skills se instalan como conjunto: sus validadores se buscan entre sí por carpeta, y `check_game.py` corre los de todas las etapas activadas.

## 1. Elegir el recorrido

Lee el pedido y, si hay un juego, su `GDD.md`. Elige el recorrido en la [guía de recorridos](references/routing.md). Lo esencial:

- **Juego nuevo:** designer → data architect (si `design.data`) → art director (si `design.art`) → level designer (si `design.levels`) → environment artist (si `design.environment`) → módulos de monetización seleccionados → builder → UI designer (si `design.ui`) → analíticas (si `analytics.enabled`) → LiveOps (si `liveops.enabled`) → verificación final del builder. Para publicar, el designer suele activar datos (si el juego promete guardar progreso), arte, pase de arte e interfaz.
- **Juego grande con varios places:** el mismo recorrido; el designer declara los places y los viajes, el level designer asigna cada nivel a su place y el builder arma un proyecto por place con `Place` y `Travel` ([varios places](../roblox-game-builder/references/multi-place.md)). El usuario crea los places y carga sus IDs.
- **Prototipo rápido:** solo el builder, con un GDD mínimo. Ver el paso 2.
- **Agregar o arreglar sonido** (efectos, música, un timbre, "mi audio no suena" o "Roblox no acepta mi archivo"): [audio designer](../roblox-audio-designer/SKILL.md) (cues y mezcla en `Audio.json`, archivos preparados; el usuario sube y da permiso) → builder si hay que conectar disparos o un RemoteEvent → UI designer si el sonido pertenece a un botón o aviso. El ambiente fijo de un nivel sigue siendo del environment artist.
- **Mejorar cómo se ve un juego existente:** primero pregunta una vez por referencias y assets propios (imágenes de estilo, modelos, texturas, sonidos; ver [assets del usuario](../roblox-environment-artist/references/user-assets.md)), después art director (si no hay tema o cambia el estilo) → environment artist (si hay `Levels.json`) → builder (integra `EnvironmentLoader` y quita la iluminación hecha a mano) → UI designer (reemplaza la UI pantalla por pantalla). La lógica del juego no cambia.
- **Agregar algo que se guarda** (mascotas, misiones diarias, un inventario): designer (qué se promete) → data architect (sección y, si cambia algo existente, migración) → builder (core nuevo con su fachada y un puente si toca otro core, sin modificar los cores existentes) → UI designer si hay pantalla. Contenido nuevo que se guarda por ID (misiones, niveles, items) no toca el esquema.
- **Sistemas que ya existen:** antes de que el builder escriba un core o un puente, busca en la librería (`library.py search`). Lo que sirve se copia sin editar; lo que casi sirve se mejora en la librería con versión nueva y se actualiza en cada juego que lo quiera; al cerrar un juego, sus cores propios sin contenido del juego se publican. Subir cambios de la librería lo aprueba el usuario. Ver la [librería de módulos](../roblox-game-builder/references/module-library.md).
- **"Se pierden datos" o "se duplican compras":** data architect (diagnóstico en `DATA.md`) → builder (arreglo, en general pasar al servicio `PlayerData` conservando las claves y la forma de los perfiles guardados) → Developer Products si hay recibos.
- **Cambio en un juego existente:** empieza por el skill dueño de lo que cambia y sigue la cadena solo hacia abajo. Un cambio de niveles o de paleta vuelve a pasar por el pase de arte: la decoración puede quedar en el aire de un salto o con un color que ya no existe.
- **"¿Qué le falta a mi juego?":** el script de estado del paso 4, sin cambiar nada.

Antes de empezar, di en una línea qué recorrido vas a seguir y por qué. Pregunta solo si el pedido admite dos recorridos con costos muy distintos (por ejemplo, prototipo rápido o juego para publicar) y no hay pistas para elegir.

## 2. Modo rápido

Úsalo cuando el usuario quiere probar una idea, dice "rápido", "prototipo" o "solo para ver si es divertido", o el juego tiene un loop simple y no se va a publicar todavía.

- El builder crea un GDD mínimo con su plantilla (`mode: prototype`, analíticas y LiveOps en `false`, monetización vacía salvo pedido expreso) y construye el juego.
- Se mantienen `Tuning` y `Telemetry`: cuestan poco y dejan el juego listo para crecer. También las capas: un core y `Game` alcanzan.
- Sin servicio de datos salvo que el usuario pida guardar algo: el estado vive en los cores durante la sesión. Pasar a publicar agrega el data architect.
- Se omiten el documento completo del designer, los niveles como datos (salvo que sean el centro del juego, como en un obby), el arte, el pase de arte, el UI designer, las analíticas y LiveOps. El builder hace una UI simple que respeta las zonas de Roblox (chat, barra superior, controles táctiles).
- Al entregar, explica cómo pasar a la versión completa: el designer completa el GDD (incluido qué se guarda), el data architect diseña los datos y el script de estado muestra qué etapas faltan.

## 3. Recorrer las etapas

Para cada etapa del recorrido:

1. Carga el skill de la etapa y sigue sus reglas: este skill no las repite ni las relaja.
2. Al terminar, corre su validador y corrige los errores antes de pasar a la siguiente. Un error que llega a la etapa siguiente cuesta más.
3. Lleva adelante los pedidos entre skills: si una etapa dejó un pedido abierto para un skill instalado, resuélvelo con la regla de pendientes del contrato antes de seguir.

Mantén informado al usuario con una línea por etapa: qué terminó y qué sigue.

Las etapas tienen dependencias: el data architect necesita lo que el GDD promete conservar ("Estado y economía"), y el builder necesita `DataSchema.json` antes de programar los cores que guardan; el pase de arte necesita el tema y los niveles como datos; la UI necesita el tema y el "Estado para la UI" que publica el builder. Si falta una, haz primero esa etapa o deja el pedido abierto.

## 4. Revisar el estado

```bash
python <skill-dir>/scripts/factory_status.py <Juego>
```

En Windows, usa `python` o `py -3` si `python3` no existe. El script recorre diseño, datos, arte, niveles, entorno, monetización, código, módulos, librería, places, UI, analíticas, LiveOps y build con los validadores de cada skill (`--library <ruta>` si la librería no está en `ROBLOX_LIBRARY` ni en el GDD); atribuye cada error a su etapa, señala las etapas visuales recomendadas para publicar, lista los pedidos abiertos de "Pendientes entre skills" y propone el siguiente paso. La etapa Studio siempre queda pendiente: solo se comprueba jugando.

Úsalo al final de cada recorrido y cuando el usuario pregunte qué falta. Responde con la tabla del script y el siguiente paso concreto: qué skill, qué comando o qué debe hacer el usuario.

## 5. Entregar

Cierra con un resumen breve:

- Qué se hizo en cada etapa y qué quedó fuera (posterior).
- Estado según el script, separando lo verificado (validadores, análisis, build) de lo pendiente (Studio, experiencia publicada, configuración en Creator Hub).
- Lo que debe hacer el usuario: abrir el place en Studio, crear pases o configs en Creator Hub, publicar. Si el recorrido cambió cómo se ve el juego, pídele capturas de antes y después en PC y en el emulador de un teléfono: los validadores comprueban legibilidad y reglas, no si se ve bien. Nunca publiques, compres ni cambies configuración de la cuenta por tu cuenta.
