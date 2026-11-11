# Niveles de TravesurasBrainrot

Fuente: `GDD.md` (Brief de niveles). Datos: `src/shared/Levels.json`. Última validación: 2 de noviembre de 2026, 0 errores, 1 advertencia (los 8 spawns del lobby son a propósito).

Los siete niveles son **La Guarida** (el lobby, un hub social y zona segura) y **seis distritos de una ciudad**, todos en un único place (`project.places: 1`) pero **aislados entre sí**: cada uno está a miles de studs de los demás y se viaja entre ellos con un teletransporte (ver Mapa del mundo y Viajes). No son recorridos con meta: usan el layout `hub` y los saltos del personaje no son el reto, así que el validador no mide saltos. La dificultad del brief la dan los policías, las estrellas y el valor de las travesuras. Lo que sí se diseña aquí es el espacio: calles anchas para correr a 60 studs/s, dónde está cada punto de travesura, cada Guarida y cada escondite, y cómo se llega a cada distrito.

## Métricas del personaje

| walkSpeed | jumpHeight | gravity | Alcance en plano | Subida útil | Salto cómodo (60 %) | Salto normal (80 %) |
| --- | --- | --- | --- | --- | --- | --- |
| 16 (base; sube hasta 60 con el nivel) | 7.2 | 196.2 | 9.67 | 6.70 | 5.8 | 7.7 |

La velocidad sube con el nivel (GDD, "Velocidad"). Por eso la ciudad **no pide saltos precisos**: todo es llano o con rampas, y las únicas piezas con altura son las azoteas del Distrito Queso, que se alcanzan por escalera.

## Curva de dificultad

La dificultad declarada es la del brief del GDD (no hay saltos que medir). Los pasos entre distritos consecutivos nunca superan 2 puntos.

| # | id | Dificultad declarada | Niveles de jugador | Tiempo esperado | Mecánica nueva |
| --- | --- | --- | --- | --- | --- |
| 1 | `barrio-papa` | 2 | 1–5 | ~5 min | Graffiti, Timbrazo, escondites, Patata |
| 2 | `colegio` | 3 | 6–13 | ~24 min | Hidrante, Carrito, Mural Gigante (banda), Tiburón |
| 3 | `playa-podrida` | 4 | 14–19 | ~27 min | Arena lenta, Castillo de arena, Sombrillas, Cafetera |
| 4 | `centro-neon` | 5 | 20–25 | ~34 min | Bocinas, Semáforos, Sinfonía (banda), autos patrulla |
| 5 | `distrito-queso` | 7 | 26–39 | ~99 min | Cajero, Estatua, Caja Fuerte (banda), azoteas, Helicóptero |
| 6 | `puerto-podrido` | 9 | 40–50 | ~84 min | Contenedor misterioso, jefe Comisario Cerebrote |

## Mapa del mundo

Coordenadas absolutas (studs). El suelo de cada nivel es llano (y = 0). **Los niveles no se tocan:** cada uno tiene su `origin` a 5 000 studs de los demás (más que el radio máximo de streaming, 2 048), así que el cliente nunca carga dos a la vez y viajar es un teletransporte. Cada nivel está cerrado por un muro invisible (`limite-1…4`) en todo su borde.

| Nivel | Origen | Tamaño | Rango en X | Rango en Z |
| --- | --- | --- | --- | --- |
| La Guarida (lobby) | (0, 0, 0) | 760 × 760 | −380 a 380 | −380 a 380 |
| Barrio Papa | (−5000, 0, 0) | 600 × 600 | −5300 a −4700 | −300 a 300 |
| Colegio Brainrot | (5000, 0, 0) | 700 × 700 | 4650 a 5350 | −350 a 350 |
| Playa Podrida | (0, 0, 5000) | 1200 × 600 | −600 a 600 | 4700 a 5300 |
| Centro Neón | (0, 0, −5000) | 1400 × 500 | −700 a 700 | −5250 a −4750 |
| Distrito Queso | (5000, 0, 5000) | 900 × 900 | 4550 a 5450 | 4550 a 5450 |
| Puerto Podrido | (−5000, 0, 5000) | 1000 × 800 | −5500 a −4500 | 4600 a 5400 |

## La Guarida (lobby)

Hub social y zona segura: todos aparecen aquí al entrar (8 `spawn` en la plaza, único nivel con spawns habilitados), y nada ni nadie los persigue (zona `lobby`, y los policías no la ven ni entran). Tiene todo lo de una Guarida (depósito, tienda, Ascensión, alijo y 2 Salas de Entrenamiento) y además:

- **6 portales** en un anillo de 150 studs, uno por distrito (`portal-<distrito>`, con `target`). El nivel que exige cada uno está en `src/shared/Destinations.luau`.
- **16 parcelas** (`parcela-1…16`, zona `plot`) en un anillo de 270 studs, cada una con pedestal y cartel: se reclaman con el aviso del pedestal y muestran el nivel, las Ascensiones y los logros de su dueño. Se pueden recorrer para comparar progresos.
- La plaza central (150 × 150) con un pedestal y obelisco con el cartel "LA GUARIDA".

## Viajes

Todos los viajes pasan por un método del servidor, `Transit.to(jugador, destino)` (`src/server/Game/Transit.luau`), con los destinos de `src/shared/Destinations.luau`. Un destino con `placeId` viaja a otro place en vez de mover al personaje; hoy ninguno lo tiene.

| Desde | Cómo | Exige |
| --- | --- | --- |
| Lobby → distrito | Portal `portal-<distrito>` (zona `portal` con `target`) o el menú "La Guarida" (H) | Nivel del distrito, sin estrellas, sin arresto ni travesura en curso |
| Distrito → lobby | Portal `portal-lobby` junto a una Guarida del distrito, o el menú | Sin estrellas, desde una Guarida o un portal |

| Distrito | Nivel | Pieza de portal en el lobby |
| --- | --- | --- |
| Barrio Papa | 1 | `portal-barrio-papa` |
| Colegio Brainrot | 6 | `portal-colegio` |
| Playa Podrida | 14 | `portal-playa-podrida` |
| Centro Neón | 20 | `portal-centro-neon` |
| Distrito Queso | 26 | `portal-distrito-queso` |
| Puerto Podrido | 40 | `portal-puerto-podrido` |

Ya no hay vallas (`puerta-*`), carteles de aviso (`aviso-puerta-*`) ni calles de conexión (`conexion-*`): el nivel se exige al viajar.

## Vocabulario de zonas

Todo lo jugable son piezas `zone` con `name`. El builder las convierte en puntos de juego por su `name` y el `id` identifica cada instancia (por ejemplo `mischief-graffiti-3`).

| `name` | Tamaño típico | Qué hace el juego |
| --- | --- | --- |
| `distrito` | todo el distrito | Límites del distrito, nivel mínimo en la `note` y preset de iluminación |
| `guarida` | 24 × 8 × 24 | Zona segura: depósito de Botín, tienda, reaparición y alijo. Los policías no entran |
| `afk` | 14 × 8 × 14 | Volumen `AfkZone` de la Sala de Entrenamiento (6 jugadores). Se activa desde el nivel 8 |
| `payspray` | 20 × 8 × 20 | Lavadero Pay'n'Spray |
| `cop_spawn` | 10 × 4 × 10 | Aparición de los caminantes (patrulla ambiental), fuera de la vista inmediata; también su destino |
| `guard_post` | 3 × 4 × 3 | Punto de ruta de una guardia fija. Campos: `post` (la travesura que vigila), `order` (1, 2…) y `cop` (tipo de policía); el giro Y de la zona es hacia dónde mira |
| `heli_spawn` | 10 × 4 × 10 | Aparición del Helicóptero Banana (★5) |
| `comisario_spawn`, `arena_jefe` | 10 × 4 × 10, 180 × 12 × 140 | Jefe ★6 y su plaza |
| `hide` | 6 × 6 × 6 | Escondite para perder las estrellas. Campo opcional `hideKind`: `bush` (arbusto, por defecto) o `container` (contenedor); ver «Escondites» |
| `cubierta` | 30 × 20 × 40 | Zona cubierta: el Helicóptero no ve a quien está debajo |
| `sand` | toda la arena | Zona de arena (`World.SandSpeedMult`) |
| `portal` | lobby (uno por distrito) y junto a una Guarida de cada distrito | Viaje: `target` es el id del destino (ver Viajes) |
| `plot` | lobby | Parcela reclamable (16) |
| `lobby` | lobby entero | Zona segura: cuenta como Guarida para la patrulla, el depósito y la tienda |
| `mischief_graffiti`, `mischief_timbrazo` | 8 × 8 × 8 | Travesuras de nivel 1 |
| `mischief_hidrante`, `mischief_carrito` | 8–10 | Travesuras de nivel 6 |
| `mischief_castillo`, `mischief_sombrillas` | 10 × 8 × 10 | Travesuras de nivel 14 (Playa) |
| `mischief_bocinas`, `mischief_semaforos` | 30 × 8 × 10, 10 × 8 × 10 | Travesuras de nivel 20 (Centro) |
| `mischief_cajero`, `mischief_estatua` | 8, 14 | Travesuras de nivel 26 (Distrito Queso) |
| `mischief_contenedor` | 10 × 8 × 10 | Travesura de nivel 40 (Puerto) |
| `coop_mural`, `coop_sinfonia`, `coop_cajafuerte` | 40 × 12 × 8, 40 × 8 × 16, 10 × 8 × 30 | Travesuras de banda (2–8, 3–8 y 4–8 jugadores) |
| `tutorial_graffiti`, `tutorial_cop_spawn`, `tutorial_hide` | — | Pasos guionados del onboarding en el Barrio |

### Guardias de las travesuras

Cada travesura tiene un puesto de dos puntos (`guard_post`, ids `guard-<travesura>-1/2`): el primero a 8–12 studs del borde de la travesura con vista libre hacia ella, el segundo a 14–28 studs del primero por calle libre (generados con comprobación contra edificios, muros y zonas seguras). La guardia mira hacia la travesura en cada punto. **Barrio Papa** deja solo dos travesuras custodiadas (`mischief-graffiti-4` y `mischief-timbrazo-3`); los demás distritos custodian todas.

| Distrito | Puestos | Tipos de guardia |
| --- | --- | --- |
| Barrio Papa | 2 de 11 travesuras | Patata |
| Colegio Brainrot | 17 | Patata, Capibara |
| Playa Podrida | 14 | Capibara, Tiburón |
| Centro Neón | 18 | Tiburón, Capibara |
| Distrito Queso | 9 | Tiburón, Cafetera |
| Puerto Podrido | 5 | Cafetera, Tiburón |

### Escondites

Un escondite no es solo una zona: necesita un **prop visible** que llene la zona (un arbusto grande o un contenedor, del pase de arte), y se coloca para que sea **alcanzable** durante una persecución.

- **Tipos.** `bush` (arbusto) esconde de los policías de tierra salvo la K-9 de cerca; `container` esconde también de la K-9 pero solo 12 s (reglas completas en el GDD, «Esconderse»). Ninguno esconde del Helicóptero: eso lo hace `cubierta`.
- **Densidad (estándar para todos los distritos).** Desde cualquier punto de calle debe haber un escondite a **≤ 60 studs**: cobertura ≥ 95 % de los puntos transitables y peor punto a ≤ 85 studs. Barrio Papa tenía 10 (29 % de cobertura, peor punto a 234 studs); ahora tiene 31 (95,6 %, peor punto a 82 studs, sin contar la franja exterior de 2 studs junto al muro del límite, que no se puede pisar).
- **Mezcla.** Al menos 5 `container` por distrito (los contenedores sirven contra la K-9 de ★4+), el resto `bush` en parques, jardines y laterales de las manzanas.
- **Ubicación.** En esquinas, callejones y traseras, **no en medio de la calle** ni dentro de una Guarida, ni a menos de 12 studs de un `cop_spawn` o un `guard_post`.
- **Tutorial.** `tutorial_hide` es un `bush` y coincide con el prop resaltado del paso `first_escape`.

Cantidades por distrito:

| Distrito | Guaridas | Escondites | Policías | Travesuras individuales | Travesuras de banda |
| --- | --- | --- | --- | --- | --- |
| Barrio Papa | 2 | 31 | 6 | 5 graffiti, 6 timbrazo | — |
| Colegio | 2 | 10 | 6 | 3 graffiti, 3 timbrazo, 5 hidrante, 4 carrito | 2 Mural Gigante |
| Playa Podrida | 3 | 10 | 6 | 3 graffiti, 6 castillo, 5 sombrillas | — |
| Centro Neón | 3 | 10 | 8 | 3 graffiti, 3 hidrante, 4 bocinas, 6 semáforos | 2 Sinfonía |
| Distrito Queso | 3 | 12 | 8 (+ 2 helicópteros) | 5 cajero, 3 estatua | 1 Caja Fuerte |
| Puerto Podrido | 2 | 10 | 8 (+ 2 helicópteros) | 5 contenedor | — |

## Nivel por nivel

### `barrio-papa` · Barrio Papa

- **Intención:** enseñar el loop sin riesgo: travesura → estrella → escape → depósito.
- **Recorrido:** se llega por el portal `portal-barrio-papa` del lobby y se aparece en `spawn-1`, junto a la Guarida `guarida-1` (−110, −110) del distrito (sus spawns están deshabilitados: solo el lobby recibe a los jugadores al entrar). El muro del tutorial (`tutorial-graffiti`, a ~26 studs) se ve desde ahí. La Patata guionada aparece en la calle (−110, −230) y el arbusto de escape está cerca (−143, −45), sobre la acera.
- **Ritmo:** manzanas de 160 × 160 con calles de 60: todo queda a pocos segundos. Sin azoteas, sin sorpresas.
- **Riesgos justos:** solo la Patata (más lenta que el jugador); no hay peligros de caída.
- **Notas para el builder:** `portal-lobby` (regreso a La Guarida) está junto a `guarida-1`.

### `colegio` · Colegio Brainrot

- **Intención:** primeras travesuras con herramienta: hidrante (patio y calle) y carrito (cantina). Aparece el Mural Gigante para la banda.
- **Recorrido:** 3 × 3 manzanas con calles de 65. La manzana central es el colegio (edificio + patio abierto de 170 × 100). Los blancos son objetos y adultos NPC, nunca alumnos.
- **Ritmo:** Tiburón (★3) obliga a usar callejones. Los murales grandes están en las manzanas con paredes de ≥ 150 studs.
- **Notas para el builder:** `portal-lobby` (regreso a La Guarida) está junto a `guarida-1`.

### `playa-podrida` · Playa Podrida

- **Intención:** hacer elegir entre la arena (lenta, −15 %, con castillos y sombrillas) y el paseo marítimo (recto y rápido).
- **Recorrido:** de norte a sur: calle costera, paseo de madera (1200 studs, 60 de ancho), kioscos y arena. Las Guaridas están sobre el paseo cada 400 studs. Las travesuras de la Playa están en la arena.
- **Ritmo:** la Cafetera (★4) alcanza a quien se queda en la arena. El paseo es la vía de escape.
- **Notas para el builder:** `sand` es la zona de arena para `World.SandSpeedMult`; solo afecta a unidades terrestres.

### `centro-neon` · Centro Neón

- **Intención:** velocidad. La avenida central mide 1400 × 70 studs sin curvas.
- **Recorrido:** avenida de oeste a este, tres calles transversales y rascacielos pastel de 50 a 110 studs. Autos estacionados a ambos lados para las Bocinas; semáforos en las esquinas para los autos patrulla.
- **Ritmo:** el jugador cruza el distrito en ~25 s a velocidad máxima: muy corto para escapar, así que los escondites importan.
- **Notas para el builder:** `mischief_semaforos` atasca los autos patrulla de la esquina durante 20 s; la `coop_sinfonia` va en la fila de autos de los extremos.

### `distrito-queso` · Distrito Queso

- **Intención:** primer distrito vertical y contra el Helicóptero (★5): hay que esconderse bajo cubierta o por azoteas.
- **Recorrido:** manzanas altas (80 a 180 studs), calle central de 80 studs alineada con el Centro, 3 azoteas alcanzables con escalera y 4 `cubierta`. El Banco de Queso es la manzana este del centro y tiene la `coop_cajafuerte`.
- **Ritmo:** más estrecho que el Centro, con cruces cortos para romper la línea de vista del Helicóptero.
- **Notas para el builder:** las `truss` miden 2 × N × 2 con N par; las azoteas son `platform` independientes sobre el edificio.

### `puerto-podrido` · Puerto Podrido

- **Intención:** distrito final: contenedores, una grúa y la plaza del jefe (★6).
- **Recorrido:** 4 × 3 pilas de contenedores separadas por calles de 60. La plaza `arena_jefe` está en el centro; el Comisario Cerebrote aparece en `comisario_spawn`.
- **Ritmo:** las pilas son de referencia (cada una se divide en contenedores en el pase de arte). Hay galpones `cubierta` para despistar al Helicóptero.
- **Notas para el builder:** `puerto-podrido` es el último distrito; al alcanzar el nivel 50 se ofrece la Ascensión (GDD).

## Validación

`validate_levels.py`: 0 errores, 0 advertencias. 7 niveles (lobby + 6 distritos), 548 piezas en total (presupuesto de 2500). No hay saltos que medir (todos los niveles son `hub`); las únicas piezas con altura son 3 azoteas alcanzables por escalera.

No cubierto por el validador y a probar en Studio:

- Que cada portal lleve al spawn correcto, que el nivel se exija al viajar y que desde el lobby no se vea ningún distrito (streaming).
- Que las calles se sientan amplias a 60 studs/s, sobre todo en curvas y cruces del Centro Neón y el Distrito Queso.
- Que el cono de visión de los policías no atraviese los edificios de referencia.
- Que la arena baje la velocidad de jugador y policías terrestres.

## Suposiciones y pendientes

- **Suposición:** los edificios y las pilas de contenedores son bloques de referencia (`prop`); el pase de arte los reemplaza sin mover las calles ni las zonas.
- **Suposición:** las posiciones de los puntos de travesura y escondites son una primera colocación sobre las aceras; se ajustan al jugar.
- **Suposición:** `Levels.json` se generó con un script de colocación y se mantiene a mano desde ahora.
- level-designer → builder: construir el mundo desde `Levels.json`: piezas `platform`, `prop`, `wall` y `truss`, y tratar cada `zone` por su `name` según el vocabulario (abierto)
- level-designer → builder: los portales (`portal`, con `target`) llevan al destino con `Transit.to`; el nivel lo exige el servidor (resuelto)
- level-designer → game-designer: el brief decía "~99 min" para el Distrito Queso con una calle central; la distancia entre Guaridas allí es de 400 studs (≈ 7 s a velocidad máxima): si el jefe del Distrito debe sentirse más lejos, agrandar el distrito (abierto)
- level-designer → environment-artist: vestir los seis distritos con el preset de iluminación indicado en cada `distrito` (abierto)
