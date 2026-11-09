---
name: roblox-art-director
description: Dirigir el arte de juegos de Roblox. Define el estilo visual en design/ART.md (intención, paleta con roles, materiales, iluminación por ambiente, tipografía, estilo de interfaz y reglas de legibilidad) y lo traduce a Theme.json, los tokens que usan la UI, la decoración y el builder; valida contrastes, legibilidad de juego y daltonismo con un script. Úsalo cuando el usuario quiera definir o cambiar cómo se ve su juego, su paleta de colores, sus fuentes o su ambiente, cuando el GDD active design.art, o cuando el juego se vea genérico, poco legible o inconsistente. No coloca piezas en los niveles (roblox-level-designer y roblox-environment-artist) ni diseña pantallas (roblox-ui-designer).
metadata:
  version: "1.1.0"
  last_verified: "2026-10-12"
---

# Roblox Art Director

Decide cómo se ve el juego y lo deja escrito en dos formas: un documento que explica las decisiones (`ART.md`) y un archivo de tokens que el código usa directamente (`Theme.json`). Así la UI, los niveles y la decoración hablan el mismo idioma visual, y un cambio de paleta se hace en un solo lugar.

La dirección de arte no es decoración: decide qué ve primero el jugador. Si la lava y el checkpoint tienen colores parecidos, o el texto de la tienda no se lee en un celular, el juego es peor aunque se vea "lindo".

## Qué produces y qué no

- Lees del `GDD.md`: fantasía, pilares, público, plataformas y género.
- Escribes, según el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md):
  - `design/ART.md`, con la [plantilla](references/art-bible-template.md);
  - `src/shared/Theme.json`, con el [formato del tema](references/theme-format.md). Rojo lo convierte en el ModuleScript `Shared.Theme`, y el código lo lee con `Style` (plantilla del builder).
- No colocas piezas ni cambias niveles, no diseñas pantallas ni su distribución, y no escribes código. Si un nivel o una pantalla contradice el estilo, déjalo como pedido con la regla de pendientes del contrato.
- Si el usuario pidió definir el estilo y el frontmatter tiene `design.art: false` o no lo tiene, actívalo y regístralo.
- En un clon de otro juego, toma el **tipo** de estilo (por ejemplo "caricatura brillante") pero no su identidad: ni logo, ni personajes, ni paleta firma, ni assets del original.

## 1. Intención visual

Escribe en pocas frases qué debe sentir el jugador al ver el juego y qué ve primero. Define hasta tres **pilares visuales**: reglas que deciden conflictos ("lo que importa brilla", "nada seguro usa rojo"). Busca referencias del usuario en `<Juego>/assets/reference/` (o adjuntas en el chat); si no hay ninguna y el pedido es definir el estilo desde cero, pregunta una vez si tiene capturas de juegos o lugares cuyo estilo le guste. Míralas y describe con palabras qué tomas de cada una (paleta, contraste, materiales, luz): no copies arte con derechos ni la identidad de otro juego.

Ten en cuenta el público y las plataformas del GDD: en celulares los elementos se ven chicos y con brillo variable, así que el contraste y el tamaño importan más que el detalle.

## 2. Paleta con roles

Elige pocos colores con nombre y asígnales **roles**. El código nunca pide "naranja": pide `hazard`. Roles obligatorios: `background`, `surface`, `hazard`, `interactive`, `goal`, `reward`, `panel`, `text`, `textMuted`, `textOnAccent`, `accent`, `danger` y `success` (detalles en el [formato](references/theme-format.md)).

- Los colores de juego (peligro, interactivo, meta, recompensa) son los más saturados o luminosos; el fondo y las superficies, más apagados. El ojo va primero a lo jugable.
- El color del peligro es exclusivo: nada seguro lo usa.
- **El color nunca es la única señal.** Material, forma, brillo o animación también distinguen lo peligroso (por ejemplo, la lava en `Neon`).
- Lee [legibilidad](references/readability.md) antes de cerrar la paleta.

## 3. Materiales, iluminación y tipografía

- **Materiales por rol** (`surface`, `hazard`, `decoration`…), con valores de `Enum.Material`.
- **Iluminación:**
  - Elige `LightingStyle` (`Soft` o `Realistic`) y `PrioritizeLightingQuality`. Roblox no deja cambiarlos por script: van en `default.project.json`, y el builder los copia del tema.
  - Define presets con nombre (`default` y los que pida cada nivel o modo). Cada preset usa `atmosphere` o `fog` para la distancia de visión, no ambos.
  - Usa postprocesado moderado (`colorCorrection`, `bloom`, `sunRays`). Un bloom fuerte tapa los saltos.
- **Tipografía:**
  - Usa valores de `Enum.Font`: BuilderSans para la interfaz y una fuente con carácter para títulos, como FredokaOne o LuckiestGuy. Gotham y Arial están obsoletas.
  - Define pesos por uso: título, cuerpo, etiqueta y número.
- **Estilo de UI:** radio de esquinas, grosor de borde, espaciado, transparencia de paneles, tamaño mínimo táctil (44 px o más) y rango de tamaño de texto. Son los tokens que usa el UI designer.

## 4. Validar

```bash
python <skill-dir>/scripts/check_art.py <Juego>
```

Para revisar solo un tema, usa `--theme <ruta/Theme.json>`. En Windows, usa `python` o `py -3` si `python3` no existe. El script comprueba:

- el formato del tema;
- el contraste de texto (4,5:1) y de elementos de UI (3:1);
- que peligro, interactivo, meta, recompensa y superficie se distingan entre sí en visión normal y con protanopia, deuteranopia y tritanopia simuladas (ΔE de 25 o más);
- que `ART.md` nombre cada color de la paleta.

`check_game.py` del builder lo ejecuta también cuando el GDD activa `design.art`.

Corrige todos los ERROR ajustando luminosidad o tono, sin cambiar la intención. Si bajas un umbral en `validation`, explica por qué en `ART.md`. Los colores se ven distintos bajo cada iluminación: pide al usuario una captura en Studio con el preset aplicado antes de dar el estilo por cerrado.

## 5. Documentar

Completa `ART.md`:

- intención y pilares;
- tabla de paleta (color, hex, rol y uso);
- materiales con su porqué, presets de iluminación, tipografía y estilo de UI;
- reglas de legibilidad con el resultado del validador;
- una sección **Para los demás skills** que diga qué debe respetar cada uno.

## Juegos que ya existen

Antes de proponer, busca en el código los colores y las fuentes escritos a mano (`Color3.fromRGB`, `Color3.fromHex`, `Enum.Font`) y en `Levels.json` los colores de las piezas: son la paleta de hecho. Conserva lo que funciona, corrige lo que no se lee y lista en Pendientes los archivos que deben pasar a usar `Style`. Esos archivos son del builder o del UI designer.

## Entrega

Resume en pocas líneas: intención y pilares, paleta y roles críticos, resultado de `check_art.py`, ajustes que quedan para el proyecto (`LightingStyle`) y pedidos abiertos para niveles, UI o builder.
