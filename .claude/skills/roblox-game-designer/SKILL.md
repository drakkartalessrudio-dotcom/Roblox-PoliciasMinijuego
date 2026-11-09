---
name: roblox-game-designer
description: Diseñar juegos de Roblox antes de programarlos. Convierte una idea o un GDD incompleto en el GDD de la fábrica con pilares, loop principal, onboarding de los primeros 60 segundos, progresión, economía con fuentes y sumideros, física del personaje, brief de niveles, KPIs objetivo, qué se conserva entre sesiones y selección de módulos (datos, niveles, monetización, analíticas, LiveOps). Úsalo siempre que el usuario quiera idear, definir, revisar o balancear un juego de Roblox, su economía, progresión u onboarding, aunque no diga GDD. Cuando el pedido es construir el juego completo, roblox-game-builder lo carga como primer paso. No escribe código Luau ni niveles detallados; la implementación es de roblox-game-builder, los niveles de roblox-level-designer y el catálogo y cobro de los módulos de monetización.
metadata:
  version: "1.2.0"
  last_verified: "2026-10-08"
---

# Roblox Game Designer

Decide qué juego se va a construir y por qué va a ser divertido, antes de escribir código. El resultado es `GDD.md`: un documento que el builder puede implementar sin adivinar, que el level designer puede convertir en niveles y que dice qué medir para saber si funcionó.

Diseñar primero ahorra iteraciones caras: un loop confuso o una economía que se rompe en el minuto 20 no se arreglan con mejor Luau.

## Qué produces y qué no

- Escribes `<Juego>/GDD.md` con la [plantilla de la fábrica](../roblox-game-builder/references/gdd-template.md): frontmatter y secciones de diseño. Si el usuario no indicó carpeta, usa una con el nombre del juego en PascalCase.
- Respetas el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md): no escribes Arquitectura ni Assets (son del builder), ni el catálogo de compras (es de cada módulo de monetización), ni niveles detallados (son del level designer). Si algo de eso te preocupa, déjalo en "Pendientes entre skills".
- Si el usuario trae un GDD, conserva sus decisiones y su redacción. Completa vacíos, marca como **Suposición** lo que agregaste y explica cualquier cambio que propongas antes de aplicarlo si contradice algo que él decidió.
- Haz como máximo **una** pregunta, y solo si el loop principal es realmente ambiguo ("un juego de dragones": ¿carreras, combate, crianza?). En los demás casos decide, registra la suposición y sigue: el usuario puede corregir el GDD más rápido que responder un cuestionario.

## 1. Intención y alcance

- **Fantasía** en una frase: quién es el jugador y qué hace. **Público** y **duración de sesión** esperados.
- **Pilares**: hasta tres frases que sirvan para decidir. Cada sistema del MVP debe reforzar al menos uno; si no refuerza ninguno, va a "posterior".
- **Género**: elige la referencia más cercana y lee solo esa: [obby](references/genres/obby.md), [simulador o clicker](references/genres/simulator.md), [tycoon](references/genres/tycoon.md), [rondas](references/genres/rounds.md) o [supervivencia por oleadas](references/genres/survival.md). Mezcla si hace falta. Las referencias son puntos de partida: no agregues monedas, rondas ni tienda si el juego no las necesita.
- **Modo**: `prototype` para validar el loop con el menor alcance útil; `release-candidate` cuando el usuario quiere publicar o entregar un juego terminado. Un modo no cancela requisitos pedidos.
- **Plataformas** objetivo y **máximo de jugadores** por servidor.

**¿Uno o varios places?** Por defecto, uno (`project.places: 1`). Propón varios places cuando el mundo es grande o tiene muchas zonas, cuando hay un vestíbulo y partidas en servidores propios, o cuando los modos necesitan cantidades de jugadores o reglas muy distintas; para pocos mapas chicos alcanza con uno que carga el mapa de cada ronda. Con varios, declara la lista (`id`, `role`: `start`, `match` o `area`, y `maxPlayers`) y escribe la sección **Places y viajes**: qué tiene cada place, cuándo se viaja, a qué servidor, qué pasa si el viaje falla. Los criterios y el costo (viajes que pueden fallar, pruebas solo publicado) están en [varios places](../roblox-game-builder/references/multi-place.md). Si el onboarding cruza places, nombra sus pasos igual en todos.

## 2. Loop principal

Describe tres escalas, cada una con una **decisión** real del jugador:

- **Momento a momento** (segundos): la acción básica y su feedback.
- **Sesión** (minutos): qué objetivo organiza la partida y cómo termina.
- **Regreso** (días): qué progreso, colección o meta lo trae de vuelta. En un prototipo puede quedar como hipótesis.

Define progreso, victoria, pérdida, respawn e ingreso a mitad de partida. Explica cómo funciona en solitario y con poca gente: si el juego solo es divertido con el servidor lleno, la mayoría de las sesiones reales van a ser malas.

## 3. Onboarding: los primeros 60 segundos

El jugador nuevo decide muy rápido si se queda. Diseña lo que ve y hace segundo a segundo:

- Un objetivo visible y la posibilidad de actuar en los primeros segundos, sin leer párrafos.
- La primera recompensa o logro poco después; el primer loop completo dentro del primer minuto como objetivo orientativo, a confirmar con datos.
- Enseña haciendo y de a un concepto por vez. Muestra los controles de cada plataforma objetivo.
- Quien vuelve no repite el tutorial.

Lista los pasos del funnel de onboarding con nombres estables en `snake_case` (`joined`, `first_action`, `first_reward`…). Cada paso debe ser un hecho que el servidor pueda observar; la medición depende de esos nombres.

## 4. Progresión y dificultad

- Metas cortas, medias y largas que se encadenan. Desbloquea **decisiones nuevas** (una herramienta, una zona, una regla), no solo números más grandes.
- Ritmo: introducir, practicar, combinar, sorprender; con momentos de descanso entre picos. Entre niveles consecutivos, la dificultad buscada no sube más de 3 puntos; una bajada es un descanso deliberado.
- Dificultad justa: los peligros se anuncian antes de castigar, reintentar es rápido y el castigo es proporcional. En multijugador, evita que el que va ganando quede imposible de alcanzar.
- Puntos naturales de salida y motivos para volver que no castiguen la ausencia.

## 5. Economía

Si el juego tiene moneda o recursos, lee [economía](references/economy.md) y completa la tabla de fuentes y sumideros, el tiempo hasta cada hito y la regla de apilamiento de multiplicadores. Sus valores van a la sección Parámetros ajustables (paso 7).

Si no hay moneda ni datos persistentes, escríbelo. No agregues una economía para que el juego "parezca completo".

**Qué se conserva.** En "Estado y economía", escribe una lista de promesas al jugador: qué conserva entre sesiones ("sigue desde el último checkpoint", "conserva sus mascotas y su nivel", "lo comprado con Robux no se pierde") y qué pasa si la carga de su progreso falla (por ejemplo, juega sin poder comprar). Escribe **qué** se promete, no cómo se guarda: los campos, las secciones y los límites los decide el [data architect](../roblox-data-architect/SKILL.md). Cada promesa debe ser algo que el jugador nota si se pierde; lo que se reconstruye al entrar (la ronda, la posición) no se promete.

## 6. Niveles y física del personaje

- Activa `design.levels: true` cuando el juego tiene espacios diseñados cuyo layout importa: etapas de un obby, arenas, parcelas de un tycoon, mapas de rondas. Déjalo en `false` si el mundo es procedural o trivial.
- Fija la física en "Física y métricas del personaje": `walkSpeed`, `jumpHeight` y `gravity`, con la sensación que buscas. El juego los aplica explícitamente; la referencia habitual de Roblox es 16, 7.2 y 196.2.
- Con niveles, escribe el **Brief de niveles**: cantidad, y por nivel objetivo, mecánica que introduce, dificultad buscada (1 a 10) y tiempo esperado; cadencia de checkpoints y restricciones de tamaño. El level designer lo convierte en datos validados.

## 7. Parámetros ajustables

En todo juego, no solo en los que tienen economía, completa la sección "Parámetros ajustables" del GDD: cada número que alguien querría tocar sin programar (tiempos, daño, velocidades de enemigos, precios en moneda del juego, recompensas), con nombre en formato `Seccion.Valor`, valor inicial y para qué sirve. El builder los copia a `Config.luau` y el juego los lee con `Tuning.get`; LiveOps podrá ajustarlos en vivo. La física del personaje va en su propia sección, no acá.

## 8. Módulos: monetización, analíticas y LiveOps

- **Monetización**: decide si hay y cuál, con una hipótesis de por qué encaja con el juego. Las claves válidas son `developer-products`, `game-passes`, `creator-rewards` y `avatar-ugc`; respeta lo que pidió el usuario. El recorrido gratuito debe ser completo y, salvo decisión explícita, lo pagado prioriza comodidad, personalización y capacidad antes que poder competitivo. Si una moneda comprable con Robux puede usarse para premios aleatorios, aplica la política de aleatoriedad pagada. En "Monetización seleccionada" escribe las ofertas, su beneficio y la hipótesis; puedes proponer rangos de precio como hipótesis comercial. El catálogo con IDs, el precio vigente, el flujo de compra y sus pruebas los completa el módulo correspondiente.
- **Datos** (`design.data`): `true` cuando el juego promete conservar algo entre sesiones: progreso, colección, moneda, compras con beneficio que dura. Casi siempre en un `release-candidate`; en un prototipo, solo si el usuario pidió que algo se guarde. Con LiveOps o con Developer Products de beneficio permanente, también. [roblox-data-architect](../roblox-data-architect/SKILL.md) convierte tus promesas en el esquema y fija `data.persistence`.
- **Dirección de arte** (`design.art`): `true` cuando el aspecto importa para el juego, casi siempre en un `release-candidate`. [roblox-art-director](../roblox-art-director/SKILL.md) define el estilo a partir de tu fantasía y tus pilares.
- **Pase de arte** (`design.environment`): `true` cuando hay niveles y dirección de arte y el aspecto importa, casi siempre en un `release-candidate`. [roblox-environment-artist](../roblox-environment-artist/SKILL.md) viste los niveles sin cambiar cómo se juegan.
- **Interfaz** (`design.ui`): `true` cuando el juego tiene más que un HUD mínimo (tienda, inventario, menús) o se juega en celular o consola. [roblox-ui-designer](../roblox-ui-designer/SKILL.md) diseña las pantallas a partir de "Plataformas e interacción" y del onboarding.
- **Analíticas** (`analytics.enabled`): `true` en un `release-candidate` o cuando el usuario quiere medir; los KPIs se escriben igual. [roblox-analytics-dev](../roblox-analytics-dev/SKILL.md) los convierte en eventos con los nombres que fijes aquí.
- **LiveOps** (`liveops.enabled`): solo si hay persistencia y alguien va a operar eventos. En un prototipo, `false`. [roblox-liveops](../roblox-liveops/SKILL.md) elige cuáles de los parámetros ajustables se pueden cambiar en vivo y arma el calendario.

## 9. KPIs objetivo

Lee [KPIs](references/kpis.md) y elige entre 3 y 6 indicadores ligados a los pilares y al funnel de onboarding. Para cada uno: definición con denominador y ventana, objetivo inicial, cómo se mide y qué decisión dispara. Sin datos previos, el objetivo es "medir línea base" o una hipótesis marcada como tal; no presentes cifras de la industria como hechos.

## 10. Criterios de aceptación

Escribe casos observables que el builder pueda verificar: entrar, actuar, recibir recompensa, fallar, ganar, reaparecer, salir y volver, con la población prevista. Un buen criterio se comprueba mirando el juego, no leyendo el código.

## 11. Autorrevisión

Antes de entregar, revisa:

- [ ] La fantasía y el loop se entienden sin explicación oral.
- [ ] Cada sistema MVP refuerza un pilar; lo demás está en "posterior".
- [ ] Los primeros 60 segundos están descritos y el funnel tiene nombres estables observables desde el servidor.
- [ ] La economía tiene sumideros para cada fuente ilimitada y una tabla de tiempo hasta hitos sin muros bruscos.
- [ ] "Parámetros ajustables" lista todos los números que alguien querría tocar, con nombre, valor inicial y uso.
- [ ] El frontmatter declara `mode`, `genre`, `platforms`, `design.levels`, `design.data`, `monetization.enabled`, `analytics.enabled` y `liveops.enabled`.
- [ ] "Estado y economía" lista qué se promete conservar (o dice que nada se guarda) y qué pasa si la carga falla.
- [ ] Con `design.levels: true` hay brief de niveles y física explícita.
- [ ] Los KPIs tienen definición, objetivo honesto y decisión asociada.
- [ ] Las suposiciones están marcadas y las preguntas abiertas, listadas.

## Entrega y siguiente paso

Resume en el chat, en pocas líneas: fantasía, loop, qué entra en el MVP, módulos activados y preguntas abiertas.

- Si el usuario pidió construir el juego, sigue el orden del contrato: data architect si `design.data` es `true`, level designer si `design.levels` es `true`, luego los módulos de monetización activados y por último el builder.
- Si solo pidió diseño, termina con el GDD y ofrece el siguiente paso.
- Si pidió **revisar** un GDD, entrega primero los problemas ordenados por impacto y los cambios propuestos; edita el archivo cuando el usuario lo pida o cuando el cambio solo completa vacíos.
