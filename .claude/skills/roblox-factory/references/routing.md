# Guía de recorridos

Cada pedido recorre solo las etapas que necesita. La regla general del [contrato](../../roblox-game-builder/references/factory-contract.md): empezar por el dueño de lo que cambia y seguir la cadena solo hacia abajo.

| Pedido | Recorrido | Verificación al final |
| --- | --- | --- |
| Juego nuevo desde una idea | designer → data architect (si `design.data`) → art director (si `design.art`) → level designer (si `design.levels`) → environment artist (si `design.environment`) → monetización → builder → UI designer (si `design.ui`) → analíticas (si hay) → LiveOps (si hay) | `factory_status.py`, `rojo build` |
| Juego nuevo desde un GDD del usuario | builder (completa el GDD con el designer si faltan nombres, parámetros o qué se guarda) → data architect, art director y level designer si hacen falta → resto como arriba | `factory_status.py` |
| Juego grande o con vestíbulo y partidas | designer (places y viajes) → data architect (un documento para todos los places) → art director → level designer (`place` de cada nivel) → environment artist → monetización → builder (un proyecto por place, `Place`, `Travel`, guardado antes de viajar) → UI designer → analíticas → LiveOps | `factory_status.py` (etapas Datos y Places), `rojo build` de cada place; los viajes, en la experiencia publicada |
| Pasar un juego existente a varios places | designer (places y viajes) → level designer (`place` de cada nivel) → builder (proyectos, registro, viajes, `PlayerData.save` en `Travel.onBeforeTravel`) → UI designer si hay pantallas por place | `factory_status.py` |
| Prototipo rápido | builder con GDD mínimo, un core y `Game`, sin servicio de datos salvo pedido | `check_game.py`, `rojo build` |
| Pasar un prototipo a publicar | designer (`release-candidate`, qué se conserva, `design.data`) → data architect (`persistent`) → art director, environment artist y UI designer recomendados → builder (servicio de datos y fachadas) → analíticas | `factory_status.py` |
| Agregar un sistema que se guarda (mascotas, misiones diarias, inventario) | designer (qué se promete) → builder busca en la librería (`library.py search`) → data architect (sección nueva, o la del módulo de la librería con `library_section.py`; migración si cambia algo que ya existe) → builder (core nuevo con su fachada, o la copia de la librería, y un puente si toca otro core, sin modificar los cores existentes) → UI designer si hay pantalla | `check_data.py`, `check_game.py`, `factory_status.py` |
| Cambiar o renombrar lo que se guarda | data architect (versión nueva, `history` y migración) → builder si cambia una fachada | `check_data.py` (simula la migración), `check_game.py` |
| "Se pierden datos" o "se duplican compras" | data architect (diagnóstico en `DATA.md`, esquema con la forma actual en `history`) → builder (pasar a `PlayerData` sin cambiar la clave ni el DataStore de los perfiles guardados) → Developer Products si hay recibos | `check_data.py`, `check_game.py`; en Studio, salir y volver |
| Un sistema nuevo que depende de otro | builder: busca primero en la librería; core nuevo y puente `<Origen>_<Destino>`, sin tocar los cores | `check_game.py` (etapa Módulos) |
| Usar un sistema que ya está en la librería | builder (`library.py search` y `add`; un puente después de sus dos cores) → data architect (`library_section.py` si guarda) → builder (contenido en `Game` por `init` y `connect`, ajustes en Config, Origen en el Mapa de módulos, `library.py record`) | `factory_status.py` (etapas Módulos y Librería), `check_game.py` |
| Un módulo de la librería casi sirve o tiene un error | builder en la librería (`bump`, con `--from-game` si el cambio se probó en el juego; código, README y pruebas; `release`) → el usuario aprueba subir la branch y abrir el PR → builder `update` en el juego → data architect (`library_section.py --since`) si cambió la sección | `check_library.py` y `run_tests.py` en la librería; `factory_status.py` del juego |
| Actualizar los módulos de la librería de un juego | `factory_status.py` o `library.py status` → builder `update`, uno por uno, leyendo el CHANGELOG → data architect si cambió una sección → UI designer si cambió el estado que publica un core | `factory_status.py`, `check_game.py`, Studio |
| Publicar en la librería los módulos de un juego | builder (`publish` de los cores y después de los puentes; README, pruebas y sin contenido del juego; `release`; `add` para adoptar la copia) → el usuario aprueba subir la branch y abrir el PR | `check_library.py`, `run_tests.py`, `factory_status.py` (etapa Librería) |
| Pasar un juego plano a módulos | builder en modo migración ([pasar un juego plano a capas](../../roblox-game-builder/references/module-architecture.md#pasar-un-juego-plano-a-capas)); data architect si cambia el dueño de los datos | `check_game.py`, luau-lsp |
| Cambiar o agregar niveles | level designer → environment artist (si `design.environment`: vestir lo nuevo y revisar que la decoración no quede en el aire de un salto) → builder (si cambia la lógica) | `validate_levels.py`, `check_environment.py`, `check_game.py` |
| Rebalancear la economía o la dificultad | designer (Parámetros ajustables) → builder (Config) → LiveOps si se cambia en vivo | `check_game.py` |
| Agregar monetización | designer (oferta y beneficio) → módulo de monetización → data architect (sección de recibos con Developer Products; derechos que duran) → builder (servicio de compra con `PlayerData.grantPurchase`) → UI designer (tienda, si `design.ui`) → analíticas (`economy` IAP) | `check_data.py`, `check_game.py`, pruebas del módulo |
| Definir o cambiar el estilo visual | art director → environment artist (si `design.environment`: actualizar colores y preset) → builder (`LightingStyle` en el proyecto) | `check_art.py`, `check_environment.py`, `check_ui.py` |
| Los niveles se ven blockout | environment artist (antes art director si no hay tema y level designer si el mundo no está en `Levels.json`) → builder (integrar `EnvironmentLoader`) | `check_environment.py`, `check_game.py` |
| Mejorar la UI o botones tapados | UI designer (antes art director si no hay tema) → builder si falta estado o un remote | `check_ui.py`, `check_game.py` |
| Que el juego se vea profesional | referencias y assets del usuario (una pregunta) → art director → environment artist (con vistas previas) → builder → UI designer | `factory_status.py`, capturas en Studio |
| Medir algo nuevo | analíticas → builder si faltan llamadas a `Telemetry` | `check_analytics.py` |
| Evento o ajuste en vivo | LiveOps → data architect si el evento da algo que dura → builder si falta un flag o parámetro en Config | `check_liveops.py` |
| Modelar o importar autos 3D (una serie por tiers, una pick-up con caja intercambiable) | [vehicle modeler](../../roblox-vehicle-modeler/SKILL.md) (spec → blockout con aprobación → exportar y `check_vehicle.py` → `collect_models.py`) → el usuario importa a Studio (`VehicleBody.verify`) → builder (catálogo de autos en `Game`, `VehicleBody` en el constructor de autos, sin tocar los cores de manejo ni de tuning) | `check_vehicle.py`, `check_game.py`, Studio |
| Los autos del juego no caben o no se manejan bien al cambiar de modelo | vehicle modeler (medidas y manifest) → level designer / environment artist (espacios más largos que el auto más largo) → builder (perfil de manejo por auto) → data architect si cambian los IDs guardados | `check_vehicle.py`, `validate_levels.py`, Studio |
| Agregar música, efectos o ambiente que cambia con el juego | [audio designer](../../roblox-audio-designer/SKILL.md) (intención y mezcla → cues con aprobación → archivos con `prepare_audio.py` → el usuario sube y da permiso → `Audio.json` y `SoundBank`) → builder (disparos en el cliente y RemoteEvent con el nombre del cue) → UI designer si es sonido de interfaz | `check_audio.py`, `check_game.py`, Studio con auriculares |
| Un audio no se sube o no suena | audio designer (`prepare_audio.py inspect`, límites vigentes, permisos de la experiencia, ID en `Audio.json`) → builder solo si hay IDs en el código para pasar a cues | `check_audio.py`; el usuario lo prueba en Studio |
| Arreglar un script o un bug | builder solo, respetando la arquitectura del juego | El arreglo concreto; `check_game.py` si es un juego de la fábrica |
| "¿Qué le falta?" o "¿en qué estado está?" | Solo `factory_status.py` | — |

Un pedido de una sola etapa ("cambiá el color del botón", "agregá faroles en el nivel 2", "hacé el tema", "agregá un campo al esquema") va directo a ese skill; este skill solo coordina cuando el pedido cruza etapas.

## Cuándo un pedido cambia de recorrido

- El usuario pide publicar: el juego pasa a `release-candidate`. Hacen falta persistencia de lo prometido (data architect con `persistent`), analíticas (recomendado), arte, pase de arte e interfaz (recomendados) y todos los criterios de aceptación del GDD.
- El usuario pide que algo "se guarde" o "no se pierda": entra el data architect aunque el pedido no lo nombre.
- Contenido nuevo que se guarda por ID (misiones, niveles, items, monedas) no cambia el esquema. Un campo que se mueve, se renombra, se borra o cambia de tipo sí: pasa por el data architect y su migración.
- Aparece una compra con Robux: entra el módulo de monetización correspondiente aunque el pedido original no la mencionara; si hay UI designer, la tienda es suya; con Developer Products, el data architect agrega la sección de recibos.
- Un módulo de la librería casi sirve: no se edita la copia del juego (la etapa Librería lo marca); se mejora en la librería con versión nueva y se vuelve a copiar.
- Un core propio no tiene nada del juego y otro juego lo necesita: se publica en la librería en vez de copiarlo a mano.
- Dos sistemas tienen que hablarse: el builder agrega un puente; si alguien propone que un core requiera a otro, es una excepción que se declara en el Mapa de módulos con su motivo.
- Un evento necesita contenido nuevo (una zona, una tienda): el contenido lo diseña el designer y lo construye el builder detrás de un flag; LiveOps solo lo programa.
- LiveOps sobre un prototipo sin persistencia: señálalo antes de seguir, porque los eventos que dan progreso necesitan guardarse.
- Cambia la paleta o se renombra un color: `Environment.json` usa nombres de la paleta, así que el pase de arte se vuelve a validar.
- Se mueve una pieza de un nivel decorado: corre `check_environment.py`; un prop que antes estaba lejos puede quedar al alcance.
- El juego pinta la iluminación o la UI a mano (sin `Style` ni el kit): el builder la reemplaza cuando entran el environment artist o el UI designer, sin tocar la lógica.

## Señales para el modo rápido

A favor: "probar", "rápido", "prototipo", "ver si es divertido", "algo simple", un solo loop, sin publicación a la vista.

En contra: "publicar", "vender", "lanzar", "que se vea profesional", "que se guarde el progreso", monetización pedida, varios sistemas que deben guardarse, un GDD completo entregado por el usuario.
