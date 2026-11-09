---
name: roblox-level-designer
description: Diseñar niveles y mapas de juegos Roblox como datos validados. Convierte el brief de niveles del GDD en design/LEVELS.md (intención, curva de dificultad y ritmo) y src/shared/Levels.json (piezas, posiciones, checkpoints, peligros y plataformas móviles), y comprueba con un script que cada salto sea posible con la física declarada. Úsalo para etapas de obby, arenas de rondas, parcelas de tycoon, zonas de simulador o mapas de oleadas, y para ajustar la dificultad o arreglar saltos de niveles existentes. Cuando el pedido es construir el juego completo, roblox-game-builder lo carga si el GDD activa niveles. No programa la lógica del juego ni decide loop o economía; eso es de roblox-game-builder y roblox-game-designer.
metadata:
  version: "1.1.0"
  last_verified: "2026-10-08"
---

# Roblox Level Designer

Convierte la intención de diseño en espacios jugables: dónde está cada plataforma, qué tan lejos queda el siguiente salto, dónde reaparece el jugador y cómo sube la dificultad. Los niveles se escriben como **datos** en `Levels.json` para que un script pueda comprobar cada salto antes de abrir Studio, y para que el builder los construya sin reinterpretarlos.

Un nivel con un salto imposible o un pico de dificultad injusto se detecta acá en segundos; en Studio, después de programar, cuesta mucho más.

## Qué produces y qué no

- Lees del `GDD.md`: Brief de niveles, Física y métricas del personaje, Contenido y alcance (máximo de jugadores) y `project.genre`.
- Escribes `<Juego>/design/LEVELS.md` con la [plantilla](references/levels-template.md) y `<Juego>/src/shared/Levels.json` con el [formato de niveles](references/level-format.md). Rojo convierte ese JSON en el ModuleScript `ReplicatedStorage.Shared.Levels`.
- El aspecto final (materiales, decoración, terreno, luces) es del [environment artist](../roblox-environment-artist/SKILL.md), que viste tus niveles sin moverlos. Tus colores y materiales sirven para leer la geometría; los `prop` de `Levels.json` son bloques de referencia de la escena.
- No escribes código: el builder construye los niveles a partir de los datos y programa su lógica. No cambias loop, economía ni brief: si el brief pide algo imposible o incoherente, propón la alternativa en "Pendientes entre skills" del GDD, como indica el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md).
- Si no hay brief (el usuario pidió niveles directamente), escribe uno breve al principio de `LEVELS.md`, márcalo como suposición y déjalo en Pendientes para que el game designer lo confirme. Sin `GDD.md`, los pedidos a otros skills van en "Suposiciones y pendientes" de `LEVELS.md`. Si el usuario pidió niveles y el frontmatter tiene `design.levels: false`, cámbialo a `true` y regístralo, como permite la excepción del contrato.
- Haz como máximo una pregunta, solo si falta algo que cambia el layout (por ejemplo, el máximo de jugadores de una arena).

## Juegos con varios places

Si el GDD declara varios places (`project.places` como lista), cada nivel lleva `place` con la clave del place donde se juega: cada place es un mundo aparte, así que niveles de places distintos pueden usar las mismas coordenadas, y cada place necesita su propio spawn habilitado (o que el código ubique a quien llega). `validate_levels.py` revisa la superposición y los spawns por place; `check_game.py` del builder compara cada `place` con el GDD. Un nivel sin `place` va al place de inicio.

## 1. Métricas del personaje

Copia `walkSpeed`, `jumpHeight` y `gravity` del GDD al bloque `physics` de `Levels.json`. Si el GDD no los fija, usa 16, 7.2 y 196.2 y anótalo como suposición. El juego aplica estos valores explícitamente, así que son la única fuente de verdad de la física.

Corre el validador sobre un borrador y anota en `LEVELS.md` las dos cifras que imprime: **alcance en plano** y **subida útil**. Con ellas clasifica los saltos:

| Uso de la capacidad | Para qué |
| --- | --- |
| Hasta 60 % (`validation.onboardingRatio`) | Onboarding y tramos de descanso |
| 60 % a 80 % | Desafío normal |
| Más de 80 % (`validation.demandingRatio`) | Exigente: pocos, anunciados y con checkpoint cerca |

Como punto de partida, plataformas de 6 studs o más en el primer nivel, 4 a 5 en niveles normales y 2 a 3 solo en tramos exigentes. Ajusta con pruebas.

## 2. Curva de dificultad y ritmo

- Cada nivel cumple la dificultad buscada del brief (1 a 10). La dificultad sube por **combinación** de mecánicas conocidas, no solo por saltos más largos. Como punto de partida, relaciona la dificultad con lo que mide el validador:

  | Dificultad | Uso máximo | Saltos exigentes | Piezas móviles o giratorias |
  | --- | --- | --- | --- |
  | 1 a 2 | Hasta 60 % | Ninguno | Ninguna |
  | 3 a 4 | Hasta 70 % | Como mucho uno | Un tramo |
  | 5 a 6 | Hasta 80 % | Uno o dos, con checkpoint antes | Varias, por separado |
  | 7 a 10 | Más de 80 % | Varios, siempre con checkpoint antes | Combinadas |

- Entre niveles consecutivos, la dificultad no sube más de 3 puntos (regla del game designer); una bajada es un descanso deliberado.
- Dentro del nivel: introducir una mecánica en condiciones seguras, practicarla, combinarla y cerrar con una prueba. Entre picos, un tramo de descanso.
- El primer nivel es onboarding: saltos cómodos, un peligro aislado e inconfundible y un checkpoint temprano.
- Los peligros se ven: material y color distintos del piso (por ejemplo `Neon` rojo o naranja), nunca escondidos. Los peligros móviles empiezan lentos.
- Checkpoints con la cadencia del brief; el validador avisa si hay demasiados saltos seguidos sin uno.

## 3. Construir los datos

Sigue el [formato de niveles](references/level-format.md). Lo esencial:

- Cada nivel tiene su `origin`; sepáralos lo suficiente para que no se superpongan (en obbies, unos 200 studs entre niveles suele alcanzar).
- `layout: "linear"` para recorridos: `start`, `path` en orden y una pieza `goal`. Arenas, hubs y parcelas usan `arena`, `hub` o `plots`, con `spawn` y `zone`.
- Un peligro grande debajo de cada recorrido (`hazard`), para que caer reinicie rápido.
- Plataformas móviles con `motion.type: "linear"` (arrastran al jugador). Barras giratorias como piezas `hazard` con `motion.type: "spin"` y `collide: false`, para que dañen sin lanzar personajes por el aire.
- Un `hazard` sin `damage` mata. Usa `damage` solo para peligros que restan vida sin matar.
- Las escaleras (`truss`) miden 2 × 2 × N studs, con N par.
- Respeta `budget.maxParts`. La geometría decorativa también cuenta.

Para arenas, parcelas, zonas y mapas de oleadas, lee la sección del género en [layouts por género](references/genre-layouts.md).

## 4. Validar

```bash
python <skill-dir>/scripts/validate_levels.py <Juego>/src/shared/Levels.json
```

En Windows, usa `python` o `py -3` si `python3` no existe. El script revisa estructura, ids, checkpoints, spawns, peligros sobre zonas seguras, superposición de niveles, presupuesto y cada salto del recorrido; las plataformas móviles se evalúan en sus dos extremos.

- Corrige todos los **ERROR** y vuelve a correr hasta que no quede ninguno.
- Cada **WARN** se corrige o se justifica en `LEVELS.md`.
- Compara la tabla de curva medida con la dificultad declarada y ajusta los niveles que no coinciden.
- El modelo de salto es una aproximación. Si una prueba en Studio contradice al validador, calibra el bloque `validation` de `Levels.json` y anota por qué; no ignores un error.

## 5. Documentar

Completa `LEVELS.md`: métricas, tabla de curva (la que imprime el validador), intención de cada nivel, notas para el builder (piezas con comportamiento especial, nombres de zonas) y el resultado de la validación con fecha.

## Autorrevisión

- [ ] `physics` coincide con el GDD.
- [ ] El validador termina con 0 errores y cada advertencia está corregida o explicada.
- [ ] El primer nivel enseña sin saltos de más del 60 % ni peligros sorpresa.
- [ ] La curva medida acompaña a la dificultad declarada, con descansos entre picos.
- [ ] Cada recorrido lineal tiene `start`, `goal`, checkpoints y peligro debajo.
- [ ] Las arenas, parcelas y spawns alcanzan para el máximo de jugadores del GDD.
- [ ] `LEVELS.md` explica la intención de cada nivel, no solo sus coordenadas.

## Entrega y siguiente paso

Resume en pocas líneas: cantidad de niveles, curva, resultado del validador y pendientes. Si el usuario pidió el juego completo, el siguiente paso es el builder, que construye el mundo desde `Levels.json`. Si solo pidió niveles, termina aquí y ofrece la implementación.
