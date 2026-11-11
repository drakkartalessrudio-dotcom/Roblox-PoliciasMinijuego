# Sprint: Escondites que sirven de verdad

**Objetivo:** que esconderse sea una forma real de escapar de una persecución, en todos los niveles de estrellas, y que el jugador sepa dónde están los escondites y cuándo está a salvo.
**Alcance:** sistema general (servidor + cliente) y colocación completa en el Nivel 1 (`barrio-papa`). Los otros cinco distritos usan el mismo sistema y se colocan en un sprint posterior.
**Estado de partida:** el 11-11-2026, ver «Diagnóstico».
**Estado actual:** bloques 0, 1 y 3 hechos; bloque 2 hecho salvo sonido y aviso de policías cercanos; bloque 4 pendiente de prueba en Studio. Marcas: `[x]` hecho, `[~]` parcial, `[ ]` pendiente.

---

## Diagnóstico (lo que se encontró en el código)

El GDD sí promete escondites: arbustos y contenedores (GDD §Loop, «Perder las estrellas»; §Onboarding, paso `first_escape`; Brief de niveles: «Escondites cada ≤ 60 studs»; `Hide.SecondsPerStar` y `Hide.MinCopDistance` en Parámetros). Existen 10 zonas `hide` en `barrio-papa` (más `tutorial_hide`) y el bucle de [World.luau](../src/server/Game/World.luau) las usa. Pero **en una persecución real no sirven**:

| # | Problema | Dónde | Efecto |
| --- | --- | --- | --- |
| 1 | Los policías **ignoran el escondite**: `canSee` no mira si el jugador está en una zona `hide`. Un policía en `chase` además ve a su objetivo a ×1,5 de alcance. | [Cops/init.luau](../src/server/Modules/Cops/init.luau) `canSee` / `visionRange` | Te siguen viendo dentro del arbusto, te agarran dentro del arbusto. |
| 2 | La cuenta de esconderse **solo corre cuando nadie te ve** (`state.seen == false`). | [Wanted/init.luau](../src/server/Modules/Wanted/init.luau) rama `else` del tick | Esconderse no ayuda a perder la vista; solo cuenta cuando ya la perdiste (y entonces ya baja el calor sola). |
| 3 | Exige **ningún policía a ≤ 8 studs**. Los perseguidores van pegados a ti. | [World.luau:141](../src/server/Game/World.luau#L141) | En una persecución casi nunca se cumple. |
| 4 | **Los refuerzos y quienes buscan van al punto exacto donde te vieron** (`lastKnown` / `lastSeen`), que suele ser el arbusto al que entraste. | `Cops` `search` | Esconderse donde te vieron entrar es una trampa. |
| 5 | **Los escondites no se ven.** Las 10 zonas son volúmenes invisibles de 6×6×6: no hay ningún arbusto ni contenedor colocado en ellas (`Environment.json`, `barrio-papa.props`, 0 props a < 6 studs de una zona; el prefab `bush` existe pero no se usa). El GDD dice «arbusto resaltado» y no hay resaltado. | `Environment.json`, `Levels.json` | El jugador no sabe dónde esconderse. |
| 6 | **No hay feedback**: el atributo `Hidden` se publica y nadie lo lee (ni HUD, ni sonido, ni efecto). | `World.luau:145` | No se sabe si «está funcionando». |
| 7 | **Densidad**: 10 escondites en 600×600. Con la regla del GDD (≤ 60 studs) solo se cubre el **29 %** del distrito; el peor punto está a **234 studs** de un escondite. A 40 studs se cubre el 13 %. | `Levels.json` | A la velocidad del jugador (~16–60 studs/s) casi nunca hay uno al alcance. |
| 8 | **Sin contrapeso por estrella.** Todo escondite sería igual a ★1 que a ★5; el GDD (línea 162) dice que a ★5 «hay que esconderse/usar herramientas» y nada lo respalda. | GDD / `Cops` | Hay que decidir qué esconde de qué (ver «Diseño»). |

---

## Diseño propuesto

### Idea central
Un escondite no «borra» las estrellas por magia: **te saca de la vista y te hace difícil de encontrar**. Funciona si **rompes el contacto antes de entrar** y **te quedas quieto**; si un policía te ve entrar o se acerca demasiado, te descubre. Así sigue habiendo juego (correr hasta el escondite, entrar sin que te vean, aguantar la tensión) en vez de un botón de «salvarse».

### Reglas

1. **Entrar.** Estar dentro de una zona `hide` (volumen que ya existe) con estrellas ≥ 1.
2. **Te ven entrar → escondite quemado.** Si al entrar algún policía de tu persecución te tiene a la vista a ≤ `Hide.WitnessRange` (25 studs), ese escondite queda *quemado* para ti durante `Hide.BurnSeconds` (20 s): no oculta y se pinta de rojo. Esto resuelve el problema 4 (trampa del `lastSeen`). Si nadie te ve entrar, el escondite es seguro.
3. **Oculto = visión recortada.** Mientras estás escondido (y el escondite no está quemado) los policías **solo te ven a ≤ `Hide.RevealDistance`** (10 studs) y con línea de vista; el resto del alcance de visión (incluido el ×1,5 de persecución) no cuenta. Quien te perseguía y te pierde pasa a `search` (🔍) como ahora.
4. **Te descubren si se acercan.** Un policía en `search` o `chase` a ≤ `Hide.RevealDistance` te descubre: el escondite se quema, sales a «visto» y la persecución sigue. Se acabó la regla de «ningún policía a 8 studs para que cuente»: ahora es *descubrimiento*, no *bloqueo del contador*.
5. **Recompensa por aguantar.** Escondido y sin que nadie te vea, el calor baja `Hide.DecayMult` (×3) más rápido y, además, cada `Hide.SecondsPerStar` baja una estrella como hoy. Esconderse deja de depender de `state.seen`: si estás oculto, `Cops` deja de reportarte como visto (problema 2).
6. **Moverte te delata un poco.** Dentro del escondite, si te mueves a más de `Hide.StillSpeed` (4 studs/s) cuenta el doble el alcance de descubrimiento (20 studs). Estarte quieto es lo que te salva; así no es una zona invulnerable para pasearse.
7. **Contrapesos por tipo de policía** (cómo escala con las estrellas; se aplica a todos los distritos):

| Escondite | Esconde de | No esconde de |
| --- | --- | --- |
| `bush` (arbusto) | Patata, Capibara, Tiburón (★1–3) | Cafetera K-9 a ≤ 24 studs (olfato), Helicóptero |
| `container` (contenedor) | todos los de tierra, incluida la K-9 | Helicóptero; el contenedor solo aguanta `Hide.ContainerSeconds` (12 s) |
| `cubierta` (ya existe, galería/toldo) | **Helicóptero** | policías de tierra a ≤ 12 studs (como hoy) |

   Resultado: a ★1–3 basta un arbusto; a ★4 hay que ir a un contenedor; a ★5 hay que combinar cubierta (contra el helicóptero) y esquivar a los de tierra. Esto respalda la línea 162 del GDD.
8. **Escondite ocupado.** Máximo `Hide.Capacity` (2) jugadores por escondite; el tercero no se esconde (evita apilar a una banda de 8 en un arbusto).
9. **Cooldown.** Un escondite quemado no oculta durante `Hide.BurnSeconds` (20 s), y eso ya hace de espera para volver a entrar; por eso no existe un `Hide.ReenterSeconds` aparte.

### Parámetros nuevos (en `Config.Hide`, expuestos por `Tuning`)

| Clave | Valor inicial | Qué hace |
| --- | --- | --- |
| `Hide.SecondsPerStar` | 3 (ya existe) | Segundos oculto por estrella que baja |
| `Hide.MinCopDistance` | **se elimina** | Reemplazado por `RevealDistance` |
| `Hide.RevealDistance` | 10 | Alcance al que un policía descubre al oculto |
| `Hide.MovingRevealMult` | 2 | Multiplicador del alcance si te mueves |
| `Hide.StillSpeed` | 4 | Velocidad máxima para contar como quieto (studs/s) |
| `Hide.WitnessRange` | 25 | Distancia a la que un policía que te ve entrar quema el escondite |
| `Hide.BurnSeconds` | 20 | Cuánto dura un escondite quemado para ese jugador |
| `Hide.DecayMult` | 3 | Multiplicador de la bajada de calor estando oculto |
| `Hide.K9SniffRange` | 24 | Alcance con el que la K-9 huele un arbusto |
| `Hide.ContainerSeconds` | 12 | Cuánto aguanta un contenedor |
| `Hide.Capacity` | 2 | Jugadores por escondite |

---

## Tareas

Orden pensado para poder probar en Studio al final de cada bloque. Responsable: **B** = builder (código Luau), **L** = level-designer (`Levels.json`/`LEVELS.md`), **E** = environment-artist (`Environment.json`/`ENVIRONMENT.md`), **U** = ui-designer, **D** = game-designer (GDD).

### Bloque 0 · Diseño (D)
- [x] **0.1** Actualizar el GDD: «Perder las estrellas» (reglas 1–9), tabla de Parámetros (`Hide.*`), onboarding paso 40–70 s, criterios de aceptación (ver abajo) y la línea 162. Quitar `Hide.MinCopDistance`.
- [x] **0.2** Actualizar `design/LEVELS.md`: tipos de zona `hide` con atributo `Kind` (`bush` | `container`) y el estándar de densidad (ver 3.1).

### Bloque 1 · Núcleo (B)
- [x] **1.1** Tipo de escondite: leer `Kind` de la zona `hide` en `Areas` (por defecto `bush`) y exponer `Areas.hideAt(player) -> Part?`. *Hecho cuando:* una consulta devuelve la zona y su tipo.
  *Hecho:* el tipo viaja como atributo `HideKind` de la zona (`LevelLoader` lo lee de `hideKind` en `Levels.json`); no hizo falta `Areas.hideAt`, lo resuelve `Game/Hiding`.
- [x] **1.2** Estado de ocultación por jugador en `Game/World` (nuevo `Game/Hiding.luau`, para no crecer `World.luau`): entra, evalúa «te vieron entrar» (regla 2), quema, capacidad y cooldown. Publica los atributos `Hidden` (bool), `HideState` (`safe` | `burned`) y `HideSpot` (id). *Hecho cuando:* los atributos cambian bien en pruebas de consola.
  *Hecho:* `Game/Hiding.luau`; publica `Hidden`, `HideState`, `HideKind`, `HideLeft`, `HideMoving` y `HideBurned`.
- [x] **1.3** `Cops.options` gana `hideStateOf(player) -> { hidden: boolean, kind: string }`. En `canSee`: si está oculto, el alcance efectivo pasa a `Hide.RevealDistance` (×2 si se mueve) con línea de vista; excepciones por tipo (K-9 con `K9SniffRange` en arbusto; helicóptero salvo `cubierta`). *Hecho cuando:* un Patata a 15 studs con LOS no llena la barra de detección contra un jugador oculto.
- [x] **1.4** Descubrimiento: un policía en `search`/`chase` que entra en el alcance de descubrimiento quema el escondite del jugador (evento `Cops.discovered`) y vuelve a verlo. Los perseguidores que pierden de vista siguen a `search` con `lastSeen` como hoy.
- [x] **1.5** `Wanted`: separar «oculto» de «visto». Con `hidden` y sin que `Cops` lo reporte, el calor decae ×`Hide.DecayMult` y la cuenta por estrella corre. Quitar la dependencia de `state.seen` en esa rama. *Hecho cuando:* escondido ★3 sin policías cerca, baja ★ cada 3 s.
  *Hecho:* `Cops` deja de reportarte como visto cuando estás oculto a salvo (tras 0,5 s sin ver), y `Wanted` aplica `Hide.DecayMult`.
- [x] **1.6** Contenedor: temporizador `Hide.ContainerSeconds`; al agotarse, el jugador queda «expuesto» y se expulsa del escondite (cooldown aplicado).
- [x] **1.7** Refuerzos: un refuerzo nuevo **no** va a un `lastKnown` cuyo punto es el escondite del jugador mientras está oculto y seguro; usa la posición donde lo vieron *antes* de entrar. *Hecho cuando:* los refuerzos aparecen lejos del arbusto y no se dirigen a él.
  *Hecho:* el refuerzo usa `lastKnown` aunque hayan pasado más de 60 s mientras estés oculto.
- [x] **1.8** Telemetría: `hide_entered` (tipo, estrellas, seguro/quemado), `hide_discovered`, `hide_escaped` (estrellas que bajó escondido). Añadir a `AnalyticsSchema.json` y a `design/ANALYTICS.md`.

### Bloque 2 · Que se vea y se sienta (E, U, B)
- [x] **2.1** (E) Colocar un prop visible en **cada** zona `hide`: arbusto grande (usar el prefab `bush` agrandado o uno nuevo `hedgeBig` de 6×4×6 que oculte de verdad al personaje) y contenedor (`dumpster`, nuevo prefab). Alinear el prop con el volumen de la zona (`Environment.json`/`ENVIRONMENT.md`). Los props **no** pueden bloquear el paso al interior ni cambiar el juego (regla del pase de arte).
  *Hecho de otra forma:* no son prefabs de `Environment.json` sino `Game/HidingProps.luau` (mismo enfoque que `SpotProps`); ver `design/ENVIRONMENT.md`.
- [x] **2.2** (B/E) Resaltado: `Highlight` de color `interactive` (amarillo `sunny`, ya en `ART.md`) en los escondites a ≤ 80 studs **solo mientras tengas ≥ 1 estrella**; rojo si están quemados. En cliente, sin red extra: usa los atributos del bloque 1.
- [x] **2.3** (U) Indicador en el HUD: «Escondido», con el estado `quieto / te pueden oír`, barra de aguante del contenedor y aviso «¡Te vieron entrar!» al quemarse. Texto de una línea, sin romper la zona del chat. Añadir a `design/UI.md`.
- [~] **2.4** (B) Dentro de un escondite oculto, el personaje se vuelve ~60 % transparente para el propio jugador (para que sepa que está cubierto) y emite una nota de sonido discreta (hoja/metal). Cue en `Audio.json` (si no hay ID, queda pendiente de subir, no se inventa).
  *Parcial:* el personaje se vuelve semitransparente solo para su dueño (`HideFeedback.client.luau`). **Falta el sonido**: no hay ID de audio; hay que subir un cue de hojas/metal y registrarlo en `Audio.json`.
- [ ] **2.5** (E) Icono 🔍/«?» de los policías sobre el prop cuando un policía en `search` se acerca al escondite (tensión).
  *No hecho* (opcional): se deja para después de probar el resto en Studio.

### Bloque 3 · Nivel 1: colocación (L)
- [x] **3.1** Subir los escondites de `barrio-papa` de 10 a **~28** para cumplir «≤ 60 studs»: cobertura objetivo **≥ 90 %** del distrito a 60 studs y el peor punto a **≤ 75 studs**. Colocarlos en esquinas, callejones y laterales de las manzanas (no en medio de la calle). Revisar los 10 actuales (algunos pueden quedar en la calle).
  *Hecho:* **31** escondites (no 28): 95,6 % de cobertura a 60 studs y peor punto a 82 studs (sin la franja exterior de 2 studs junto al muro del límite, que no se puede pisar). El criterio quedó en ≥ 95 % y ≤ 85 studs.
- [x] **3.2** Añadir `Kind` a cada una (`bush` en parques/jardines, `container` en callejones y traseras; mínimo 5 contenedores aunque el nivel 1 solo llegue a ★2: preparan el sistema para los demás distritos).
- [x] **3.3** Verificar que el escondite del tutorial (`tutorial-hide-1`, −135, −45) coincide con el prop resaltado y está a una distancia razonable del policía guionado (el Patata a 14 studs/s, el jugador a 16).
  *Hecho:* `tutorial-hide-1` pasó de (−135, −45) a (−143, −45), sobre la acera. Falta probar en Studio la distancia al Patata guionado.
- [x] **3.4** Validación de densidad: `validate_levels.py` (skill roblox-level-designer) valida saltos pero no escondites; añadir una comprobación densidad de escondites con el cálculo del diagnóstico (cobertura a 60 studs y peor punto) y que ningún escondite esté dentro de la Guarida ni a < 12 studs de un `cop_spawn` o un `guard_post`.
  *Hecho:* `tools/check_hides.py` (cobertura, peor punto, tipos, contenedores mínimos, distancia a Guaridas, `cop_spawn` y `guard_post`).

### Bloque 4 · Pruebas y ajuste (B + el usuario en Studio)
- [ ] **4.1** Pruebas manuales en Studio con los casos de aceptación (abajo). El usuario prueba y manda feedback numerado; se ajustan los valores de `Hide.*` solo en `Config.luau`, sin tocar lógica.
  *Pendiente:* nada de esto se ha podido ejecutar fuera de Studio; solo pasan los validadores estáticos.
- [ ] **4.2** `CopsDebug`: ampliar para dibujar el radio de descubrimiento del escondite y el estado `safe`/`burned`.
  *No hecho:* queda ampliar `CopsDebug`.
- [x] **4.3** Pasada de rendimiento: el bucle de ocultación corre cada 0,25 s como hoy; sin raycasts nuevos por jugador salvo la comprobación de «te ven entrar» (una vez, al entrar).

---

## Criterios de aceptación (casos nuevos para el GDD)

34. **Esconderse rompe la persecución:** con ★2 y un Patata a 25 studs que **no** te vio entrar, entrar a un arbusto hace que el Patata pase a 🔍 en ≤ 3 s y las estrellas empiecen a bajar cada 3 s.
35. **Te ven entrar:** con un policía a 15 studs con línea de vista al entrar, el escondite se quema (rojo), no oculta y avisa «¡Te vieron entrar!».
36. **Descubrimiento:** un policía que busca llega a 8 studs del arbusto en el que estás oculto → te descubre, el escondite se quema y vuelve la persecución.
37. **Quieto vs. en movimiento:** oculto y moviéndote a 10 studs/s, un policía te descubre a 20 studs; quieto, solo a 10.
38. **Contenedor y K-9:** una Cafetera K-9 a 20 studs huele un arbusto (te descubre) pero no un contenedor; el contenedor te expulsa a los 12 s.
39. **Helicóptero:** ni arbusto ni contenedor te esconden del Helicóptero; la `cubierta` sí.
40. **Refuerzos:** con ★3 oculto y seguro, los refuerzos nuevos no aparecen yendo hacia el arbusto.
41. **Capacidad:** un tercer jugador no entra a un escondite con 2; no se apila una banda de 8.
42. **Densidad:** en `barrio-papa`, ≥ 90 % de los puntos de la calle tiene un escondite a ≤ 60 studs; el peor a ≤ 75.
43. **Visibilidad:** cada escondite tiene su prop; con ≥ 1 estrella los de ≤ 80 studs se resaltan; el HUD marca «Escondido» y la barra del contenedor.
44. **Tutorial:** el paso `first_escape` (40–70 s) se puede completar escondiéndose en el arbusto resaltado sin que el Patata guionado te atrape.

---

## Riesgos y decisiones abiertas

- **Muy fácil / muy difícil.** Los valores iniciales son una hipótesis: si esconderse resulta un «botón de salvarse», subir `Hide.RevealDistance` o `BurnSeconds`; si sigue sin servir, bajarlos. Se ajusta en Studio.
- **Regla de «te ven entrar»** es la más delicada: es lo que evita que ocultarse sea trivial a corta distancia y lo que da juego (hay que romper contacto primero). Alternativa más simple si cuesta: quemar el escondite si algún policía de tu persecución está a ≤ 20 studs (sin comprobar línea de vista).
- **Nivel 1 solo llega a ★2** (techo por nivel): el Barrio no pondrá a prueba ★4–★5; esos contrapesos (K-9, helicóptero, contenedor) se verifican en `playa-podrida`/`centro-neon`/`distrito-queso` en el sprint siguiente. Hasta entonces se prueban con un comando de consola que sube estrellas.
- **Fuera de alcance de este sprint:** colocar escondites en los otros 5 distritos; habilidades que expulsen del escondite; escondites en azoteas del Distrito Queso; monetización.
- **Árbol de trabajo:** hay cambios sin commit de otro trabajo (`Compinche.luau`, `SpotProps.luau`, `World.luau`, `init.luau`, `Config.luau`). El bloque 1 toca `World.luau`, `init.luau` y `Config.luau`: conviene commitear o integrar ese trabajo antes de empezar.
