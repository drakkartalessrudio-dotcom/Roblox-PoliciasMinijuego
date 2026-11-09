---
name: roblox-environment-artist
description: Hacer el pase de arte de los niveles de un juego de Roblox para que dejen de parecer blockout. Viste la geometría del level designer con el tema del art director (materiales, zócalos, cornisas, pilastras, guardas y baldosas en muros y pisos), agrega props hechos con Parts o los modelos, texturas, sonidos y animaciones que aporte el usuario, terreno, luces y cielo, y lo escribe como datos en design/ENVIRONMENT.md y src/shared/Environment.json. Pregunta por referencias, mira vistas previas antes de Studio y valida que la decoración no cambie el juego y se vea bien (terreno que no asoma, sin caras superpuestas ni superficies lisas). Úsalo cuando los niveles se vean vacíos, grises, de plástico o sin terminar, cuando el usuario pida decorar o ambientar un mapa o usar sus propios modelos o texturas, o cuando el GDD active design.environment. No mueve piezas jugables (roblox-level-designer), no define la paleta (roblox-art-director) ni hace la interfaz (roblox-ui-designer).
metadata:
  version: "1.2.0"
  last_verified: "2026-10-13"
---

# Roblox Environment Artist

Convierte niveles de blockout en lugares. El level designer decide dónde se juega y el art director cómo se ve el juego; este skill decide cómo se ve **donde se juega**, sin tocar lo que el jugador pisa, salta o esquiva.

Un nivel con aspecto de blockout no está "sin adornos": tiene muros y pisos lisos de punta a punta, todo del mismo plástico, nada que diga hacia dónde ir, ningún fondo y una luz plana. Lo que más se ve en pantalla son las superficies grandes; empieza por ellas, no por los props.

## Qué produces y qué no

- Lees `design/LEVELS.md` y `src/shared/Levels.json` (geometría y física), `design/ART.md` y `src/shared/Theme.json` (paleta, materiales e iluminación), la fantasía del `GDD.md` y las referencias y assets del usuario.
- Escribes, según el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md):
  - `design/ENVIRONMENT.md`, con la [plantilla](references/environment-doc-template.md);
  - `src/shared/Environment.json`, con el [formato](references/environment-format.md);
  - las filas de los assets del usuario en la sección "Assets y servicios" del GDD.
- El builder copia `EnvironmentLoader.luau` de sus plantillas, lo llama después de construir los niveles y mapea en `default.project.json` las carpetas de modelos y materiales del usuario: no escribes código.
- Necesitas `Levels.json` y `Theme.json`. Sin ellos, pide los niveles al level designer o el tema al art director con la regla de pendientes; si el usuario pidió el pase de arte, activa `design.environment: true` en el frontmatter (excepción del contrato).

## Reglas que no se rompen

1. **La geometría jugable no cambia.** Ni posición, tamaño, forma, rotación, transparencia ni colisión de una pieza de `Levels.json`. El loader conserva la física del material original aunque cambies el material. Si una pieza estorba la composición, pídele el cambio al level designer.
2. **Peligros, checkpoints, metas y coleccionables conservan el color de su rol** (`hazard`, `interactive`, `goal`, `reward`). Puedes cambiar su material.
3. **La decoración no juega.** Nada en el aire de un salto del recorrido; nada sólido (props con colisión o terreno) al alcance de un salto o en la caída hacia el peligro; agua solo lejos de lo jugable. Ningún prop sin colisión con forma de escalón al alcance: el jugador intentaría pisarlo.
4. **Se ve como se diseñó.** El terreno queda a 4 studs o más de toda pieza: Roblox lo arma con vóxeles de 4 studs, redondea sus bordes y asoma a través de los pisos como manchas. Dos caras en el mismo plano con distinto color parpadean (z-fighting): todo adorno se apoya encima o se separa.
5. **Colores solo del tema**, por rol o por nombre de la paleta. La decoración no usa los colores de los roles de juego ni colores que se confundan con el peligro. Si falta un color, pídelo al art director.
6. **Solo assets del usuario, declarados.** Usa los modelos, texturas, variantes de material, sonidos y animaciones que aporte el usuario, cada uno con su origen y licencia en `assets` y en el GDD. Nunca inventes un ID, nunca busques ni bajes assets por tu cuenta.

## 0. Referencias y assets del usuario

Antes de decidir nada, revisa `<Juego>/assets/`: `reference/` (imágenes de juegos o lugares que le gustan), `models/` (modelos `.rbxm` o `.rbxmx`), `materials/` (variantes de material) y `ASSETS.md` (IDs de texturas, sonidos o animaciones, con su origen). Mira cada imagen de referencia y anota en `ENVIRONMENT.md` qué tomas de ella: paleta, densidad, materiales, formas o luz.

Si no hay nada y el usuario no dijo nada al respecto, pregunta **una vez**, antes de empezar:

> ¿Tenés referencias o assets para usar? Por ejemplo: capturas de juegos cuyo estilo te guste (en `assets/reference/`), modelos 3D exportados desde Studio (en `assets/models/`), texturas o variantes de material, sonidos de ambiente o animaciones (sus IDs). Si no, sigo con piezas de Roblox y la paleta del juego.

Si dice que no, sigue sin volver a preguntar. Cómo prepara cada tipo el usuario, qué permite Roblox con cada uno y qué hacer con los permisos está en [assets del usuario](references/user-assets.md).

## 1. Leer el nivel

Corre el validador de niveles para ver el alcance de un salto con la física del juego y el recorrido:

```bash
python ../roblox-level-designer/scripts/validate_levels.py <Juego>/src/shared/Levels.json
```

El "alcance en plano" es la distancia horizontal que cubre un salto: lo sólido va más lejos que eso de cualquier pieza pisable. Lee en `LEVELS.md` la intención de cada nivel y en `ART.md` los pilares visuales. Genera la vista previa del estado actual (paso 6) para ver de dónde partes.

## 2. Intención por nivel

Escribe en `ENVIRONMENT.md`, para cada nivel, una frase de lugar y momento ("un camino de piedra sobre un mar de lava, de noche"), qué guía la vista hacia la meta y cómo cambia el ambiente a medida que sube la dificultad. Lee la [guía del pase de arte](references/art-pass.md): superficies primero, lectura antes que belleza, un punto de referencia por nivel, fondo de siluetas, grupos en lugar de filas y luz que señala el objetivo.

## 3. Vestir las piezas jugables

En `pieces` de `Environment.json` define el aspecto por tipo (`platform`, `wall`, `spawn`, `checkpoint`, `goal`, `hazard`, `truss`, `collectible`, `prop` y `moving` para lo que se mueve), con ajustes por nivel y por pieza:

- **Superficies grandes:** ningún muro o piso grande queda de plástico liso sin tratar. Usa un material con textura de Roblox (`Plaster`, `Brick`, `CeramicTiles`, `WoodPlanks`, `Carpet`, `Concrete`, `Cobblestone`…) si encaja con el estilo, una variante de material o textura del usuario, y adornos de superficie:
  - muros: `baseboard` (zócalo), `cornice` (cornisa), `pilasters` (pilastras cada tantos studs) y `band` (franja);
  - pisos: `border` (guarda), `grid` (juntas de baldosas) y `checker` (baldosas alternadas);
  - todas las piezas: `trim` (borde claro arriba), `rock` (roca debajo), `pillar` (pilar hasta el peligro) y `base` (cimiento que tapa el hueco con el terreno).
- `color`, `material` y `variation` (hasta 0,15, varía el brillo de cada pieza). Si el material del tema para una superficie es plástico liso y el estilo no lo exige, propón al art director uno con textura.

## 4. Decorar

- **Props.** Copia a `prefabs` los que necesites de la [biblioteca](assets/prefabs.json) (rocas, agujas, árboles, arbustos, faroles, braseros, cristales, cercas, cajas, barriles, ruinas, arcos, nubes, hongos, carteles, bancos, maceteros, faroles dobles, fuentes, puestos de mercado, banderines, casitas, canteros y fachadas de tienda) y asigna sus ranuras de color a la paleta del juego. Puedes crear prefabs nuevos con el mismo formato.
- **Modelos del usuario.** Decláralos en `assets` y colócalos como props con `asset` y la caja `size` donde deben entrar; el loader los escala y les borra los scripts. Si traen animación, agrega `animation`.
- **Reparto.** Coloca a mano lo importante (puntos de referencia, marcos) y reparte el resto con:

  ```bash
  python <skill-dir>/scripts/scatter.py <Juego> --level <id> --prefab pine --count 8 --area X0 Z0 X1 Z1 --ground <y>
  ```

  Con `--asset <nombre>` reparte un modelo del usuario. Descarta los lugares que rompen las reglas y escribe el resultado en `Environment.json`.
- **Terreno** para el suelo y el fondo (`Block`, `Ball`, `Cylinder` o `Wedge`), con su borde en un múltiplo de 4 y a 4 studs o más de toda pieza; el hueco bajo pisos y muros se tapa con `base`. Siempre tiene colisión: lejos de lo jugable.
- **Luces** pocas, con alcance corto y sin sombras, para señalar la meta, los checkpoints o un camino. **Sonidos** de ambiente del usuario en `sounds`.

## 5. Ambiente

Elige en `lighting.preset` uno de los presets de iluminación del tema (con varios places, `lighting.places` elige uno por place: cada place tiene su propia luz); si el nivel necesita otro clima (una cueva, un amanecer) o la luz es plana (sin sombras, ambiente muy alto), pídelo al art director. Agrega nubes (`lighting.clouds`) y colores de terreno (`terrainColors`) de la paleta.

## 6. Mirar la vista previa

```bash
python <skill-dir>/scripts/preview_environment.py <Juego>
```

Dibuja cada nivel en `build/preview/`: una vista general (`iso`) y lo que ve el jugador al aparecer (`player`). **Mira las imágenes** y critícalas con la lista de [revisión visual](references/art-pass.md#revisión-visual): superficies grandes sin tratar, siluetas, punto de referencia visible desde el inicio, grupos en lugar de anillos o filas, contraste entre lo jugable y el fondo, densidad. Corrige y vuelve a generar hasta que la imagen cuente la intención. No muestra texturas, el detalle de los materiales ni sombras.

## 7. Verificar

```bash
python <skill-dir>/scripts/check_environment.py <Juego>
```

En Windows, usa `python` o `py -3` si `python3` no existe. El script revisa formato, colores, que la decoración no cambie el juego ni engañe, que el terreno no asome, caras superpuestas, superficies sin tratar, presupuesto de piezas y luces, y los assets del usuario. `check_game.py` del builder lo ejecuta cuando el GDD activa `design.environment`. Corrige todos los ERROR; cada WARN se corrige o se explica en `ENVIRONMENT.md`.

Después pide al usuario la prueba en Studio de la plantilla y capturas de cada nivel (vista general y desde el inicio, en PC y en el emulador de un teléfono). Cuando lleguen, revísalas con la misma lista que la vista previa y corrige: un script no ve si algo es lindo.

## Juegos con varios places

Cada place construye solo sus niveles (el `place` de cada nivel en `Levels.json`) y aplica solo su decoración, su terreno y su preset. El validador y la vista previa tratan cada place como un mundo aparte: el terreno o los props de un place no se comparan con piezas de otro, aunque compartan coordenadas.

## Juegos que ya existen

El pase de arte funciona sobre cualquier `Levels.json` y no toca la lógica. Si el juego aplica iluminación a mano (por ejemplo, en un servicio de mundo), lista en Pendientes que el builder la reemplace por `EnvironmentLoader.apply`. Si el mundo no está en `Levels.json`, el pase de arte necesita primero que el level designer lo pase a datos.

## Entrega

Resume: referencias y assets usados, intención de cada nivel, qué cambió en las superficies y piezas, decoración por nivel, resultado de `check_environment.py` con el presupuesto, las vistas previas generadas, pedidos abiertos (colores o presets al art director, geometría al level designer, integración y mapeo de assets al builder, permisos de assets al usuario) y qué mirar en Studio.
