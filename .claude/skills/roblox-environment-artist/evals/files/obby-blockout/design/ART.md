# Dirección de arte de ObbyEjemplo

Fuente: `GDD.md` (concepto y pilares). Tokens: `src/shared/Theme.json` ("Noche volcánica"). Verificado con `check_art.py` el 2026-10-12: 0 errores.

## Intención visual

Un volcán al anochecer: el cielo se apaga en rosa y violeta, la piedra es oscura y fría, y todo lo importante para jugar brilla. El jugador lee el recorrido de un vistazo porque solo lo jugable tiene luz y color saturado.

Pilares visuales:

1. **Lo que importa brilla.** Peligros, checkpoints y metas son las únicas superficies saturadas o emisivas. El fondo y la piedra son apagados.
2. **El peligro nunca se confunde.** La lava es naranja rojizo y de `Neon`; ningún elemento seguro usa ese color ni ese material.
3. **Calma entre picos.** Iluminación cálida y suave, sin destellos que tapen los saltos.

## Paleta

| Color | Hex | Rol | Uso |
| --- | --- | --- | --- |
| `night` | #141826 | background, textOnAccent | Cielo profundo, texto sobre botones de acento |
| `dusk` | #262C40 | panel | Fondo de paneles de UI |
| `stone` | #4E5668 | surface | Plataformas de piedra |
| `stoneLight` | #7B8496 | surfaceAlt | Bordes y plataformas secundarias |
| `lava` | #FF5A1F | hazard | Lava, franjas y barras peligrosas |
| `ember` | #FFB020 | accent | Botón principal, resaltados |
| `sun` | #FFE066 | interactive | Checkpoints |
| `sky` | #2EC4F1 | goal | Metas de nivel |
| `violet` | #B794F6 | reward | Recompensas y coleccionables |
| `mint` | #4ADE80 | success | Mensajes de éxito |
| `coral` | #FF6B8A | danger | Avisos de error en la UI |
| `snow` | #F5F7FA | text | Texto principal |
| `mist` | #B8C0CC | textMuted | Texto secundario |

El amarillo de los checkpoints es `#FFE066` y no un amarillo más oscuro: con deuteranopia, `#FFD54F` se confunde con la lava (ΔE 22,8, debajo del mínimo de 25).

## Materiales

| Rol | Material | Por qué |
| --- | --- | --- |
| surface | Slate | Piedra volcánica con textura que no compite con el color |
| surfaceAlt | Basalt | Variación para bordes sin cambiar la paleta |
| hazard | Neon | La lava emite luz: se distingue aunque el color no se perciba |
| interactive | SmoothPlastic | Checkpoint limpio y plano, se lee como "seguro" |
| goal | Neon | La meta se ve desde lejos |
| decoration | Rock | Rocas de fondo, siempre más oscuras que el recorrido |

## Iluminación

Preset `default`: atardecer (hora 19,6), estilo `Soft` con prioridad de calidad. Ambiente violeta apagado, luz cálida desde arriba, atmósfera rosada con algo de bruma para separar el fondo del recorrido, bloom moderado para que la lava y las metas brillen sin encandilar.

## Tipografía

| Uso | Fuente | Peso |
| --- | --- | --- |
| Títulos y mensajes grandes | FredokaOne | Bold |
| Texto de interfaz | BuilderSans | Regular |
| Etiquetas y botones | BuilderSans | SemiBold |
| Números (nivel, checkpoint) | BuilderSans | Bold |

## Estilo de interfaz

Paneles `dusk` con 12 % de transparencia, esquinas de 10 px, borde de 2 px en `stoneLight` para separar del fondo, espaciado base de 8 px. Botones táctiles de 44 px como mínimo. El texto nunca se apoya directo sobre el mundo 3D: siempre sobre un panel o con contorno.

## Reglas de legibilidad

- Contraste de texto 4,5:1 y de elementos de UI 3:1 (cumplido, ver `check_art.py`).
- Peligro, checkpoint, meta y recompensa se distinguen entre sí y de la piedra también con protanopia, deuteranopia y tritanopia.
- El color nunca es la única señal: la lava además es `Neon`, y checkpoints y metas tienen forma y tamaño propios.

## Para los demás skills

- **Level designer y environment artist:** colores y materiales por rol de esta tabla; nada seguro en `lava` ni en `Neon` naranja.
- **UI designer y builder:** colores, fuentes y medidas solo desde `Theme.json` (con `Style`).
