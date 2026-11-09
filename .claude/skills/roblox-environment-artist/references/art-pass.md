# Guía del pase de arte

Cómo convertir un nivel de blockout en un lugar sin perder lo que lo hace jugable. Orden de trabajo: referencias, lectura, superficies, punto de referencia, fondo, detalle, luz y revisión visual.

## 1. Referencias

Si el usuario dejó imágenes en `assets/reference/` o las adjuntó, míralas antes de decidir y anota qué tomas de cada una: la paleta (que traduces a los nombres del tema, sin hexadecimales), los materiales, la densidad de detalle, la escala de los props, la luz y cómo enmarcan el objetivo. Toma el estilo, no el diseño: nada de logos, personajes ni edificios reconocibles de otro juego. Si la referencia pide colores o presets que el tema no tiene, pídeselos al art director.

## 2. Lectura antes que belleza

El jugador decide en menos de un segundo dónde pisar. Antes de agregar nada:

- **Lo pisable se ve pisable:** superficies con color de `surface`, distintas del fondo y con un borde (`trim`) que marca el filo. El borde importa más que cualquier adorno en un obby.
- **Lo que mata se ve peligroso y nada más se le parece:** el peligro conserva su color y brillo; la decoración no usa ese color ni uno que se confunda con él.
- **Lo importante brilla:** la meta y los checkpoints conservan su rol y reciben una luz o un marco (arco, faroles). La vista va hacia lo que tiene más contraste y luz.

## 3. Superficies primero

Los muros y pisos grandes ocupan la mayor parte de la pantalla. Si quedan lisos, el nivel sigue viéndose como blockout aunque tenga cien props alrededor.

| Superficie | Qué hacer | Adornos |
| --- | --- | --- |
| Piso de arena o plaza | Material con textura (`CeramicTiles`, `Cobblestone`, `Concrete`, `Pavement`, `WoodPlanks`, `Carpet`) o una textura del usuario; `variation` baja | `border` a 2 a 4 studs del muro, `grid` de 8 o 16 studs, `checker` en zonas que deben destacar |
| Muro perimetral | Material de pared (`Plaster`, `Brick`, `Concrete`, `WoodPlanks`); un color algo más oscuro que el piso | `baseboard` y `cornice` siempre; `pilasters` cada 12 a 20 studs en muros largos; `band` para un acento de color |
| Tabique o cobertura | El mismo material que el muro o uno del juego (`cover`) | `trim` arriba; `baseboard` si es alto |
| Plataforma de obby | `surface` con `variation` | `trim` y `rock` o `pillar` |
| Pieza que toca el suelo | — | `base` para que no flote sobre el terreno |

Si el estilo pide plástico (juguete, caricatura), se puede conservar `SmoothPlastic`, pero con adornos de superficie y colores por zona. Una superficie grande que siga lisa necesita una razón escrita en `ENVIRONMENT.md`.

## 4. Terreno y suelo

- Roblox arma el terreno con vóxeles de 4 × 4 × 4 studs y redondea sus bordes: un relleno que termina a 1 o 2 studs de un piso asoma a través de él como manchas. Deja 4 studs o más entre el terreno y cualquier pieza, con los bordes en múltiplos de 4 (por ejemplo, el suelo hasta y = -8 si el piso empieza en y = -1).
- El hueco que queda entre el terreno y un piso o un muro se tapa con `base` (cimiento) de la profundidad del hueco.
- Un suelo de terreno bajo todo el mundo evita el vacío alrededor: colinas, rocas o volcanes que nacen de él, en lugar de esferas que flotan.

## 5. Un punto de referencia por nivel

Una silueta grande, visible desde el inicio, que diga hacia dónde ir: un arco detrás de la meta, una aguja, una fuente, una torre. Va lejos del alcance o detrás del final, nunca en el aire de un salto. Cambia de forma entre niveles para que el jugador sienta que avanza.

## 6. Capas de distancia

| Capa | Dónde | Qué va | Densidad |
| --- | --- | --- | --- |
| Juego | Las piezas del nivel y su alcance | El aspecto de las piezas y sus adornos; props chicos sin colisión que no parezcan escalones | Baja |
| Cerca | Justo fuera del alcance (el validador dice cuánto es) | Bancos, maceteros, faroles, puestos, rocas, árboles: lo que da escala y textura | Media |
| Lejos | Decenas de studs más allá | Terreno grande, fachadas, casas, siluetas, nubes | Pocas piezas, grandes |

La densidad baja con la distancia: mucho detalle lejos cuesta piezas y no se ve; poco detalle cerca se ve vacío. Fuera de una arena, el lugar se cuenta con fachadas y casas, no con un anillo de árboles iguales.

## 7. Formas, grupos y escala

- Los props de la biblioteca son bloques y esferas con un giro: el estilo es low-poly. Varía tamaño (±25 %) y giro de cada copia (`scatter.py` lo hace).
- Agrupa de a tres o cinco con tamaños distintos, alrededor de algo (una fuente, un puesto, una esquina); las filas regulares y los anillos parejos delatan que alguien los puso.
- Usa la escala del personaje (unos 5 studs) como referencia: un banco de 6 studs de largo, un farol de 10 a 20, un árbol de 12 a 18, una casa de 12 o más.
- Los modelos del usuario son el detalle más fuerte: úsalos en los lugares que más se miran (cerca del inicio, alrededor del objetivo) y los prefabs para el resto.

## 8. Color y material

- La paleta es del art director. Las superficies grandes van apagadas y los acentos son pocos.
- Material con intención: `Slate` o `Basalt` para piedra, `WoodPlanks` para madera trabajada, `Neon` solo para lo que brilla de verdad (peligro, meta, faroles). El exceso de `Neon` aplana la escena y cansa en celulares.
- `variation` entre 0,04 y 0,08 rompe la repetición sin cambiar la lectura.

## 9. Luz y ambiente

- El preset del tema fija la hora y la atmósfera; elige uno por nivel según la intención (más oscuro o más cerrado cuando sube la dificultad). Si la luz es plana (sol alto, ambiente muy claro, sin sombras), pide al art director un preset con más contraste.
- Las luces locales señalan: meta, checkpoints, entradas. Alcance corto (12 a 20 studs), brillo moderado (1 a 2) y sin sombras.
- Las nubes y el color del terreno terminan el fondo: un cielo vacío se ve sin terminar. Un sonido de ambiente del usuario (pájaros, viento, gente) suma más que muchos props.

## 10. Rendimiento

Roblox no publica un número máximo de piezas o luces. Sí recomienda menos luces, alcance corto, sin sombras donde no hacen falta, sin sombra en piezas chicas y evitar transparencias superpuestas ([mejorar el rendimiento](https://create.roblox.com/docs/performance-optimization/improve)). El loader apaga la sombra de las piezas de decoración de menos de 4 studs. El presupuesto de la fábrica (3.000 piezas, 24 luces, 2 con sombra) es una referencia conservadora para celulares: mide en Studio con el MicroProfiler antes de subirlo. Las baldosas (`checker`) y las juntas (`grid`) suman piezas rápido: usa baldosas grandes.

## Revisión visual

Usa esta lista con las imágenes de `preview_environment.py` y con las capturas de Studio que mande el usuario. Para cada nivel, anota en `ENVIRONMENT.md` qué cambiaste por cada punto que falló.

1. **Superficies:** ¿queda algún muro o piso grande liso, del mismo color de punta a punta?
2. **Lectura:** desde la vista del jugador, ¿se distingue qué se pisa, qué mata y dónde está el objetivo?
3. **Punto de referencia:** ¿se ve desde el inicio y dice hacia dónde ir?
4. **Fondo:** ¿hay un horizonte con siluetas, o vacío y objetos flotando?
5. **Grupos:** ¿los props forman grupos con intención, o anillos y filas parejas?
6. **Escala:** ¿los props tienen el tamaño que tendrían junto a un personaje de 5 studs?
7. **Color:** ¿las superficies grandes están apagadas y los acentos son pocos? ¿Se parece a las referencias del usuario?
8. **Defectos:** en las capturas, ¿hay manchas en pisos (terreno o caras superpuestas), objetos que atraviesan piezas o huecos bajo los muros?

## Por género

| Género | Énfasis |
| --- | --- |
| Obby lineal | Bordes, roca o pilares debajo de las plataformas, faroles en checkpoints, arco en la meta, suelo de terreno lejano y fondo de siluetas |
| Arena o rondas | Piso con material y guarda, muros con zócalo, cornisa y pilastras; nada sólido adentro que cambie por dónde se corre o por dónde persiguen los enemigos; el lugar se cuenta afuera de las paredes con fachadas, casas y terreno |
| Hub o lobby | Más detalle cerca (es donde el jugador se queda), una fuente o un punto de referencia en el centro, carteles y luces hacia las salidas |
| Interior | Muros con zócalo y cornisa, piso de madera o alfombra con guarda, luces de techo cálidas, nada que tape la vista a la altura de la cabeza |
| Tycoon o parcelas | Cada parcela con el mismo marco; la decoración va entre parcelas, no adentro |
