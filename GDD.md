---
project:
  name: TravesurasBrainrot
  mode: release-candidate
  genre: simulator # referencia principal; mezcla persecución/sigilo estilo "estrellas" (ver Concepto)
  places: 1
  platforms: [desktop, mobile, tablet]
design:
  levels: true
  art: true
  environment: true
  ui: true
  data: true
data:
  persistence: persistent # fijado por roblox-data-architect (ver design/DATA.md)
monetization:
  enabled: [game-passes, developer-products]
analytics:
  enabled: true
liveops:
  enabled: false # posterior: eventos de temporada (ver Contenido y alcance); requiere persistencia ya diseñada
---

# TravesurasBrainrot — GDD

> Estado: **diseño v1**. Todo lo marcado **Suposición** lo agregó el game designer para completar vacíos del pedido y se puede cambiar sin romper el resto. Las cifras de tiempo y economía son **estimaciones de diseño**, no datos observados.

## Concepto

**Fantasía.** Eres un travieso en una ciudad llena de policías *brainrot*: haces travesuras (pintar paredes, tocar timbres y salir corriendo, abrir hidrantes, tocar bocinas…), los policías que te ven te persiguen y, cuanto más alboroto armas, más **estrellas de búsqueda** (hasta 6) y más dinero ganas, pero más te arriesgas a perder el botín. Escapar, esconderte y derribar policías es tan divertido como la travesura.

**Pilares** (cada sistema del MVP refuerza al menos uno):

1. **Riesgo = recompensa.** Más estrellas → más dinero y XP por travesura, pero el botín sin depositar se puede perder.
2. **Velocidad es poder.** Subir de nivel te hace más rápido; ser más rápido significa que te agarran menos, llegas a más travesuras por minuto y puedes embestir policías más fuertes.
3. **Caos cómico, nunca crueldad.** Todo es slapstick (tartas, bananas, bocinas); los policías son criaturas *brainrot* absurdas, sin sangre ni armas realistas.

**Público y sesión.** Jugadores de Roblox de 9 a 16 años, sobre todo en celular (**Suposición**). Sesión objetivo: 20–30 min (una travesura/persecución dura 30–90 s, así que el loop encaja en ratos cortos). Hasta 16 jugadores por servidor, con **bandas co-op de hasta 8** (dos bandas completas).

**Género.** Simulador de progresión (niveles, mejoras, prestigio: ver [simulador](../.claude/skills/roblox-game-designer/references/genres/simulator.md)) mezclado con persecución tipo GTA. El corazón del diseño es la curva de progresión y la sensación de la persecución, así que ahí está el detalle.

## Loop principal

**Momento a momento (segundos).** Buscas un punto de travesura → haces el minijuego (3–12 s) → ganas **Botín** (dinero sin depositar) y XP → si un policía te vio, aparece ★ y te persiguen → decides: correr, esconderte, usar una herramienta o derribar policías.

**Sesión (minutos).** Ciclo "travesura → persecución → escape → depósito en la Guarida". El jugador decide cuánto Botín acumular antes de depositar: cada travesura más es más dinero, pero también más calor y más a perder. Termina cuando el jugador sale; no hay "fin de ronda". Meta de sesión visible: la siguiente mejora o el siguiente nivel (barra siempre en pantalla).

**Regreso (días).** Nivel → distritos y estrellas nuevas; mejoras; **Ascensión** (prestigio) con multiplicador permanente y árbol de Cerebros; misiones diarias, cartel semanal, álbum de graffitis y cosméticos. Es una **hipótesis** que se valida con D1/D7 (ver KPIs).

**Reglas del loop**

- **Botín vs Dinero.** Lo que ganas va a **Botín** (se ve en el HUD, tope de capacidad). Se convierte en **Dinero** al depositarlo en una **Guarida** (mantener 1,5 s, sin estar buscado). Solo el Dinero se gasta y se conserva siempre.
- **Pérdida (arresto).** Si un policía te agarra: pierdes el 40 % del Botín (60 % con 5★ o más, mínimo 10 % con mejoras), reapareces en la Guarida más cercana tras 5 s (se acorta tocando rápido), te quedas sin estrellas. **Nunca** pierdes Dinero ya depositado, nivel ni mejoras.
- **Victoria.** No hay victoria global; hay hitos (nivel, ★6, Ascensión).
- **Respawn / ingreso a mitad.** Todos aparecen en **La Guarida (el lobby)**: ver la sección *La Guarida: lobby y hub social*. Tras un arresto o una caída se reaparece en la Guarida más cercana del distrito donde se estaba. Quien entra en medio de una persecución ajena no se ve afectado: cada policía persigue a **un** jugador identificado.
- **Salir buscado.** Salir con estrellas cuenta como arresto (pierdes la fracción de Botín); salir sin estrellas deposita el Botín automáticamente. Evita usar "salir" como escape.
- **Solo y con poca gente.** Las persecuciones son **por jugador** (o **por banda**, si juegas con una: ver Banda): los policías de tu persecución son tuyos y no dependen de que haya más gente. Los demás jugadores ven los murales, el ruido y las sirenas, pero el juego es completo en solitario. Con más gente aumenta el caos visual y las bocinas atraen a todos los policías cercanos (a veces te meten en problemas ajenos: divertido, no obligatorio).

### Sistema de estrellas y calor (la parte "GTA")

**Calor (Heat)** es un número oculto que sube cuando un policía **ve** la travesura o cuando haces algo ante policías. Las estrellas son sus umbrales:

| Estrellas | Calor mínimo | Policías que aparecen | Nivel en que se desbloquea el techo |
| --- | --- | --- | --- |
| ★1 | 20 | Patrullero Patata (2) | 1 |
| ★2 | 60 | Más Patatas (3), solo Patatas | 1 |
| ★3 | 120 | + Capibara Motorizada y Tiburón Zapatilla SWAT | 6 |
| ★4 | 200 | + Cafetera K-9 | 14 |
| ★5 | 320 | + Helicóptero Banana | 26 |
| ★6 | 480 | + Comisario Cerebrote (jefe) | 40 |

- **Techo de estrellas por nivel.** El calor por encima del techo se guarda pero no sube la estrella. Un jugador de nivel 3 no puede llegar a ★5 por accidente; subir de nivel "te hace más buscado". El techo que se acerca también anuncia el contenido nuevo.
- **Fuentes de calor** (solo si hubo testigo): travesura pequeña +8, mediana +20, grande +45 (valores exactos por minijuego en la tabla de travesuras); derribar un policía +20; estar bajo persecución +1 cada 5 s (la persecución larga escala sola).
- **Detección.** La patrulla **solo detecta a quien ya está buscado (≥ ★1) o está en plena travesura**: sin estrellas se puede pasar delante de un policía sin que se inmute. Una travesura hecha a la vista (o al oído) de un policía sí suma calor y la primera estrella; no hay otra forma de que un policía sin estrellas te persiga. Cada policía tiene cono de visión y oído. Entrar en el cono llena una barra de detección (0,5 s de cerca, 1,6 s de lejos); mientras se llena aparece "?" sobre el policía y al llenarse "!" y te persigue. El **ruido** de la travesura alerta a policías dentro de su radio hacia el punto (no te ven aún). Mejora **Sigilo** reduce el rango de visión y el ruido.
- **Perder las estrellas.** Pierdes la vista durante 10 s → estado "Buscando" (estrellas parpadeando) → el calor baja 5/s. Esconderse en contenedores/arbustos (sin policías a menos de 8 studs) baja una estrella cada 3 s. El **Lavadero Pay'n'Spray** quita todas las estrellas al instante por dinero (sumidero).
- **Premio de riesgo.** Cada travesura paga ×(1 + 0,4 × estrellas actuales): ★6 paga ×3,4. Este factor es de **situación** y se aplica sobre el resultado final de los bonos permanentes (regla de apilamiento en Estado y economía).
- **Agarre.** Un policía agarra si se mantiene a menos de 3,5 studs durante 0,7 s. Si tu velocidad supera la del policía, la distancia crece y no hay agarre: la velocidad es defensa real.

### Policías brainrot (originales, sin personajes con derechos de terceros)

| Policía | Desde | Velocidad | Visión | Habilidad | Cómo vencerlo / derribarlo |
| --- | --- | --- | --- | --- | --- |
| **Patrullero Patata** (papa con gorra) | ★1 | 14 | 40 studs, 100° | Corre en línea recta, grita "¡Alto, tubérculo!" | Más lento que el nivel 1: tutorial del escape. Embestida poder ≥ 12 |
| **Capibara Motorizada** | ★3 | 22 (en calles) | 55 studs | Moto: se frena en cruces con semáforo trucado | Pasar por callejones o escaleras. Poder ≥ 18 |
| **Tiburón Zapatilla SWAT** | ★3 | 30 | 60 studs | Salto-embestida cada 6 s con aviso de 0,6 s | Esquivar el aviso; Banana. Poder ≥ 30 |
| **Cafetera K-9** (perro-cafetera) | ★4 | 38 | 65 studs + olfato 25 | Vapor: ralentiza 30 % por 3 s, rastrea tu camino | Humo la despista. Poder ≥ 40 |
| **Helicóptero Banana** | ★5 | 46 (aire) | 80 studs, foco | Marca tu posición con foco; lanza red (ralentiza 60 % 2 s) | No se derriba: bajo techos/túneles o Bomba de confeti |
| **Comisario Cerebrote** (jefe) | ★6 | 52 | 90 studs | Grito sónico (aturde 1 s, aviso 1 s) | Combo de trampas (3 impactos de herramientas); soltar **Medalla** (recompensa grande) |

- **Alerta progresiva.** Los valores de la tabla son los de un policía a pleno rendimiento. Lo que ve y corre cada policía se multiplica por las **estrellas actuales** del jugador (sin estrellas, p. ej. en plena travesura, vale ★1): visión ×0,45 / 0,6 / 0,7 / 0,8 / 0,9 / 1,0 para ★1 a ★6, velocidad ×0,85 / 0,92 / 0,96 / 1 / 1 / 1 y barra de detección ×1,4 / 1,25 / 1,1 / 1 / 0,9 / 0,8 de tiempo. Así el Patata de ★1 ve a ≈ 18 studs y corre a ≈ 12 (más lento que el nivel 1), el de ★2 a ≈ 24 studs, y el Comisario de ★6 ve a 90. En el Barrio Papa (techo ★2) solo hay Patatas, ambientales y de persecución; el resto debuta con la estrella que lo trae.
### Patrullas de la ciudad: guardias, caminantes y cazadores

Hay tres clases de policía en la calle, además de los perseguidores de la plantilla de estrellas:

- **Guardias (puestos fijos).** Cada travesura de un distrito tiene su guardia, **salvo en el Barrio Papa, donde solo dos travesuras están custodiadas** (un graffiti y un timbrazo; el resto del barrio se aprende sin presión). Cada puesto tiene dos puntos de ruta cerca de la travesura. La guardia va a un punto, **espera**, **mira de derecha a izquierda** (100° en 3 s) y pasa al siguiente. Aparece cuando un jugador está a 260 studs del puesto y se retira cuando se aleja. Si ve al jugador haciendo una travesura (o buscado) pasa a **persecución**. Al perderlo **vuelve a su último punto de guardia** y, si no llega en **5 s**, se **teletransporta** allí. El ruido de la travesura también la alerta hacia el punto. Su tipo sube con el distrito: Patata (Barrio), Patata/Capibara (Colegio), Capibara/Tiburón (Playa), Tiburón/Capibara (Centro), Tiburón/Cafetera (Queso), Cafetera/Tiburón (Puerto).
- **Caminantes (patrulla que aparece).** Un policía aparece en un punto de patrulla fuera de la vista, **camina hasta otro punto lejano** (90 a 320 studs) y **desaparece** al llegar si nadie lo mira de cerca. Aparecen a goteo (uno cada 5–12 s por jugador, hasta 3 cerca). Al perseguir y perder al jugador se convierten también en caminantes y se van.
- **Cazadores (prioridad al más buscado).** Helicóptero Banana y Comisario Cerebrote no persiguen al jugador más cercano sino al que tiene **más estrellas** (a igualdad, al más cercano), dentro de 1 500 studs. Si en una partida con varios jugadores uno sube de estrellas, los cazadores que perseguían a otro cambian de objetivo. Cualquier policía de patrulla que vea a varios jugadores a la vez se fija también en el más buscado.

- **Cantidad.** Máximo 14 policías activos por persecución; el desglose por estrella está en parámetros (`Cops.CountByStar`).
- **Dificultad de ciudad.** Cada Ascensión aumenta velocidad y visión de los policías un 4 % (tope 40 %): la ciudad "se pone al día" con tu poder.
- **Derribar policías.** Dos formas: **Empujón** (siempre, solo contra Patata) y **Embestida** (Dash con cooldown de 5 s). La Embestida derriba si el **Poder de Embestida** = `Velocidad actual × (1 + 0,08 × nivel de Fortachón)` es ≥ la resistencia del policía. El policía queda en ragdoll 4 s y suelta una "propina" (pequeña recompensa de XP y Botín). Eso vuelve útil la velocidad **y** la mejora de fuerza.

## Onboarding

**Los primeros 60–90 segundos.** El jugador completa el loop entero (travesura → estrella → escape → depósito) en ~90 s con un concepto por vez. *(Hipótesis: el primer minuto da la travesura y la primera estrella; el depósito cierra el loop.)*

| Seg. | Qué ve y hace | Paso del funnel |
| --- | --- | --- |
| 0–10 | Spawn en La Guarida (lobby). Texto de una línea: "Entra al portal amarillo (Barrio Papa)". El portal teletransporta a la Guarida del Barrio | `joined` |
| 10–15 | Llega a la Guarida del Barrio Papa. Flecha al muro de graffiti a 25 studs. Texto de una línea: "Pinta el muro". Controles según plataforma | — |
| 5–20 | Mini-tutorial del graffiti (puntos a seguir con el dedo o el mouse). Termina: +$15 Botín, +25 XP, barra de XP sube | `first_mischief` |
| 20–40 | Un Patrullero Patata (guionado) lo ve → "!" y sirena → ★1. El texto dice "¡Corre! Eres más rápido que él" (14 < 16) | `first_star` |
| 40–70 | Se esconde en un arbusto (resaltado) o corre y pierde al policía; las estrellas parpadean y desaparecen | `first_escape` |
| 70–90 | Flecha a la Guarida; mantiene 1,5 s: Botín → Dinero. "¡Compra tus primeras zapatillas! ($100)" con la tienda a un toque | `first_deposit` |
| ≤ 3 min | Primera compra (Zapatillas 1) y primer nivel (nivel 2 en ~20 s) | `first_upgrade`, `first_level_up` |

- Quien vuelve no repite el tutorial (`tutorial_done` guardado). Si ya está en nivel ≥ 2, nunca se muestra.
- Si el jugador ignora el policía guionado, el tutorial espera a que se acerque (no se castiga).
- Cada paso lo observa el servidor (travesura completada, estrellas ≥ 1, estrellas a 0 sin arresto, depósito, compra, subida de nivel).

## La Guarida: lobby y hub social

**La Guarida es el lobby del juego y su zona segura.** Todos aparecen aquí al entrar (también tras una Ascensión) y es el lugar donde los jugadores coordinan, se comparan y salen de viaje. Ningún policía la ve ni entra, y cuenta como Guarida para todo: depósito de Botín, tienda, Ascensión, alijo y 2 Salas de Entrenamiento. Se puede comprar y depositar desde cualquier punto del lobby.

| Pieza | Qué es |
| --- | --- |
| **Plaza central** | Los 8 puntos de aparición, un obelisco con el cartel "LA GUARIDA" y el punto de depósito |
| **6 portales** | Uno por distrito, en un anillo alrededor de la plaza. Teletransportan a la Guarida del distrito si se tiene el nivel (Barrio 1, Colegio 6, Playa 14, Centro 20, Queso 26, Puerto 40). Se puede viajar también desde el menú **La Guarida** (tecla H). Solo desde una zona segura y sin estrellas |
| **16 parcelas reclamables** | Cada jugador reclama **una** en el pedestal (E) y la conserva mientras esté en el servidor. Su cartel muestra el nombre, el nivel, las Ascensiones, los logros y la banda de su dueño, y sobre el pedestal crece una **torre** que sube con el nivel y toma el color del último distrito desbloqueado. Quien se acerca a una parcela ajena abre su perfil y se compara con ella. Se puede soltar la parcela o ir a ella desde el menú |
| **Logros** | 19 logros (travesuras, escapes, derribos, banda, niveles, Ascensiones…). No se guardan aparte: se calculan con contadores que ya se guardan, así que no se pierden con la Ascensión. Avisan al lograrse y se ven en el menú y en la parcela |
| **Jugadores** | Lista del servidor ordenada por progreso (Ascensiones y nivel), con atajo para invitar a la banda |

**Viajes.** Hay un solo método de viaje (`Transit.to`) que sirve para los portales, el menú y los traslados del juego. Funde a negro, pide al cliente que cargue el destino y mueve al personaje. Si un destino declara otro `placeId`, el mismo método usa `TeleportService` (hoy ningún destino lo hace). Un viaje exige el nivel del destino y falla con estrellas, arresto, travesura en curso o fuera de una zona segura.

## Progresión

### Qué progresión elegí y por qué (la que conviene)

| Opción | Pros | Contras | Decisión |
| --- | --- | --- | --- |
| Solo niveles (XP) | Simple | Una sola palanca; sin decisiones | Descartada |
| Niveles + mejoras con dinero | Hay decisiones (qué comprar) | Termina y no hay motivo para volver | Base |
| **Niveles + mejoras + Ascensión (prestigio)** | Reinicio con ventaja; tiempo de juego largo; lo que pediste: "vuelvo desde 0 pero subo más rápido" | Necesita dosificar las recompensas para no inflar | **Elegida** |
| Pase de temporada | Retención | Requiere liveops y contenido periódico | Posterior |

La progresión tiene **cuatro capas que se encadenan**:

1. **Nivel (1–50, soft-gate).** Se obtiene con XP de travesuras y escapes. Cada nivel da **+0,4 de velocidad** y desbloquea decisiones, no solo números: techo de estrellas, distritos, herramientas, minijuegos.
2. **Mejoras (5 líneas × 10 niveles, con Dinero).** **Zapatillas** (+1,5 velocidad/nivel), **Sigilo** (−4 % visión y ruido/nivel), **Bolsillos** (más capacidad de Botín y −3 % de pérdida al arresto/nivel), **Manos Rápidas** (−4 % duración de minijuegos/nivel, o sea menos exposición), **Fortachón** (+8 % Poder de Embestida/nivel). Competir por el mismo Dinero crea la decisión.
3. **Herramientas (5, se desbloquean por nivel y se compran con Dinero).** Tarta (L4), Banana (L9), Bomba de confeti/humo (L16), Patineta turbo (L22), Señuelo (L30).
4. **Ascensión (prestigio, 10 niveles).** Al llegar al **nivel 50** (y pagar una cuota) reinicias nivel, Dinero y mejoras, y ganas un **multiplicador permanente** de XP y Dinero, **Cerebros** (moneda permanente para un árbol de perks) y un distintivo. Subes más rápido cada vez.

### Velocidad (la mecánica que pediste)

`Velocidad = 16 + 0,4 × (nivel − 1) + 1,5 × nivel de Zapatillas + perks de Ascensión` (tope 60 studs/s; el servidor es dueño del valor).

| Momento | Velocidad aproximada | Contra qué corres |
| --- | --- | --- |
| Nivel 1 | 16 | Patata 14: la ganas por poco (fácil) |
| Nivel 14 (Zapatillas 3) | ≈ 26 | ★3 Tiburón 30: no lo superas en recto, hay que usar obstáculos |
| Nivel 26 (Zapatillas 6) | ≈ 35 | ★4 Cafetera 38 casi igual; ★5 Helicóptero 46 no se supera: hay que esconderse/usar herramientas |
| Nivel 40 | ≈ 44 | ★6 Comisario 52 sigue siendo más rápido: hay que tácticas |
| Nivel 50 + Zapatillas 10 + perks | ≈ 55 | Casi igualas al Comisario; con **Patineta turbo** (×1,35) lo superas |

**Efectos de la velocidad en todo el diseño:** menos agarres (sin alcance), más travesuras por minuto (llegas antes a más puntos), Embestida más fuerte y tiempos de huida más cortos. Es lo que hace que "más rápido = menos te agarran = más travesuras".

### Qué desbloquea cada nivel

| Nivel | Se desbloquea (decisión nueva) |
| --- | --- |
| 1 | Graffiti, Timbrazo, Empujón, techo ★2, Barrio Papa |
| 4 | Herramienta **Tarta** |
| 6 | **Colegio**, Hidrante, Carrito, Mural Gigante (banda), techo ★3 |
| 8 | **Sala de Entrenamiento** (AFK activo) y sus mejoras |
| 9 | Herramienta **Banana** |
| 14 | **Playa**, Castillo de arena, Sombrillas voladoras, techo ★4 |
| 16 | **Bomba de confeti** |
| 20 | **Centro Neón**, Bocinas, Semáforos locos, Sinfonía de bocinas (banda) |
| 22 | **Patineta turbo** |
| 26 | **Distrito Queso**, Cajero glitcheado, Estatua con bigote, Caja Fuerte (banda), techo ★5 |
| 30 | **Señuelo** |
| 40 | **Puerto Podrido**, Contenedor misterioso, techo ★6 (Comisario) |
| 50 | **Ascensión** |

### Curva de XP

`XP para pasar del nivel n al n+1 = 30 × n^1,4` (redondeado a 5) y ritmo medio de ganancia `XP/min = 100 + 14 × n` (con multiplicador ×1). Resultado: primera Ascensión disponible a las **≈ 4,5 h de juego**.

## Proyección: tiempo hasta cada hito

*Estimaciones de diseño (ritmo medio de juego, multiplicador ×1). Se calibran con datos reales.*

### Primera carrera (sin Ascensión)

| Nivel / hito | Minuto de juego acumulado | Dinero ganado acumulado | Ingreso aprox. por minuto en ese momento | Qué pasa |
| --- | --- | --- | --- | --- |
| 2 | 0,3 | 21 | 90 | Primera subida: gancho |
| 4 | 2 | 176 | 110 | Tarta disponible |
| 6 | 5 | 525 | 130 | **Colegio** y ★3 |
| 10 | 15 | 1 958 | 170 | Fin de la primera sesión típica |
| 14 | 29 | 4 566 | 210 | **Playa** y ★4 |
| 20 | 56 | 11 055 | 270 | Primera hora; **Centro Neón** |
| 26 | 90 | 21 078 | 330 | **Distrito Queso** y ★5 |
| 30 | 116 | 29 917 | 370 | Señuelo |
| 40 | 189 | 60 352 | 470 | **Puerto** y **★6** |
| 50 | 273 (4,5 h) | 103 803 | 570 | **Ascensión disponible** |

### Compras tipo (ruta de gasto razonable)

Costo de una línea de mejora: `base × 1,45^(n−1)`; bases: Zapatillas 100, Sigilo 150, Bolsillos 120, Manos Rápidas 200, Fortachón 250.

| Compra | Costo | Acumulado | Minuto aprox. |
| --- | --- | --- | --- |
| Zapatillas 1 | 100 | 100 | 1 |
| Tarta (L4) | 300 | 400 | 4 |
| Bolsillos 1 + Sigilo 1 + Zapatillas 2 | 415 | 815 | 7 |
| Banana (L9) | 800 | 1 615 | 13 |
| Manos 1 + Zapatillas 3 + Fortachón 1 | 660 | 2 275 | 17 |
| Bomba de confeti (L16) | 2 000 | 4 275 | 27 |
| Zapatillas 4–6 + Sigilo 2–4 | 2 375 | 6 650 | 38 |
| Patineta (L22) | 4 000 | 10 650 | 55 |
| Zapatillas 7–10 + Manos 2–5 + Bolsillos 2–5 | 10 580 | 21 230 | 91 |
| Señuelo (L30) | 8 000 | 29 230 | 114 |
| Resto de Fortachón y Sigilo | 16 578 | 45 808 | 156 |
| **Cuota de Ascensión (nº 1)** | 20 000 | 65 808 | 200 |

Con ~104 000 ganados al nivel 50, la ruta tipo (≈ 66 000 con la cuota) deja margen para Pay'n'Spray, cosmética y las mejoras que faltan (el árbol completo de mejoras y herramientas cuesta ≈ 88 000): el jugador **no compra todo** en la primera carrera y debe elegir. **Control de muros:** los intervalos entre compras van de 1 a ~25 min y el único salto grande es la cuota de Ascensión al final; la primera compra llega al minuto 1.

### Ascensiones: cuánto acelera cada una

**Multiplicador de Ascensión** (sobre XP **y** Dinero, aditivo): +50 % por Ascensión hasta la 6ª, +25 % de la 7ª a la 10ª. Cuota: `20 000 × 1,15^A`.

| Ascensión nº | Multiplicador tras ascender | Duración de la carrera que la precede | Tiempo de juego acumulado al ascender | Día (25 min/día) | Día (120 min/día) |
| --- | --- | --- | --- | --- | --- |
| 1 (primera) | ×1,5 | 273 min (la primera) | 4,5 h | 11 | 2,3 |
| 2 | ×2,0 | 182 min | 7,6 h | 18 | 3,8 |
| 3 | ×2,5 | 136 min | 9,9 h | 24 | 4,9 |
| 5 | ×3,5 | 91 min | 13,2 h | 32 | 6,6 |
| 10 | ×5,0 | 57 min | 18,7 h | 45 | 9,3 |

- **El jugador percibe**: "la primera vez tardé 4,5 h, la segunda 3 h, la décima menos de 1 h". Cada Ascensión es visiblemente más corta.
- **Perks de Cerebros (permanentes).** Ganas **2 Cerebros** por Ascensión (+1 si llegaste a ★6 en esa carrera). Cuatro perks de 5 niveles (costo 1-2-3-4-5): **Pies de Rayo** (+1 velocidad/nivel), **Sigilo Innato** (−3 % detección/nivel), **Capital Inicial** (+$300 × nivel inicial/nivel), **Sangre Fría** (+8 % de decaimiento de calor/nivel). El árbol completo cuesta 60 Cerebros; 10 Ascensiones dan hasta 30: **hay que elegir**.
- **Después de la 10ª.** Estrellas doradas cosméticas infinitas y eventos (posterior, liveops).

### Retención: proyección de persistencia

**Hipótesis** (se miden, ver KPIs): sesión típica 20–30 min; el D1 se apoya en "quedé a un nivel de la zona nueva"; el D7 en llegar a ★5/★6 y ver la Ascensión cerca.

| Qué trae de vuelta | Cuándo | Diseño |
| --- | --- | --- |
| Meta visible al salir | Cada sesión | La pantalla de salida muestra "te faltan N de XP para X". Sin castigo por faltar |
| **Misiones diarias** (3) | Todos los días | "Pinta 3 muros", "Escapa de ★3", "Derriba 5 policías" o, en banda, "Hagan 2 travesuras de banda". Recompensa = 8 min de ingreso actual. Reinician a las 00:00 UTC. La **racha** sube la recompensa hasta +50 % y, si faltas, **se pausa** (no se pierde) |
| **Alijo de la Guarida** (ingreso pasivo con tope) | Al volver | Acumula 8 % del ingreso/min hasta 90 min; el servidor lo calcula con la hora del servidor. Se reclama en la Guarida |
| **Sala de Entrenamiento** (AFK activo) | Desde el nivel 8, cada día | Quedarse en la Sala paga despacio, con check-in de un clic cada 6–15 min y tope diario de 40 min. Es el motivo para quedarse conectado y volver a completar el tope |
| **Cartel "Se Busca"** (semanal) | Cada semana | Meta de dificultad (ej. "Alcanza ★5 tres veces") con cosmético |
| **Álbum de graffitis** | Siempre | 30 diseños por ID; cada muro pintado desbloquea uno |
| **Distritos y techo de estrellas** | Nivel 6/14/26/40 | El siguiente desbloqueo siempre está a ≤ 1 sesión de distancia en la primera hora |
| **Ascensión** | ≈ 4,5 h | Preview del multiplicador desde el nivel 1 |

### Línea de tiempo esperada (jugador casual 25 min/día)

| Día | Qué debería haber hecho |
| --- | --- |
| 1 | Niveles 1–12, primeras mejoras, Colegio |
| 2 | Playa, ★4 (L14) |
| 4 | Distrito Queso, ★5 (L26) |
| 8 | ★6 (L40), Puerto |
| 11 | Primera Ascensión |

Jugador intenso (120 min/día): L26 el día 1, L40 el día 2, primera Ascensión el día 3.

## Sala de Entrenamiento (AFK activo)

*Mecanismo de retención: el jugador se queda entrenando en un lugar seguro y gana despacio. El diseño no intenta engañar la detección de inactividad de Roblox: pide input real y hace inofensivo lo que no se puede evitar (autoclick, saltar cada minuto).*

**La zona es un volumen.** Cada Guarida tiene una **Sala de Entrenamiento** (cintas de correr brainrot). La sala es un volumen invisible etiquetado (`AfkZone`, ~12×12×8 studs, hasta 6 jugadores). El servidor comprueba cada `Afk.TickSeconds` que el personaje esté vivo, **dentro del volumen** y con **0 estrellas**; si no, el entrenamiento se pausa. Salir no tiene castigo. Los policías no entran (zona segura) y no se puede entrar buscado.

**Qué gana.** XP y Dinero (directo a Dinero, sin Botín) = el ritmo medio del nivel actual × `Afk.RatePercent` (15 % al empezar, hasta 35 % con mejoras). Nunca da estrellas, Cerebros ni herramientas. Se desbloquea en el **nivel 8** (≈ 9 min), después del onboarding.

**Check-in (un clic con reto).** Cada 6–15 min (según Batería, con ±15 % de variación al azar) aparece un reto: "Toca al **Patata**" entre 3 íconos brainrot, en posiciones aleatorias de la pantalla. El reto lo emite el servidor con un código único y la respuesta se valida en el servidor:

| Situación | Resultado |
| --- | --- |
| Respuesta correcta en 0,35–60 s | Sigue entrenando y recibe un bono de 1 min de ganancia AFK |
| Sin respuesta en 60 s | El entrenamiento **se pausa** (no se pierde lo ganado); se reanuda al tocar |
| Respuesta incorrecta | Nuevo reto; 3 errores seguidos = 5 min de pausa |
| Respuesta en < 0,35 s o con tiempos casi idénticos en 5 retos seguidos | Se anula el bono, se pide un reto más difícil y se marca para analíticas (`afk_suspect`); no hay castigo automático (**Suposición**) |

El intervalo máximo (17 min con jitter) queda por debajo de los ~20 min de inactividad que reportan las fuentes; el toque es input real del jugador. Si Roblox lo desconecta igual, el progreso ya está guardado porque se guarda cada tick.

**Mejoras de la Sala** (comparten el mismo Dinero que las demás, así que compiten con ellas):

| Mejora | Efecto | Niveles | Costo base × factor |
| --- | --- | --- | --- |
| **Cinta** | +2 % de ganancia AFK por nivel (15 % → 35 %) | 10 | 300 × 1,45 |
| **Batería** | +108 s entre check-ins por nivel (6 → 15 min) | 5 | 400 × 1,6 |
| **Gimnasio** | +8 min de tope diario de entrenamiento por nivel (40 → 80 min) | 5 | 600 × 1,6 |
| **Skin de cinta** | Cosmético | — | 500–5 000 |

**Límites (anti-abuso por diseño).**
- **Tope diario** de 40 min de entrenamiento pagado (hasta 80 con Gimnasio). Pasado el tope, se puede quedarse, pero no paga.
- El bono total (Ascensión + pase ×2 Dinero + eventos) se aplica igual que al juego activo, con el mismo tope ×8.
- Autoclick o saltar cada minuto **no rinden más**: no cambian lo que se paga ni el tope. Lo único que consigue un bot es lo mismo que un jugador atento, y el reto aleatorio impide el clic ciego.
- Las mejoras de la Sala se reinician con la Ascensión, igual que las demás.

**Efecto en la proyección (orientativo).**

| Jugador | Sin AFK | Con AFK (Cinta 0 → 10) |
| --- | --- | --- |
| Casual (25 min activos/día) | 1ª Ascensión al día 11 | día ≈ 9 → 7 (suma 6–14 min equivalentes por día) |
| Intenso (120 min/día) | día 2,3 | día ≈ 2,2 → 2,0 |

Para el casual el AFK es una ayuda importante (+25–55 %); para el intenso casi no cambia. Es retención: se queda más tiempo conectado y vuelve para completar la meta del día.

## Banda (co-op hasta 8 jugadores)

*Los jugadores que se juntan forman una **banda**. En banda es más fácil conseguir Botín y XP, y hay travesuras que solo se pueden hacer entre varios; a cambio, el calor se contagia y el ruido atrae a más policías.*

**Formar la banda.**
- Botón **Banda** en el HUD o el prompt "Reclutar" en cualquier Guarida: invita a amigos o a jugadores cercanos del servidor. El jefe elige banda **abierta** (cualquiera se une) o **cerrada** (solo invitados). Un amigo que entra por "unirse" de Roblox cae en la banda de su amigo si hay cupo.
- Hasta **8 miembros**; el servidor de 16 admite dos bandas completas. Nombre y color de banda; etiqueta sobre el jugador. Si el jefe se va, el cargo pasa al miembro más antiguo.
- Disponible desde el nivel 1. **La banda no se guarda entre sesiones**: se arma en cada partida.

**Qué se gana en banda (más fácil conseguir botín).**

| Beneficio | Regla |
| --- | --- |
| **Bono de banda** | +12 % de Botín y XP por cada **otro** miembro activo y cercano (≤ 80 studs y con alguna acción en los últimos 30 s). Con 8 jugadores: +84 %. Entra en la **suma** del bono total (tope ×8). No aplica en la Sala AFK |
| **Travesuras de banda** | Tres travesuras que necesitan 2 a 8 jugadores a la vez y pagan **a cada miembro** `base × (1 + 0,25 × (miembros − 1))` (ver tabla) |
| **Recompensa compartida** | Los derribos del Comisario y la Medalla reparten la recompensa a todos los miembros a ≤ 100 studs |
| **Rescate** | Un arrestado queda 5 s en la Camioneta; si un compañero la toca antes, se libera y solo pierde la mitad de la pérdida normal (20 %) |
| **Perseguidores compartidos** | Los policías persiguen a la banda como grupo: tope de 30 por banda en vez de 14 por jugador (cuida el rendimiento) |

**Qué cuesta (para que no sea trivial).**
- **Contagio de calor:** el 50 % del calor que gana un miembro pasa a los miembros a ≤ 100 studs. Suben las estrellas juntos y el premio de riesgo crece, pero también el peligro.
- **El techo de estrellas se respeta por nivel:** un miembro de nivel bajo recibe calor, pero no pasa de su techo. Los novatos no quedan expuestos a ★5.
- **Sin carry:** cada uno gana según su propio nivel; el XP no se transfiere; ninguna banda abre un distrito antes de que el jugador alcance su nivel.
- **Sin AFK de relleno:** el bono exige actividad reciente y cercanía.

**Travesuras de banda** (valores por miembro con 1 compañero; escalan con la regla de arriba):

| Travesura | Nivel | Jugadores | Qué hacen | Dinero base | XP base | Calor | Ruido | Duración |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Mural Gigante** | 6 | 2–8 | Cada uno traza su sección de una pared enorme al mismo tiempo | 40 | 60 | 20 | 20 | 12 s |
| **Sinfonía de bocinas** | 20 | 3–8 | Cada uno toca un auto y todos deben seguir el mismo ritmo | 140 | 190 | 40 | 80 | 10 s |
| **Caja Fuerte del Queso** | 26 | 4–8 | Todos mantienen presionado a la vez y giran la llave en orden | 320 | 420 | 55 | 40 | 12 s |

El Mural Gigante desbloquea diseños de graffiti exclusivos de banda en el Álbum.

**Proyección con banda** (primera carrera, solo el bono de banda, a ritmo medio; se suma con los demás bonos):

| Tamaño de la banda | Bono | Tiempo hasta la 1ª Ascensión |
| --- | --- | --- |
| Solo | +0 % | 273 min (4,5 h) |
| 2 | +12 % | ≈ 244 min |
| 4 | +36 % | ≈ 201 min |
| 8 | +84 % | ≈ 148 min (2,5 h) |

Con Ascensiones altas el efecto relativo baja, porque el bono de banda se suma y no se multiplica (ej.: en la Ascensión 3, de ×2,5 a ×3,3 con 8 jugadores).

**Retención social.** Misiones diarias en banda, travesuras que solo se hacen entre varios y rescates dan motivos para invitar amigos. Esto es una hipótesis (se mide con `band_*` en analíticas).

## Minijuegos de travesuras (los que me conviene)

### Cómo elegí

Criterios (1–5; mi evaluación, **Suposición**): facilidad de construir (F), jugable en celular (M), sinergia con velocidad/persecución (S), rejugabilidad (R), seguro para las políticas de Roblox (P).

| Candidato | F | M | S | R | P | Decisión |
| --- | --- | --- | --- | --- | --- | --- |
| **Graffiti** (pintar la pared) | 4 | 5 | 3 | 5 | 5 | **MVP** (introduce el loop) |
| **Timbrazo y a correr** | 5 | 5 | 5 | 4 | 5 | **MVP** (premia velocidad) |
| **Hidrante** (manguerazo) | 3 | 4 | 4 | 4 | 5 | **MVP** (reemplaza "orinar en público") |
| **Birlar del carrito** (timing) | 4 | 5 | 3 | 3 | 5 | **MVP** |
| **Concierto de bocinas** (ritmo) | 3 | 5 | 4 | 4 | 5 | **MVP** |
| **Semáforos locos** (memoria) | 4 | 5 | 5 | 3 | 5 | **MVP** (táctico) |
| **Cajero glitcheado** (mash + código) | 3 | 4 | 3 | 3 | 5 | **MVP** |
| **Estatua con bigote** (escalar) | 2 | 3 | 3 | 3 | 5 | **MVP** (jefe del distrito) |
| **Contenedor misterioso** (Puerto) | 2 | 4 | 3 | 3 | 5 | **MVP** (fase 2) |
| **Castillo de arena** (mantener + toques) | 4 | 5 | 3 | 4 | 5 | **MVP** (Playa) |
| **Sombrillas voladoras** (secuencia) | 3 | 5 | 3 | 3 | 5 | **MVP** (Playa) |
| **Mural Gigante** (co-op, trazar) | 3 | 4 | 4 | 5 | 5 | **MVP** (banda) |
| **Sinfonía de bocinas** (co-op, ritmo) | 3 | 5 | 4 | 5 | 5 | **MVP** (banda) |
| **Caja Fuerte del Queso** (co-op, mantener a la vez) | 2 | 4 | 4 | 4 | 5 | **MVP** (banda, fase 2) |
| Rave callejera (arrastrar gente) | 2 | 3 | 2 | 4 | 5 | Posterior |
| Atraco al Banco de Queso (multi-etapa, co-op) | 1 | 3 | 5 | 5 | 4 | Posterior (v1.1) |
| Orinar en público | — | — | — | — | 1 | **Descartado**: puede infringir las normas de la comunidad; sustituido por el Hidrante |

Mezcla de entradas: trazar, tocar, mantener, timing, ritmo, memoria, mash. No hay dos seguidos con el mismo gesto, y todos funcionan con un dedo en celular.

### Tabla de travesuras (MVP)

Valores a velocidad del nivel y multiplicador ×1, sin factor de riesgo. Cada punto de travesura tiene su cooldown por jugador.

| Travesura | Nivel | Qué haces | Duración | Dinero | XP | Calor | Ruido (studs) | Nota de diseño |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Graffiti** | 1 | Seguir con el dedo/mouse 5–8 puntos sobre una pared | 7 s | 15 | 25 | 8 | 10 | El mural queda visible 120 s para todos y desbloquea un diseño del Álbum |
| **Timbrazo y a correr** | 1 | Tocar el timbre y alejarte 40 studs en < 5 s | 5 s | 20 | 30 | 10 | 15 | Premio ×1,0–×1,8 según velocidad: **la mejor travesura para el que corre** |
| **Hidrante** | 6 | Mantener para abrir y apuntar el chorro a NPC y policías | 8 s | 45 | 60 | 20 | 30 | Charcos ralentizan policías 15 %; empuja a la Patata |
| **Birlar del carrito** | 6 | Barra de timing de 3 golpes | 5 s | 40 | 55 | 15 | 12 | El vendedor NPC te persigue brevemente |
| **Castillo de arena** | 14 | Mantener y pisotear con toques rápidos hasta derrumbarlo | 6 s | 60 | 80 | 18 | 15 | Se reconstruye tras el cooldown; en la arena todos van más lentos, así que elegir dónde hacerlo importa |
| **Sombrillas voladoras** | 14 | Tocar 4 sombrillas en orden para catapultarlas | 7 s | 75 | 100 | 25 | 25 | Las sombrillas caen y distraen a los policías cercanos 3 s |
| **Concierto de bocinas** | 20 | Ritmo sobre 4 autos | 10 s | 90 | 120 | 30 | 60 | Mucho dinero pero ruido enorme: atrae a todos |
| **Semáforos locos** | 20 | Repetir una secuencia de 3–5 señales | 6 s | 70 | 90 | 12 | 5 | **Táctico**: los autos patrulla de esa esquina se atascan 20 s |
| **Cajero glitcheado** | 26 | Tocar rápido + código de 3 dígitos | 6 s | 150 | 200 | 35 | 20 | Suelta Botín en monedas visibles |
| **Estatua con bigote** | 26 | Escalar y poner el bigote | 12 s | 200 | 250 | 40 | 25 | Atrae al Helicóptero |
| **Contenedor misterioso** | 40 | Mantener y resolver un puzzle de 3 pasos | 9 s | 400 | 500 | 60 | 35 | Payout más alto; dispara ★5 de golpe |

### Reglas de las travesuras

- **Servidor autoridad:** inicia, valida proximidad, duración mínima, cooldown y paga; el cliente solo muestra el minijuego.
- **Cooldown por punto y por jugador:** 45 s (tunable); repetir el mismo punto no es rentable. Hay varios puntos por distrito, de modo que el jugador **se mueve**.
- **Manos Rápidas** reduce la duración; **Sigilo** reduce el ruido.
- **Combo de caos (Suposición):** hacer 3 travesuras en 60 s sin ser arrestado da +25 % de XP en la siguiente.
- **Destrozo ambiente** (sin minijuego): atravesar conos, cajones y puestos a gran velocidad da +$1–$3 y llena un medidor de combo. Premia ir rápido.

### Herramientas (derribar y escapar)

| Herramienta | Nivel / costo | Efecto | Cooldown |
| --- | --- | --- | --- |
| Empujón | 1 / gratis | Empuja un policía débil (solo Patata) | 3 s |
| **Tarta** | 4 / $300 | Proyectil: aturde 2 s | 6 s |
| **Banana** | 9 / $800 | Trampa: resbala 3 s a un policía o auto | 8 s |
| **Bomba de confeti** | 16 / $2 000 | Cubre una zona: los policías pierden vista 5 s; el helicóptero pierde el foco | 20 s |
| **Patineta turbo** | 22 / $4 000 | +35 % velocidad durante 8 s | 25 s |
| **Señuelo** | 30 / $8 000 | Muñeco de cartón que los policías persiguen 6 s | 30 s |

## Contenido y alcance

**MVP** (release-candidate):

- 1 place, **6 distritos** (ver Brief de niveles), 11 travesuras individuales + 3 de banda, **bandas co-op de hasta 8**, 6 tipos de policía, 5 herramientas, 5 líneas de mejoras, Ascensión 1–10 con 4 perks, misiones diarias (3), alijo, **Sala de Entrenamiento (AFK) con check-in y 3 mejoras**, álbum de graffitis (30), cosméticos básicos (skins brainrot y auras), tienda y pases.
- **Fases de producción sugeridas:** A (cortometraje vertical: Barrio + Colegio, ★1–3, 4 travesuras + Mural Gigante, banda básica, Patata/Capibara/Tiburón; valida el loop, el funnel y el co-op), B (Playa + Centro + Queso, ★4–5, Sala AFK), C (Puerto, ★6, Ascensión completa, pases, analíticas). Un lanzamiento limitado puede salir con la fase B si C no llega.

**Posterior:** Rave callejera, Atraco al Banco de Queso co-op, testigos civiles que alertan a policías, LiveOps (eventos de temporada, ciudad nocturna), pase de temporada, trading, nivel y cosméticos de banda que se guardan entre sesiones.

**Presupuesto técnico (Suposición):** máx. 16 jugadores, 14 policías por jugador en persecución y **30 por banda** (los miembros comparten perseguidores); los policías de un jugador que no se ve se desactivan (streaming + despawn por distancia). StreamingEnabled obligatorio.

## Brief de niveles

*Las calles deben ser largas y anchas para una velocidad de hasta 60 studs/s: calles principales ≥ 60 studs de ancho, curvas con radio ≥ 20 studs, rectas de ≥ 300 studs en el Centro Neón y en el Paseo Marítimo de la Playa; paredes de ≥ 40 studs de ancho para el Mural Gigante. Spawn → primera travesura ≤ 30 studs en el Barrio. Guarida cada ≤ 250 studs. Escondites (contenedor o arbusto) cada ≤ 60 studs. Un Pay'n'Spray por distrito.*

| # | Distrito | Objetivo | Mecánica que introduce | Dificultad | Tiempo esperado | Niveles de jugador |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **Barrio Papa** (600×600) | Enseñar el loop | Graffiti, Timbrazo, escondites, Patata | 2 | ~5 min | 1–5 |
| 2 | **Colegio Brainrot** (700×700) | Patio, cantina y pasillos: recorridos cortos y callejones | Hidrante del patio, Carrito de la cantina, Mural Gigante (banda), Tiburón | 3 | ~24 min | 6–13 |
| 3 | **Playa Podrida** (1 200×600) | Arena lenta contra paseo marítimo rápido: elegir ruta | Castillo de arena, Sombrillas voladoras, arena (−15 % de velocidad), Cafetera | 4 | ~27 min | 14–19 |
| 4 | **Centro Neón** (1 400×500) | Rectas largas, autos y velocidad | Bocinas, Semáforos, Sinfonía (banda), autos patrulla | 5 | ~34 min | 20–25 |
| 5 | **Distrito Queso** (900×900, vertical) | Azoteas, techos y túneles contra el helicóptero | Cajero, Estatua, Caja Fuerte (banda), Helicóptero | 7 | ~99 min | 26–39 |
| 6 | **Puerto Podrido** (1 000×800) | Contenedores, grúas y jefe | Contenedor misterioso, Comisario Cerebrote | 9 | ~84 min | 40–50 |

Los seis distritos y La Guarida son **niveles de un único place** (cada uno es un nivel de `Levels.json`), pero **están aislados**: a 5 000 studs unos de otros, nunca se ven juntos y se viaja con un teletransporte desde los portales de La Guarida, que exigen el nivel de jugador del distrito. Pasos de dificultad: 2 → 3 → 4 → 5 → 7 → 9, nunca más de 3 entre consecutivos.

**Puntos de reaparición:** La Guarida (lobby) al entrar; la Guarida del distrito tras un arresto o una caída. **Restricciones:** 6 distritos aislados que se visitan por portal (el nivel se exige al viajar: no hay vallas ni calles entre ellos). Un portal de regreso a La Guarida junto a una Guarida de cada distrito. Presupuesto: ≤ 15 000 partes por distrito (Suposición; el builder y el level designer lo ajustan).

## Física y métricas del personaje

- `walkSpeed` base **16**, escalable (ver Velocidad; tope 60), `jumpHeight` **7,2**, `gravity` **196,2**. La intención: sensación de personaje normal que se vuelve **muy veloz** con el nivel; el servidor es dueño de la velocidad.
- Dash/Embestida: ×1,8 durante 0,35 s, cooldown 5 s (valida el servidor).
- Cámara y UI: la cámara se aleja y sube el FOV con la velocidad para no marear (a cargo de UI/builder).
- Por defecto el jugador **corre siempre** (sin stamina) para no complicar el celular.

## Plataformas e interacción

- **PC:** mover con WASD, Shift opcional no requerido; clic/E para travesuras, Q para Dash, 1–5 herramientas.
- **Celular y tableta:** joystick, botones grandes de acción (travesura, dash, herramientas) a la derecha, sin tapar el chat ni la barra superior; los minijuegos usan un dedo (trazo, toque, mantener). Auto-apunte para las herramientas.
- **Consola:** posterior.
- **HUD:** Botín (con tope), Dinero, estrellas con calor, barra de XP, mini-radar de policías (si Sigilo lo permite), cooldowns de herramientas.
- **Accesibilidad:** destellos de sirena opcionales, daltonismo (estrellas con forma y no solo color), subtítulos para los gritos.

## Estado y economía

### Qué se conserva (promesas al jugador)

- Conserva su **nivel y XP**, su **Dinero** depositado, sus **mejoras** (incluidas Cinta, Batería y Gimnasio de la Sala) y **herramientas desbloqueadas**.
- Conserva el **tiempo de entrenamiento AFK usado hoy** (para el tope diario) y lo ganado en la Sala hasta el último tick, aunque lo desconecten.
- Conserva sus **Ascensiones**, su **multiplicador**, sus **Cerebros** y los **perks** comprados, y su distintivo.
- Conserva el **álbum de graffitis**, los **cosméticos** y las **misiones/racha/cartel** en curso.
- Lo comprado con Robux no se pierde (pases y productos con beneficio permanente).
- **No** se conserva: Botín sin depositar (se deposita al salir sin estrellas), estrellas/calor, policías activos, el estado del tutorial a medias, ni la **banda** (se arma en cada sesión; los nombres y colores no se guardan en el MVP).
- Si la **carga falla**, el jugador puede jugar, pero **no puede comprar ni guardar**, y se le avisa; nunca se sobrescribe un perfil que no cargó.
- La Ascensión es una operación del servidor; si falla a mitad, no se pierde nada.

### Monedas

| Moneda | Cómo se obtiene | En qué se gasta | Se conserva | Robux |
| --- | --- | --- | --- | --- |
| **Botín** | Travesuras, derribos, monedas del suelo | Se convierte en Dinero al depositar | No (se deposita o se pierde en parte) | No |
| **Dinero** | Depositar Botín, misiones, alijo | Mejoras, herramientas, Pay'n'Spray, cosmética, cuota de Ascensión | Sí | Sí (paquetes) |
| **Cerebros** | Ascensión | Perks permanentes | Sí | **No** |

No hay premios aleatorios pagados con Dinero comprado, así que la política de aleatoriedad pagada no aplica (**Suposición**; si se agregan cajas, hay que revisarlo).

### Fuentes y sumideros

| Fuente | Cantidad | Frecuencia | Condición | Límite |
| --- | --- | --- | --- | --- |
| Travesura | 15–400 base (ver tabla) | ~2–4 por minuto | Completarla | Cooldown 45 s por punto; capacidad de Botín |
| Premio de riesgo | ×(1 + 0,4 × estrellas) | Cada travesura | Estrellas activas | Solo con estrellas; el Botín se puede perder |
| Derribo de policía | $5–$40 + XP | Por derribo | Derribar | 4 s ragdoll, un derribo por policía y por persecución |
| Destrozo ambiente | $1–$3 | Muy frecuente | Atravesar objetos rápido | Cooldown por objeto |
| Misiones diarias | 8 min de ingreso actual | 3 al día | Completarlas | 1 vez por día |
| Alijo de la Guarida | 8 % del ingreso/min | Mientras no estás | Reclamarlo | Tope 90 min |
| Sala de Entrenamiento (AFK) | 15–35 % del ritmo del nivel | Mientras entrenas | Estar en el volumen, con 0 estrellas y responder los check-ins | 40 min/día (hasta 80); sin Cerebros ni estrellas |
| Medalla del Comisario | Grande | Raro | Derribarlo | Una por jefe (se comparte con la banda cercana) |
| Bono de banda y travesuras de banda | +12 % por compañero activo; pago ×(1 + 0,25 × (n − 1)) en las 3 travesuras de banda | Siempre que se juega en grupo | Estar cerca y activo | Máx. 8 miembros; tope ×8 del bono total |

| Sumidero | Costo | Qué da | ¿Repetible? | Se desbloquea |
| --- | --- | --- | --- | --- |
| Mejoras (5 líneas) | `base × 1,45^(n−1)` | Velocidad, sigilo, capacidad, etc. | Hasta nivel 10 | Desde el inicio |
| Mejoras de la Sala (Cinta, Batería, Gimnasio) | 300×1,45ⁿ / 400×1,6ⁿ / 600×1,6ⁿ (≈ 43 000 en total) | Más ganancia AFK, más tiempo entre check-ins, más tope diario | Hasta nivel 10 / 5 / 5 | Nivel 8 |
| Herramientas | 300–8 000 | Utilidad | No | Por nivel |
| Pay'n'Spray | `120 × ★ × (1 + 0,05 × nivel)` | Quita estrellas ya | **Sí, ilimitado** | Desde el inicio |
| Cosméticos | 500–50 000 | Skins y auras | Sí | Por nivel |
| Cuota de Ascensión | `20 000 × 1,15^A` | Ascender | Sí (hasta 10) | Nivel 50 |

Cada fuente ilimitada tiene un sumidero repetible (Pay'n'Spray, cosméticos, cuota); la economía no termina antes que el juego: la Ascensión reinicia la compra de mejoras.

### Regla de apilamiento de multiplicadores

1. **Bono permanente y de evento = suma**: `1 + 0,5 × Ascensiones (hasta 6; 0,25 para las siguientes) + 1,0 (pase ×2 Dinero) + 0,12 × (miembros activos de la banda − 1) + eventos`, con **tope ×8**.
2. **Premio de riesgo** (estrellas) se aplica como **multiplicador separado** sobre el pago del Botín, no se suma. Peor caso teórico: ×8 × 3,4 = ×27,2, que solo ocurre con 6★, tiempo limitado y botín perdible.
3. La descripción que ve el jugador es "Bono total: +X %", y coincide con el cálculo del servidor.
4. XP usa la misma suma (sin pase de Dinero).

## Parámetros ajustables

El builder los copia a `src/shared/Config.luau` y el juego los lee con `Tuning.get`. Nada ajustable queda solo en el texto.

| Parámetro | Valor inicial | Uso |
| --- | --- | --- |
| `Server.MaxPlayers` | 16 | Jugadores por servidor |
| `World.SandSpeedMult` | 0.85 | Multiplicador de velocidad sobre arena (jugadores y policías terrestres) |
| `Band.MaxMembers` | 8 | Tamaño máximo de una banda |
| `Band.BonusPerMember` | 0.12 | Bono de Botín y XP por cada otro miembro activo y cercano |
| `Band.BonusRange` | 80 | Distancia (studs) para contar a un compañero |
| `Band.ActiveWindowSeconds` | 30 | Un miembro cuenta si hizo una acción en estos segundos |
| `Band.HeatShareFraction` | 0.5 | Fracción del calor que se contagia a los miembros cercanos |
| `Band.HeatShareRange` | 100 | Distancia (studs) del contagio de calor |
| `Band.SharedRewardRange` | 100 | Distancia para repartir derribos y medallas |
| `Band.RescueSeconds` | 5 | Segundos que dura la Camioneta antes del encierro |
| `Band.RescueLossPercent` | 0.2 | Botín perdido si lo rescatan a tiempo |
| `Band.MaxCops` | 30 | Máximo de policías perseguidores por banda |
| `Band.InviteCooldownSeconds` | 10 | Espera entre invitaciones al mismo jugador |
| `Coop.PayPerExtraMember` | 0.25 | Aumento del pago por miembro en travesuras de banda |
| `Coop.MuralGigante.Level` | 6 | Nivel del Mural Gigante |
| `Coop.MuralGigante.MinPlayers` | 2 | Mínimo de jugadores |
| `Coop.MuralGigante.Money` | 40 | Dinero base por miembro |
| `Coop.MuralGigante.Xp` | 60 | XP base por miembro |
| `Coop.MuralGigante.Heat` | 20 | Calor |
| `Coop.MuralGigante.Noise` | 20 | Ruido (studs) |
| `Coop.MuralGigante.Duration` | 12 | Segundos |
| `Coop.Sinfonia.Level` | 20 | Nivel de la Sinfonía de bocinas |
| `Coop.Sinfonia.MinPlayers` | 3 | Mínimo de jugadores |
| `Coop.Sinfonia.Money` | 140 | Dinero base por miembro |
| `Coop.Sinfonia.Xp` | 190 | XP base por miembro |
| `Coop.Sinfonia.Heat` | 40 | Calor |
| `Coop.Sinfonia.Noise` | 80 | Ruido (studs) |
| `Coop.Sinfonia.Duration` | 10 | Segundos |
| `Coop.CajaFuerte.Level` | 26 | Nivel de la Caja Fuerte del Queso |
| `Coop.CajaFuerte.MinPlayers` | 4 | Mínimo de jugadores |
| `Coop.CajaFuerte.Money` | 320 | Dinero base por miembro |
| `Coop.CajaFuerte.Xp` | 420 | XP base por miembro |
| `Coop.CajaFuerte.Heat` | 55 | Calor |
| `Coop.CajaFuerte.Noise` | 40 | Ruido (studs) |
| `Coop.CajaFuerte.Duration` | 12 | Segundos |
| `Player.BaseWalkSpeed` | 16 | Velocidad base |
| `Player.SpeedPerLevel` | 0.4 | Velocidad ganada por nivel |
| `Player.MaxSpeed` | 60 | Tope de velocidad (studs/s) |
| `Player.DashSpeedMult` | 1.8 | Multiplicador del Dash |
| `Player.DashSeconds` | 0.35 | Duración del Dash |
| `Player.DashCooldown` | 5 | Cooldown del Dash/Embestida |
| `Progress.MaxLevel` | 50 | Nivel máximo antes de la Ascensión |
| `Progress.XpBase` | 30 | Base de la curva de XP |
| `Progress.XpExponent` | 1.4 | Exponente de la curva de XP |
| `Progress.ComboBonus` | 0.25 | +XP tras 3 travesuras en 60 s |
| `Heat.StarThresholds` | 20,60,120,200,320,480 | Calor para cada estrella |
| `Heat.StarCapByLevel` | 1:2,6:3,14:4,26:5,40:6 | Techo de estrellas por nivel |
| `Heat.DecayPerSecond` | 5 | Bajada de calor en "Buscando" |
| `Heat.LoseSightSeconds` | 10 | Segundos sin vista para pasar a "Buscando" |
| `Heat.ChasePressurePer5s` | 1 | Calor extra por persecución larga |
| `Heat.CopKnockdown` | 20 | Calor por derribar un policía |
| `Heat.RiskPayoutPerStar` | 0.4 | Premio de riesgo por estrella |
| `Hide.SecondsPerStar` | 3 | Segundos escondido por estrella que baja |
| `Hide.MinCopDistance` | 8 | Distancia mínima de policías al esconderse |
| `Detect.FillSecondsNear` | 0.5 | Detección de cerca |
| `Detect.FillSecondsFar` | 1.6 | Detección de lejos |
| `Guard.ActivateRadius` | 260 | Distancia a la que aparece la guardia de un puesto |
| `Guard.RespawnSeconds` | 10 | Espera para reponer una guardia retirada |
| `Guard.WaitSeconds` | 2 | Pausa al llegar a un punto de guardia |
| `Guard.ScanDegrees` | 100 | Barrido de la mirada, de derecha a izquierda |
| `Guard.ScanSeconds` | 3 | Duración del barrido |
| `Guard.TurnDegreesPerSecond` | 240 | Rapidez de giro de la guardia |
| `Guard.ArriveRadius` | 3.5 | Distancia a la que cuenta como llegada |
| `Guard.WalkTimeoutSeconds` | 20 | Si no llega al siguiente punto, se teletransporta |
| `Guard.ReturnSeconds` | 5 | Tras perder al jugador, tiempo para volver al punto antes de teletransportarse |
| `Cops.WalkerSpawnMin` / `Cops.WalkerSpawnMax` | 5 / 12 | Segundos entre apariciones de caminantes (por jugador) |
| `Cops.WalkerMinTrip` / `Cops.WalkerMaxTrip` | 90 / 320 | Distancia del trayecto de un caminante |
| `Cops.WalkerMaxSeconds` | 120 | Tiempo máximo de un caminante |
| `Cops.WalkerVanishDistance` | 70 | No desaparece si un jugador está más cerca |
| `Cops.HunterRange` | 1500 | Radio en que un cazador busca al más buscado |
| `Cops.AlertVisionByStar` | 0.45,0.6,0.7,0.8,0.9,1.0 | Multiplicador de visión por estrella |
| `Cops.AlertSpeedByStar` | 0.85,0.92,0.96,1,1,1 | Multiplicador de velocidad por estrella |
| `Cops.AlertFillByStar` | 1.4,1.25,1.1,1,0.9,0.8 | Multiplicador de segundos de detección por estrella |
| `Cops.Patata.Speed` | 14 | Velocidad Patata |
| `Cops.Capibara.Speed` | 22 | Velocidad Capibara |
| `Cops.Tiburon.Speed` | 30 | Velocidad Tiburón |
| `Cops.Cafetera.Speed` | 38 | Velocidad Cafetera |
| `Cops.Helicoptero.Speed` | 46 | Velocidad Helicóptero |
| `Cops.Comisario.Speed` | 52 | Velocidad Comisario |
| `Cops.Patata.VisionRange` | 40 | Visión Patata (studs) |
| `Cops.Capibara.VisionRange` | 55 | Visión Capibara |
| `Cops.Tiburon.VisionRange` | 60 | Visión Tiburón |
| `Cops.Cafetera.VisionRange` | 65 | Visión Cafetera |
| `Cops.Helicoptero.VisionRange` | 80 | Visión Helicóptero |
| `Cops.Comisario.VisionRange` | 90 | Visión Comisario |
| `Cops.Patata.Resistance` | 12 | Poder de Embestida necesario |
| `Cops.Capibara.Resistance` | 18 | Poder necesario |
| `Cops.Tiburon.Resistance` | 30 | Poder necesario |
| `Cops.Cafetera.Resistance` | 40 | Poder necesario |
| `Cops.CountByStar` | 2,3,4,6,8,10 | Policías base por estrella (tope en `Cops.MaxPerPlayer`) |
| `Cops.MaxPerPlayer` | 14 | Máximo de policías activos por jugador |
| `Cops.Difficulty.PerAscension` | 0.04 | Aumento de velocidad y visión por Ascensión |
| `Cops.Difficulty.Cap` | 0.4 | Tope de ese aumento |
| `Cops.Grab.Distance` | 3.5 | Distancia de agarre |
| `Cops.Grab.Time` | 0.7 | Segundos para agarrar |
| `Cops.KnockdownSeconds` | 4 | Tiempo en ragdoll |
| `Arrest.LossPercent` | 0.4 | Botín perdido al arresto |
| `Arrest.LossPercentHighHeat` | 0.6 | Botín perdido con ★5+ |
| `Arrest.LossMin` | 0.1 | Mínimo con mejora de Bolsillos |
| `Arrest.JailSeconds` | 5 | Espera tras ser arrestado |
| `Spray.CostPerStar` | 120 | Costo del Pay'n'Spray por estrella |
| `Spray.LevelFactor` | 0.05 | Crecimiento del costo con el nivel |
| `Carry.BaseCap` | 300 | Capacidad base de Botín |
| `Carry.CapPerLevel` | 40 | Capacidad por nivel |
| `Carry.CapPerPocketLevel` | 150 | Capacidad por nivel de Bolsillos |
| `Deposit.HoldSeconds` | 1.5 | Tiempo de depósito |
| `Mischief.SpotCooldown` | 45 | Segundos entre repetir el mismo punto |
| `Upgrades.MaxLevel` | 10 | Nivel máximo de cada línea |
| `Upgrades.CostFactor` | 1.45 | Crecimiento del costo por nivel |
| `Upgrades.Zapatillas.BaseCost` | 100 | Costo base Zapatillas |
| `Upgrades.Sigilo.BaseCost` | 150 | Costo base Sigilo |
| `Upgrades.Bolsillos.BaseCost` | 120 | Costo base Bolsillos |
| `Upgrades.Manos.BaseCost` | 200 | Costo base Manos Rápidas |
| `Upgrades.Fortachon.BaseCost` | 250 | Costo base Fortachón |
| `Upgrades.Zapatillas.SpeedPerLevel` | 1.5 | Velocidad por nivel de mejora |
| `Upgrades.Sigilo.ReductionPerLevel` | 0.04 | Reducción de visión y ruido |
| `Upgrades.Bolsillos.LossReductionPerLevel` | 0.03 | Reducción de pérdida al arresto |
| `Upgrades.Manos.TimeReductionPerLevel` | 0.04 | Reducción de duración de minijuegos |
| `Upgrades.Fortachon.PowerPerLevel` | 0.08 | Poder de Embestida por nivel |
| `Tools.Tarta.Cost` | 300 | Costo de la Tarta |
| `Tools.Tarta.Cooldown` | 6 | Cooldown Tarta |
| `Tools.Tarta.StunSeconds` | 2 | Aturdimiento |
| `Tools.Banana.Cost` | 800 | Costo de la Banana |
| `Tools.Banana.Cooldown` | 8 | Cooldown Banana |
| `Tools.Banana.SlipSeconds` | 3 | Resbalón |
| `Tools.Humo.Cost` | 2000 | Costo de la Bomba de confeti |
| `Tools.Humo.Cooldown` | 20 | Cooldown |
| `Tools.Humo.BlindSeconds` | 5 | Segundos sin vista |
| `Tools.Patineta.Cost` | 4000 | Costo de la Patineta |
| `Tools.Patineta.Cooldown` | 25 | Cooldown |
| `Tools.Patineta.SpeedMult` | 1.35 | Aumento de velocidad |
| `Tools.Patineta.Seconds` | 8 | Duración |
| `Tools.Senuelo.Cost` | 8000 | Costo del Señuelo |
| `Tools.Senuelo.Cooldown` | 30 | Cooldown |
| `Tools.Senuelo.Seconds` | 6 | Duración |
| `Ascension.MinLevel` | 50 | Nivel mínimo para ascender |
| `Ascension.Max` | 10 | Máximo de Ascensiones |
| `Ascension.FeeBase` | 20000 | Cuota base |
| `Ascension.FeeGrowth` | 1.15 | Crecimiento de la cuota |
| `Ascension.BonusEarly` | 0.5 | Bono por Ascensión (1ª–6ª) |
| `Ascension.BonusLate` | 0.25 | Bono por Ascensión (7ª–10ª) |
| `Ascension.CerebrosBase` | 2 | Cerebros por Ascensión |
| `Ascension.CerebrosSixStar` | 1 | Cerebro extra si llegó a ★6 |
| `Perks.CostByLevel` | 1,2,3,4,5 | Costo de cada nivel de perk |
| `Perks.PiesDeRayo.SpeedPerLevel` | 1 | Velocidad por nivel de perk |
| `Perks.SigiloInnato.ReductionPerLevel` | 0.03 | Reducción de detección |
| `Perks.CapitalInicial.MoneyPerLevel` | 300 | Dinero inicial por nivel de perk |
| `Perks.SangreFria.DecayBonusPerLevel` | 0.08 | Aumento del decaimiento del calor |
| `Economy.BonusCap` | 8 | Tope del bono total aditivo |
| `Daily.QuestCount` | 3 | Misiones diarias |
| `Daily.RewardMinutesOfIncome` | 8 | Recompensa en minutos de ingreso |
| `Daily.StreakMaxBonus` | 0.5 | Bono máximo por racha |
| `Stash.RatePercent` | 0.08 | % del ingreso por minuto del alijo |
| `Stash.CapMinutes` | 90 | Tope del alijo |
| `Afk.UnlockLevel` | 8 | Nivel que desbloquea la Sala de Entrenamiento |
| `Afk.TickSeconds` | 5 | Cada cuántos segundos el servidor verifica la zona y paga |
| `Afk.RatePercent` | 0.15 | Ganancia AFK base (fracción del ritmo del nivel) |
| `Afk.RatePerCintaLevel` | 0.02 | Ganancia AFK por nivel de Cinta |
| `Afk.DailyCapMinutes` | 40 | Tope diario de entrenamiento pagado |
| `Afk.DailyCapPerGymLevel` | 8 | Minutos extra de tope por nivel de Gimnasio |
| `Afk.CheckInBaseSeconds` | 360 | Intervalo base entre check-ins |
| `Afk.CheckInPerBatteryLevel` | 108 | Segundos extra de intervalo por nivel de Batería |
| `Afk.CheckInJitter` | 0.15 | Variación aleatoria del intervalo (±) |
| `Afk.CheckInMaxSeconds` | 1020 | Intervalo máximo con variación (por debajo de ~20 min) |
| `Afk.ChallengeWindowSeconds` | 60 | Tiempo para responder el reto |
| `Afk.ChallengeMinReactionSeconds` | 0.35 | Respuesta más rápida que esto no es humana |
| `Afk.ChallengeWrongLimit` | 3 | Errores seguidos antes de la pausa |
| `Afk.ChallengeLockMinutes` | 5 | Pausa tras los errores |
| `Afk.CheckInBonusMinutes` | 1 | Bono por responder bien (minutos de ganancia AFK) |
| `Afk.SuspectStreak` | 5 | Retos seguidos con tiempos casi idénticos para marcar |
| `Afk.ZoneMaxPlayers` | 6 | Jugadores por sala |
| `Upgrades.Cinta.BaseCost` | 300 | Costo base de la Cinta |
| `Upgrades.Cinta.CostFactor` | 1.45 | Crecimiento de la Cinta |
| `Upgrades.Cinta.MaxLevel` | 10 | Niveles de la Cinta |
| `Upgrades.Bateria.BaseCost` | 400 | Costo base de la Batería |
| `Upgrades.Bateria.CostFactor` | 1.6 | Crecimiento de la Batería |
| `Upgrades.Bateria.MaxLevel` | 5 | Niveles de la Batería |
| `Upgrades.Gimnasio.BaseCost` | 600 | Costo base del Gimnasio |
| `Upgrades.Gimnasio.CostFactor` | 1.6 | Crecimiento del Gimnasio |
| `Upgrades.Gimnasio.MaxLevel` | 5 | Niveles del Gimnasio |
| `Tutorial.ScriptedCopSpeed` | 14 | Velocidad del policía guionado |

### Valores por travesura

Parámetros `Mischief.<Id>.<Campo>`; valores iniciales:

| Id | Level | Money | Xp | Heat | Noise | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| `Graffiti` | 1 | 15 | 25 | 8 | 10 | 7 |
| `Timbrazo` | 1 | 20 | 30 | 10 | 15 | 5 |
| `Hidrante` | 6 | 45 | 60 | 20 | 30 | 8 |
| `Carrito` | 6 | 40 | 55 | 15 | 12 | 5 |
| `Castillo` | 14 | 60 | 80 | 18 | 15 | 6 |
| `Sombrillas` | 14 | 75 | 100 | 25 | 25 | 7 |
| `Bocinas` | 20 | 90 | 120 | 30 | 60 | 10 |
| `Semaforos` | 20 | 70 | 90 | 12 | 5 | 6 |
| `Cajero` | 26 | 150 | 200 | 35 | 20 | 6 |
| `Estatua` | 26 | 200 | 250 | 40 | 25 | 12 |
| `Contenedor` | 40 | 400 | 500 | 60 | 35 | 9 |

## Monetización seleccionada

*Hipótesis comercial; el catálogo con IDs reales, precios vigentes y pruebas los completan los módulos. Todas las ofertas están **pendientes** (sin IDs) y su compra queda desactivada hasta tener IDs.*

**Principios:** el recorrido gratuito es completo; lo pagado prioriza **comodidad y cosmética**, no poder que decida persecuciones. No hay cajas aleatorias.

| Oferta | Módulo | Beneficio | Precio (hipótesis) | Estado |
| --- | --- | --- | --- | --- |
| **Dinero ×2** | game-passes | +1,0 al bono total aditivo (entra en la suma, con tope ×8) | 299–399 R$ | Pendiente |
| **Aura Brainrot VIP** | game-passes | Cosmético, color de nombre y emote | ~199 R$ | Pendiente |
| **Alijo extendido** | game-passes | Tope del alijo 90 → 240 min | ~149 R$ | Pendiente |
| **Teléfono de Guarida** | game-passes | Depositar a distancia cuando no estás buscado (comodidad, no evita riesgo) | ~249 R$ | Pendiente |
| **Paquetes de Dinero** | developer-products | 3 tamaños (equivalen a ≈ 30, 120 y 480 min de ingreso a nivel 20); no suben el nivel | 25 / 75 / 199 R$ | Pendiente |
| **Soborno** | developer-products | Quita las estrellas al instante (alternativa a Pay'n'Spray) | ~25 R$ | Pendiente |
| **Fianza** | developer-products | Evita la espera tras el arresto (no recupera el Botín perdido) | ~15 R$ | Pendiente |

**Hipótesis:** la gente compra comodidad (×2 Dinero, Teléfono) cuando ya ama el loop; los productos pequeños (Soborno, Fianza) aprovechan los momentos de tensión sin dar ventaja competitiva. Los paquetes no saltan la Ascensión (se bloquean al nivel 50 sin cuota).

## KPIs objetivo

| KPI | Definición | Objetivo inicial | Cómo se mide | Decisión si no se cumple |
| --- | --- | --- | --- | --- |
| **Conversión del onboarding** | Nuevos que llegan a `first_deposit` en su primera sesión / nuevos que entraron; abandono en cada paso del funnel | Medir línea base la primera semana (hipótesis: la mayoría lo completa porque el tutorial dura ~90 s) | Funnel de onboarding | Acortar el camino hasta el primer escape; simplificar el paso con más abandono; revisar el policía guionado |
| **Uso de la Sala AFK** | Jugadores nivel ≥ 8 que entran a la Sala al menos una vez por semana / jugadores nivel ≥ 8 activos; % de check-ins respondidos y de `afk_suspect` | Medir línea base; hipótesis: el AFK alarga la sesión y sube el D7 sin vaciar las travesuras | Eventos `afk_enter`, `afk_checkin`, `afk_checkin_fail`, `afk_suspect`, `afk_exit` | Ajustar el % de ganancia y el tope; si baja la actividad de travesuras, reducir la Cinta |
| **Retención D1 y D7** | Nuevos que vuelven 1 y 7 días después; se compara a quien jugó en banda contra quien jugó solo y se mide el % de sesiones en banda | Medir línea base; hipótesis: D1 se apoya en la meta visible, D7 en ★5/★6 y la banda mejora ambos | Creator Analytics y eventos `band_*` | Reforzar meta al salir, misiones diarias, distrito nuevo; si la banda no mejora la retención, simplificar el reclutamiento |
| **Embudo de progresión** | % de jugadores que llegan a los niveles 6, 14, 26, 40 y a la 1ª Ascensión | Hipótesis: la curva sin muros mantiene una caída suave entre hitos | Eventos de progresión | Ajustar la curva de XP donde esté el pico de abandono |
| **Tasa de arrestos** | Arrestos por hora de juego, por banda de nivel | Hipótesis: 4–8/h; menos de 2/h = demasiado fácil, más de 12/h = frustrante | Eventos de arresto | Ajustar velocidad de policías, visión o penalización |
| **Salud de la economía** | Dinero ganado/gastado por sesión; tiempo real hasta Ascensión 1 vs diseño (4,5 h) | Medir; el tiempo real debe estar dentro de ±30 % del diseño | Eventos de economía | Ajustar ingresos, costos y cuota |

**Nombres estables para la medición.** Funnel: `joined`, `first_mischief`, `first_star`, `first_escape`, `first_deposit`, `first_upgrade`, `first_level_up`. Camino de progresión: `Ciudad` (nivel). Monedas: `Dinero`, `Cerebros`. Eventos propios sugeridos: `arrest`, `star_reached`, `cop_knockdown`, `mischief_complete`, `ascension`, `afk_enter`, `afk_checkin`, `afk_checkin_fail`, `afk_suspect`, `afk_exit`, `band_create`, `band_join`, `band_leave`, `band_mischief`, `band_rescue`.

## Assets y servicios

*Dueño: builder.*

- **Assets externos:** ninguno. Los policías, la Camioneta, las trampas y los efectos se arman con Parts y partículas (`src/server/Game/CopModels.luau`); no hay `rbxassetid://` en el código. Texturas, sonidos y animaciones del usuario quedan para el pase de arte.
- **Servicios de Roblox usados:** DataStoreService (solo en `PlayerData`), MarketplaceService (solo en `Shop`), PathfindingService (solo en `Cops`, cuando un policía se atasca), PhysicsService (grupos de colisión en `Movement`), CollectionService (etiquetas de `LevelLoader`).
- **Configuración externa pendiente (Creator Hub):**
  - 4 Game Passes: Dinero ×2 (`money2x`), Aura Brainrot VIP (`aura_vip`), Alijo extendido (`stash_extended`) y Teléfono de Guarida (`phone`).
  - 4 Developer Products: `pack_small`, `pack_medium`, `pack_large` y `soborno`. La Fianza queda para después.
  - Los IDs van en `src/server/Game/Content.luau` y en `Game/init.luau`; mientras valgan 0 la oferta no se puede comprar.
  - Activar *Studio Access to API Services* para probar el guardado real.
  - Publicar la experiencia como `release-candidate` es una acción del usuario.

## Arquitectura

*Dueño: builder.*

**Árbol de archivos** (el proyecto está en la raíz: `default.project.json`, `src/`, `design/`, `GDD.md`):

```text
src/shared/       Config, Tuning, Signal, Style, Theme.json, Levels.json, DataTypes, Net, Catalog
src/server/       Bootstrap.server, Telemetry, LevelLoader, Data/ (PlayerData y migraciones)
  Modules/        Areas Progress Economy Upgrades Ascension Mischief Quests Training Cosmetics
                  Stats Shop Wanted Cops Band Tools Arrest
  Bridges/        Cops_Wanted Wanted_Band Stats_Quests
  Game/           init, Content, CopModels, PlayerStats, Movement, World, Effects, Reactions, Intents
src/client/       Controls.client (la interfaz es del UI designer: src/client/UI)
```

**Orden de inicio.** `Bootstrap` aplica la iluminación del tema, conecta la salida de jugadores, inicia `PlayerData`, construye el mundo con `LevelLoader`, y llama a `Game.start`: `init` de los cores, `connect` de los puentes y `start` de los cores, y después `Movement`, `World`, `Effects`, `Reactions` e `Intents`.

**Reglas de autoridad.** El servidor decide todo: velocidad, calor, estrellas, pagos, resultados de travesuras (por tiempo y cercanía), compras y arrestos. El cliente solo manda intenciones por `Net` y pinta el estado que publica el servidor en atributos.

**Estrategia de datos.** Un solo servicio de datos (`PlayerData`, sección por core, fachada `<Core>Data`), sin guardados por click. Al salir con estrellas se aplica la pérdida de arresto y sin ellas se deposita el Botín, antes de que el perfil se guarde (`Bootstrap` conecta `PlayerRemoving` antes de `PlayerData.start`; el orden de las conexiones debe comprobarse en Studio).

**Presupuesto de rendimiento.** 14 policías por jugador (30 por banda), pensamiento cada 0,15 s, ruta con `PathfindingService` solo si se atascan, `StreamingEnabled`, ~430 piezas de nivel.

**Telemetría que emite cada sistema:** funnel de onboarding (`joined`… `first_level_up`) desde `Reactions`; progresión `Ciudad` al subir de nivel; economía en `Economy`; eventos propios: `mischief_complete`, `star_reached`, `cop_knockdown`, `arrest`, `ascension`, `upgrade_bought`, `district_entered`, `band_mischief`, `band_rescue`, `afk_enter`, `afk_exit`, `afk_checkin`, `afk_suspect`.

### Mapa de módulos

| Módulo | Capa | Responsabilidad | API y eventos | Datos que posee | Excepción | Origen |
| --- | --- | --- | --- | --- | --- | --- |
| `Areas` | core | Quién está dentro de cada zona de `Levels.json` | `init`, `start`, `parts`, `inside`, `containing`, `nearest`; `entered`, `left` | — | — | propio |
| `Progress` | core | Nivel, XP y banderas de hitos | `init`, `start`, `addXp`, `level`, `setFlag`, `hasFlag`, `reset`; `leveledUp`, `loaded`, `flagSet` | `progress` | — | propio |
| `Economy` | core | Dinero, Cerebros y Botín de la sesión | `init`, `start`, `add`, `spend`, `set`, `balance`, `addLoot`, `deposit`, `loseLoot`; `changed`, `lootChanged`, `deposited`, `lootLost` | `economy` | — | propio |
| `Upgrades` | core | Mejoras (8 líneas) y herramientas desbloqueadas | `init`, `start`, `buy`, `buyTool`, `levelOf`, `hasTool`, `clear`; `upgraded`, `toolGranted`, `changed` | `upgrades` | — | propio |
| `Ascension` | core | Prestigio: cuenta, Cerebros, perks | `init`, `start`, `ascend`, `canAscend`, `buyPerk`, `markSixStar`; `ascended`, `perkChanged` | `ascension` | — | propio |
| `Mischief` | core | Travesuras: validación, enfriamiento, álbum | `init`, `start`, `request`, `submit`, `cancel`, `unlockDesign`; `started`, `completed`, `failed` | `album` | — | propio |
| `Quests` | core | Misiones diarias, racha y cartel semanal | `init`, `start`, `report`, `claim`, `claimWeekly`; `completed`, `claimed` | `quests` | — | propio |
| `Training` | core | Sala de Entrenamiento (AFK) con check-in y alijo | `init`, `start`, `answer`, `stashSeconds`, `claimStash`; `ticked`, `challengeIssued`, `checkedIn`, `suspect`, `stateChanged` | `training` | — | propio |
| `Cosmetics` | core | Cosméticos desbloqueados y equipados | `init`, `start`, `grant`, `buy`, `equip`, `unequip`; `changed` | `cosmetics` | — | propio |
| `Stats` | core | Contadores para misiones, logros y KPIs | `init`, `start`, `increment`, `get`; `incremented` | `stats` | — | propio |
| `Shop` | core | Compras con Robux: `ProcessReceipt` único y propiedad de pases | `init`, `start`, `requestProduct`, `requestPass`, `owns`, `passState`; `productGranted`, `passChanged` | `purchases` (vía `PlayerData.grantPurchase`) | — | propio |
| `Wanted` | core | Calor y estrellas (1 a 6) por jugador | `init`, `start`, `addHeat`, `setSeen`, `setHidden`, `clear`, `stars`; `heatAdded`, `starsChanged`, `starReached`, `cleared` | — | — | propio |
| `Cops` | core | Policías: guardias de puesto, caminantes, cazadores, detección, persecución, agarre y habilidades | `init`, `start`, `alert`, `witnessed`, `within`, `knockdown`, `stun`, `blind`, `decoy`, `summon`, `dismiss`; `sightChanged`, `caught`, `knockedDown`, `abilityHit`, `bossDefeated` | — | — | propio |
| `Band` | core | Bandas co-op de hasta 8 (sesión) | `init`, `start`, `create`, `invite`, `accept`, `join`, `leave`, `kick`, `setOpen`, `bonus`, `nearby`; `changed`, `inviteReceived` | — | — | propio |
| `Tools` | core | Uso y enfriamiento de acciones y herramientas | `init`, `start`, `use`, `setActive`, `isActive`; `used` | — | — | propio |
| `Arrest` | core | Camioneta, ventana de rescate y arresto | `init`, `start`, `begin`, `isHeld`, `release`; `resolved` | — | — | propio |
| `Plots` | core | Parcelas reclamables del lobby (sesión) | `init`, `start`, `list`, `claim`, `release`, `plotOf`, `ownerOf`; `claimed`, `released` | — | — | propio |
| `Achievements` | core | Logros calculados con contadores ya guardados | `init`, `start`, `sync`, `refresh`, `count`, `isDone`, `progress`; `unlocked` | — | — | propio |
| `Cops_Wanted` | puente | Lo que ven los policías sostiene las estrellas; derribar suma calor | `connect()` | — | — | propio |
| `Wanted_Band` | puente | El calor se contagia a los compañeros cercanos | `connect()` | — | — | propio |
| `Stats_Quests` | puente | Cada contador que sube avanza las misiones | `connect()` | — | — | propio |
| `Game` | main | Contenido, composición y reglas que mezclan cores (incluye `Transit`, el único método de viaje, y `Hub`, las reglas del lobby) | `start(contexto)`, `onLeaving(player)` | — | — | propio |

Se buscó en la librería de módulos (`library.py search`): `Economy`, `Quests`, `Rewards` y `Zones` existen, pero no sirven tal cual (la moneda necesita Botín, las misiones son diarias y no de objetivos, y las zonas necesitan estar adentro y no solo entrar una vez). Quedan como candidatos a publicar al cerrar el juego.

### Estado para la UI

La interfaz solo presenta lo que decide el servidor.

**Atributos del jugador** (los escribe el servidor):

| Atributo | Tipo | Lo escribe | Significado |
| --- | --- | --- | --- |
| `Level`, `Xp`, `XpNeeded` | número | `Progress` | Nivel (1 a 50), XP en el nivel y XP para el siguiente (0 en el nivel máximo) |
| `Dinero`, `Cerebros` | número | `Economy` | Saldos guardados |
| `Botin`, `BotinCap` | número | `Economy` | Botín sin depositar y capacidad |
| `Stars` (0–6), `Heat`, `WantedState` (`clear`, `seen`, `searching`), `Spotted` | número, número, texto, booleano | `Wanted` | Estrellas, calor y estado: `searching` = estrellas parpadeando; `Spotted` = un policía te ve ahora mismo (`seen` dura 10 s más) |
| `Hidden` | booleano | `Game/World` | Está escondido y bajando estrellas |
| `District` | texto | `Game/World` | Id del nivel de `Levels.json` donde está (`lobby` o un distrito) |
| `PlotId` | texto | `Plots` | Id de la parcela reclamada (vacío si no tiene) |
| `AchCount`, `Ach_<id>` | número | `Achievements` | Logros logrados y progreso de cada uno (sin pasar de la meta) |
| `Speed` | número | `Game/Movement` | Velocidad actual (studs/s) |
| `TutorialStep` | texto | `Game/Reactions` | `graffiti`, `escape`, `deposit`, `upgrade` o vacío |
| `Up_<id>` | número | `Upgrades` | Nivel de cada mejora: `zapatillas`, `sigilo`, `bolsillos`, `manos`, `fortachon`, `cinta`, `bateria`, `gimnasio` |
| `Tool_<id>` | booleano | `Upgrades` | Herramienta comprada: `tarta`, `banana`, `humo`, `patineta`, `senuelo` |
| `ToolReady_<id>` | número | `Tools` | Hora del servidor (`Workspace:GetServerTimeNow()`) en que vuelve a estar lista: `dash`, `push` y las herramientas |
| `AscensionCount`, `AscensionBonus`, `AscensionFee`, `Perk_<id>` | número | `Ascension` | Ascensiones, bono aditivo, cuota de la siguiente y nivel de cada perk |
| `QuestCount`, `Quest<i>Id`, `Quest<i>Progress`, `Quest<i>Goal`, `Quest<i>Claimed`, `QuestStreak`, `WeeklyProgress`, `WeeklyGoal`, `WeeklyClaimed` | varios | `Quests` | Misiones diarias (i = 1 a 3), racha y cartel semanal |
| `AfkActive`, `AfkPaused`, `AfkReason`, `AfkUsed`, `AfkCap`, `AfkNextCheckIn` | varios | `Training` | Estado de la Sala (segundos pagados hoy, tope y falta para el check-in) |
| `BandId`, `BandName`, `BandColor`, `BandSize`, `BandLeader`, `BandOpen`, `BandMembers`, `BandBonus` | varios | `Band` | Banda del jugador (`BandMembers` = UserIds separados por coma) |
| `Equipped_<slot>`, `Owns_<id>` | texto, booleano | `Cosmetics` | Equipamiento (`skin`, `aura`, `trail`, `badge`, `cinta`) y cosméticos que tiene |
| `Pass_<key>` | booleano | `Shop` | Pases: `money2x`, `aura_vip`, `stash_extended`, `phone` |
| `Arrested`, `ArrestEndsAt` | booleano, número | `Arrest` | Está en la Camioneta y hora del servidor en que termina la ventana |
| `DataStatus` | texto | `PlayerData` | Estado de la carga del perfil |

**Atributo de los policías** (modelo en `Workspace.Cops`): `Telegraph` (booleano) mientras preparan una habilidad.

**Remotes** (un solo RemoteEvent `ReplicatedStorage.Net`, mensajes por nombre; el cliente solo envía intenciones y el servidor valida tipo, rango, contexto y frecuencia):

| Dirección | Mensaje | Payload | Validación |
| --- | --- | --- | --- |
| Cliente → servidor | `mischief_submit` | `{ id, success }` | Sesión propia, tiempo mínimo y máximo, servidor sin confiar en `success` para el pago del Timbrazo |
| | `mischief_cancel` | — | — |
| | `use_tool` | `{ id, direction? }` | Id conocido, vector finito, enfriamiento y propiedad |
| | `buy_upgrade`, `buy_tool`, `buy_cosmetic`, `buy_perk` | `{ id }` | Dentro de una Guarida, nivel, fondos, máximo |
| | `equip_cosmetic`, `unequip_cosmetic` | `{ id }`, `{ slot }` | Propiedad |
| | `deposit`, `spray` | — | Sin estrellas (depósito), cerca del Pay'n'Spray |
| | `ascend` | — | Guarida, sin estrellas, nivel 50 y fondos |
| | `travel` | `{ id }` | Destino conocido; nivel, sin estrellas/arresto/travesura, desde zona segura, enfriamiento |
| | `plot_go`, `plot_release` | — | Tener parcela; en el lobby |
| | `claim_quest`, `claim_weekly`, `claim_stash` | `{ id }` | Misión completada; alijo en la Guarida |
| | `afk_answer` | `{ id, choice }` | Reto vigente, tiempo humano |
| | `band` | `{ action, userId?, bandId?, value? }` | Jefe para invitar, expulsar y abrir; cupo |
| | `shop_product`, `shop_pass` | `{ key }` | Clave del catálogo; ID real cargado |
| Servidor → cliente | `notify` | `{ kind, … }` | `mischief`, `mischief_failed`, `stars`, `escaped`, `arrested`, `arrest_result`, `rescued_other`, `deposit`, `spray`, `level`, `medal`, `quest_reward`, `ascended`, `ability`, `travel_locked`, `achievement`, `error` |
| | `mischief_start` | `{ id, name, game, duration, party, coop }` | `game.type`: `sequence`, `hold`, `mash`, `timing`, `memory` |
| | `travel` | `{ phase: out/in, name, seconds }` | Fundido a negro del viaje |
| | `hub_inspect` | `{ userId }` | Abre el perfil del dueño de la parcela que se tocó |
| | `afk_challenge` | `{ id, options, target, window }` | Muestra los íconos en lugares al azar y pide tocar el de `target` |
| | `afk_result`, `stash_claimed` | `{ result }`, `{ seconds }` | — |
| | `band_invite`, `band_list` | `{ fromUserId, fromName }`, lista | — |
| | `dash` | `{ direction, speed }` | El impulso lo aplica el cliente |

Los minijuegos (`sequence`, `hold`, `mash`, `timing`, `memory`) y las pantallas (HUD, tienda, Ascensión, banda, misiones, Sala) son del UI designer; el cliente no escribe en `src/client/UI/`.

## Suposiciones y criterios de aceptación

### Suposiciones (del game designer)

- **Suposición:** nombres y personajes de policías son **originales** (parodia del humor *brainrot*) para no usar personajes con derechos de terceros.
- **Suposición:** "orinar en público" se sustituye por el **Hidrante** por política de contenido.
- **Suposición:** el derribo es slapstick sin sangre; las persecuciones no incluyen armas realistas ni logos de policía reales.
- **Suposición:** el juego se publica como `release-candidate`; fases A/B/C permiten un lanzamiento parcial.
- **Suposición:** nivel máximo 50 y Ascensión máxima 10; ambos se pueden extender con LiveOps.
- **Suposición:** las cifras (curva de XP, ingreso por minuto, tiempos) son diseño y se calibrarán con datos.
- **Suposición:** la mayoría de los jugadores usa celular: todo se puede jugar con un dedo.
- **Suposición:** el check-in de la Sala AFK cuenta como input real para la detección de inactividad de Roblox, pero **no está verificado**: Roblox no documenta el umbral (se reporta ~20 min) y `Player.Idled` tiene reportes de comportamiento irregular. Hay que probarlo en Studio y en una experiencia publicada antes de confiar en él. No se usa `VirtualUser` ni teletransportes para evitar la desconexión.
- **Suposición:** el AFK paga con el mismo bono total aditivo que el juego activo (con tope ×8); el tope diario y el ritmo reducido evitan que desplace a las travesuras.
- **Suposición:** el **Colegio** es un edificio con patio, cantina y pasillos; los objetivos de las travesuras son objetos y adultos NPC (conserje, vendedor), nunca alumnos, y no hay acoso a personajes. Si la política de contenido lo pide, se reemplaza por otro distrito (ej.: Parque o Mercado) sin cambiar los números.
- **Suposición:** la banda es un grupo temporal de sesión (no se guarda); el bono se suma (+12 % por compañero activo) y no se multiplica; un servidor de 16 admite dos bandas completas.
- **Suposición:** la **Playa** (arena −15 %) y el **Colegio** reemplazan al Mercadito y a la Avenida del diseño anterior; sus travesuras se reubicaron por nivel.
- **Suposición:** los jugadores marcados con `afk_suspect` no se sancionan automáticamente: solo pierden el bono de check-in hasta que respondan bien.

### Criterios de aceptación (observables)

1. **Entrar nuevo:** en ≤ 5 s se ve la flecha al muro de graffiti, y se completa la travesura en ≤ 20 s (`first_mischief`).
2. **Persecución guionada:** aparece una estrella al ser visto por el Patata y baja a 0 al esconderse o alejarse (`first_escape`), sin arresto.
3. **Depósito:** mantener 1,5 s en la Guarida convierte Botín en Dinero y sube el contador de Dinero (`first_deposit`).
4. **Primera compra:** con ≥ $100 se compran Zapatillas 1 y la velocidad sube 1,5 (visible en la medición del servidor).
5. **Arresto:** un policía que se mantiene a < 3,5 studs durante 0,7 s arresta; el Botín baja 40 % (o menos con Bolsillos) y reaparece en la Guarida; el Dinero no cambia.
6. **Velocidad real:** a nivel 14 con Zapatillas 3 el jugador (≈ 26) deja atrás a un Patata y a una Capibara a pie, pero no a un Tiburón (30) en línea recta.
7. **Derribo:** una Embestida con poder suficiente derriba un Patata y lo deja 4 s en ragdoll; contra un Tiburón con poder < 30 no lo derriba.
8. **Techo de estrellas:** a nivel 3 el calor no pasa de ★2 aunque se acumule; a nivel 6 sube a ★3.
9. **Distritos:** el Colegio no se puede cruzar antes del nivel 6, la Playa antes del 14, el Centro antes del 20, el Distrito Queso antes del 26 y el Puerto antes del 40 (el cartel avisa); los seis están en el mismo place.
10. **Pay'n'Spray:** pagar `120 × ★ × (1 + 0,05 × nivel)` quita las estrellas y descuenta el Dinero.
11. **Ascensión:** a nivel 50 con la cuota, reinicia nivel/Dinero/mejoras y suma ×(1 + 0,5 × A); la segunda carrera llega a nivel 50 en ≈ 182 min de diseño.
12. **Salir buscado:** salir con ★ ≥ 1 aplica la pérdida de arresto; salir sin estrellas deposita el Botín.
13. **Carga fallida:** si no carga el perfil, el jugador puede jugar sin comprar ni guardar y se le avisa.
14. **Multijugador:** con 16 jugadores, un jugador solo es perseguido por policías que lo identificaron a él (o a su banda); el servidor mantiene ≤ 14 policías por jugador y ≤ 30 por banda.
15. **Celular:** todas las travesuras del MVP se completan con un dedo y ningún botón queda bajo el chat o los controles táctiles.
16. **Monetización:** con IDs pendientes, la compra de cada oferta está desactivada.
17. **Sala AFK, volumen:** un jugador de nivel ≥ 8 con 0 estrellas dentro del volumen empieza a ganar XP y Dinero (≈ 15 % del ritmo del nivel); al salir del volumen o ser buscado, el pago se detiene sin pérdidas.
18. **Check-in:** el reto aparece a los 6 min ±15 % (Batería 0); responder bien reinicia el contador y da el bono; no responder en 60 s pausa el pago y tocar lo reanuda; tres errores seguidos pausan 5 min.
19. **Anti-bot:** un clic con respuesta en < 0,35 s no da bono; un clic ciego en una posición fija falla porque los íconos cambian de lugar; saltar o hacer clic de forma automática no aumenta lo que paga la Sala.
20. **Tope diario:** pasados 40 min de entrenamiento en el día (UTC) la Sala deja de pagar; al día siguiente vuelve a pagar.
21. **Desconexión:** si Roblox o el jugador desconecta en la Sala, el progreso hasta el último tick queda guardado.
22. **Formar banda:** un jugador invita a otro, este acepta, y ambos ven la etiqueta de banda; se pueden unir hasta 8; el noveno no entra.
23. **Bono de banda:** con 4 miembros activos a ≤ 80 studs, cada travesura paga +36 % de Botín y XP; un miembro a 200 studs o sin acción en 30 s no cuenta.
24. **Travesura de banda:** el Mural Gigante no arranca con 1 jugador; con 2 o más paga a cada uno `40 × (1 + 0,25 × (n − 1))` y el servidor valida que todos participen.
25. **Contagio y techo:** cuando un miembro gana calor, los miembros a ≤ 100 studs reciben la mitad; un miembro de nivel 3 no pasa de ★2 aunque el resto llegue a ★4.
26. **Rescate:** un compañero que toca la Camioneta a tiempo libera al arrestado, que pierde solo el 20 % del Botín; si nadie llega en 5 s, pierde el 40 %.
27. **Sala AFK:** el bono de banda no se aplica a lo que paga la Sala.
28. **Playa:** la arena baja un 15 % la velocidad de jugadores y policías terrestres; el paseo marítimo no.
29. **Lobby:** un jugador que entra aparece en La Guarida (nunca en un distrito), no ve ningún distrito y ningún policía lo detecta ni lo persigue; puede depositar y comprar en cualquier punto del lobby.
30. **Patrulla sin estrellas:** con 0 estrellas y sin hacer una travesura, pasar delante de un policía de patrulla (dentro de su cono, de cerca) no lo hace perseguir ni da estrella; hacer una travesura a su vista da calor y la primera estrella.
31. **Viajes:** cada portal lleva a su distrito solo con el nivel pedido (si no, "se abre en el nivel N"); con estrellas, arrestado, en plena travesura o fuera de una zona segura no se viaja; el fundido a negro cubre el teletransporte y el jugador nunca cae al vacío al llegar; el portal de regreso lleva al lobby.
32. **Parcelas:** dos jugadores no pueden reclamar la misma parcela ni un jugador dos; al salir, la parcela queda libre; el cartel y la torre siguen el nivel del dueño y tocar una parcela ajena abre su perfil.
33. **Logros:** cruzar la meta de un logro avisa una sola vez; tras una Ascensión no se pierden; el progreso se ve en el menú de La Guarida.

## Pendientes entre skills

- game-designer → environment-artist: pase de arte de los seis distritos (cerrado: `design/ENVIRONMENT.md` y `Environment.json`; sin assets del usuario, con referencias de lugar por escrito)
- game-designer → monetization (game-passes, developer-products): completar el catálogo con IDs reales, precios vigentes y pruebas; el código ya existe con las ofertas desactivadas (ID 0) (abierto)
- builder → game-designer: la Fianza del GDD no está implementada (queda para después); las demás ofertas sí (abierto)
- ui-designer → builder: mostrar el precio en Robux de cada oferta cuando existan los IDs (abierto)
- ui-designer → environment-artist: iluminación por distrito en el cliente según el atributo `District` (abierto; Roblox aplica una sola luz desde el servidor)
- environment-artist → level-designer: el `paseo` de la Playa y los `spawn` comparten plano (y = 1,00): separarlos 0,05 studs (abierto)
- ui-designer → art-director: íconos propios de estrellas, policías y herramientas en lugar de emojis (abierto)
- analytics-dev → game-designer: la retención con y sin banda se calcula comparando cohortes en Creator Analytics (abierto)
- builder → level-designer: probar en Studio el ancho de las calles a 60 studs/s, que los portales lleven al spawn correcto y que el streaming no muestre otro nivel; ajustar `Levels.json` si hace falta (abierto)
- game-designer → data-architect, art-director, level-designer, ui-designer, analytics-dev y builder: pedidos de la primera pasada (cerrado: `DATA.md`, `ART.md`, `LEVELS.md`, `UI.md`, `ANALYTICS.md` y el código existen y pasan sus validadores)
