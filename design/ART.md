# Dirección de arte de TravesurasBrainrot

Fuente: `GDD.md` (concepto y pilares). Tokens: `src/shared/Theme.json` ("Caramelo Brainrot"). Verificado con `check_art.py` el 26 de octubre de 2026: sin errores (ver Reglas de legibilidad).

## Intención visual

Una ciudad de dibujos animados a plena luz del día, colorida, redonda y absurda: el jugador debe sentir que está en una travesura inofensiva, no en un juego de crimen. Todo lo que se puede hacer (puntos de travesura, Guarida, botín) brilla sobre un asfalto apagado; todo lo que persigue (policías, sirenas, estrellas de búsqueda) es rojo-sirena y **solo** eso es rojo-sirena.

Referencia de tipo de estilo (sin copiar identidad): caricatura brillante y exagerada, formas gordas de plástico, humor *brainrot* con criaturas ridículas (papa con gorra, tiburón con zapatillas). No se usa ningún personaje ni paleta firma de otro juego.

Pilares visuales:

1. **Lo que puedes hacer brilla.** Puntos de travesura (amarillo), Guarida y depósito (cian) y botín/Cerebros (violeta) son los colores más luminosos del mapa, con material `Neon` o brillo; el mundo es más apagado.
2. **El rojo-sirena es solo de la policía.** Policías, luces de patrulla, foco del helicóptero y el medidor de calor usan `hazard`; nada seguro lo usa (ni carteles, ni cosméticos).
3. **Se lee a 60 studs/s.** La velocidad llega a 60 studs/s: siluetas grandes, pocos colores por objeto, calles anchas sin ruido y contraste alto en los puntos de interacción, en celular y con visión de color reducida.

## Paleta

| Color | Hex | Rol | Uso |
| --- | --- | --- | --- |
| `skyBlue` | `#7CC8FF` | `background` | Cielo y fondo lejano |
| `asphalt` | `#4A4E69` | `surface` | Calles, suelos jugables y paredes neutras |
| `curb` | `#9A9FB8` | `surfaceAlt` | Aceras, bordes, muros secundarios y concreto |
| `siren` | `#FF2D4F` | `hazard` | Policías, luces de sirena, medidor de calor y estrellas de búsqueda |
| `sunny` | `#FFD60A` | `interactive` | Puntos de travesura, esconderse, herramientas recogibles |
| `cyan` | `#19D3F3` | `goal` | Guarida, Sala de Entrenamiento, depósito y Pay'n'Spray |
| `violet` | `#B97CFF` | `reward` | Botín, Dinero, Cerebros, monedas del suelo |
| `grape` | `#2B2250` | `panel` | Paneles de UI |
| `grapeLight` | `#3B2F6B` | `panelAlt` | Paneles secundarios y filas |
| `snow` | `#F8F5FF` | `text` | Texto principal |
| `mist` | `#C9C2E8` | `textMuted` | Texto secundario |
| `ink` | `#1A1233` | `textOnAccent` | Texto sobre botones de acción |
| `orange` | `#FF9F1C` | `accent` | Botón de acción principal de la UI |
| `coral` | `#FF6B8A` | `danger` | Errores y avisos en la UI |
| `mint` | `#4ADE80` | `success` | Confirmaciones y depósito completado |

Las estrellas de búsqueda se dibujan en `hazard` con la forma de estrella (la forma, no solo el color, las distingue de las estrellas de recompensa, que son violeta y con otro marco).

## Materiales

| Rol | Material | Por qué |
| --- | --- | --- |
| `surface` | `Asphalt` | Calle creíble y neutra que deja destacar lo jugable |
| `surfaceAlt` | `Concrete` | Aceras y muros de apoyo, claramente distintos de la calle |
| `hazard` | `Neon` | La policía emite luz: se ve a la distancia y de noche |
| `interactive` | `Neon` | Los puntos de travesura brillan y se distinguen del fondo sin depender del color |
| `goal` | `Neon` | La Guarida y los depósitos se ven desde lejos |
| `decoration` | `SmoothPlastic` | Aspecto de juguete en carteles, mobiliario y fachadas |

## Iluminación

Estilo `Soft` con `PrioritizeLightingQuality` activo. `Lighting.LightingStyle` y `PrioritizeLightingQuality` no se cambian por script: van en `default.project.json` y el builder los copia del tema. Un preset por clima; el pase de arte elige cuál usa cada distrito:

| Preset | Dónde | Intención |
| --- | --- | --- |
| `default` | Barrio Papa y Colegio | Tarde soleada (15:12), cielo azul claro, colores saturados y sombras suaves |
| `playa` | Playa Podrida | Mediodía muy brillante (13:12), más luz y haze ligero |
| `neon` | Centro Neón | Atardecer morado (20:24) donde el bloom hace brillar los carteles |
| `queso` | Distrito Queso | Hora dorada (17:24), cálida, con rayos de sol |
| `puerto` | Puerto Podrido | Atardecer nublado (18:36), más neblina para dar tensión al jefe |
| `sala` | Sala de Entrenamiento | Interior claro y estable, sin efectos fuertes |

Cada preset usa `atmosphere` (sin niebla). El postprocesado es moderado (bloom ≤ 0,9, sin tapar los puntos de interacción).

## Tipografía

| Uso | Fuente | Peso |
| --- | --- | --- |
| Título (`heading`) | LuckiestGuy | Regular |
| Cuerpo (`body`) | BuilderSans | Regular |
| Etiqueta y botones (`label`) | BuilderSans | SemiBold |
| Números y marcadores (`number`) | FredokaOne | Bold |

LuckiestGuy tiene un único peso: se usa para títulos y avisos grandes ("¡ESTRELLA!", "ARRESTADO"). Los números del HUD (Dinero, Botín, nivel) usan FredokaOne para leerse rápido en movimiento.

## Estilo de interfaz

Paneles `grape` con transparencia 0,1, esquinas de 14 px y borde de 3 px (`accent` para lo seleccionado, `grapeLight` en reposo). Espaciado de 8 px y tamaño táctil mínimo de **48 px**; texto entre 14 y 36 px. Los avisos sobre el mundo (nombre de la banda, "?" y "!" de detección) son `BillboardGui` con texto `snow` sobre fondo `grape`, nunca sobre el cielo.

## Reglas de legibilidad

- **Texto:** `text`/`panel` 13,47:1, `textMuted`/`panel` 8,54:1, `textOnAccent`/`accent` 8,68:1 (mínimo 4,5:1).
- **UI:** `accent`/`panel` 7,07:1, `danger`/`panel` 5,34:1, `success`/`panel` 8,33:1 (mínimo 3:1).
- **Distinción de juego** (ΔE ≥ 25 incluso con protanopia, deuteranopia y tritanopia simuladas): peligro, interactivo, meta, recompensa y superficie son distinguibles entre sí. El par más justo es `hazard`/`surface` con 34,2 (protanopia).
- **El color nunca es la única señal:** la policía se distingue además por silueta y luz de sirena; los puntos de travesura, por brillo `Neon` y un ícono flotante; la Guarida, por su forma y pulso; las estrellas, por forma.
- **A revisar en Studio con el preset aplicado:** el contraste de `hazard` sobre `Asphalt` en `neon` y `puerto` (cuanto más oscuro el preset, más hay que subir el brillo del `Neon`) y la legibilidad del cian de la Guarida sobre la arena de la Playa.

## Para los demás skills

- **Level designer y environment artist:** los colores y materiales salen de los roles, no de nombres: suelo `surface`/`Asphalt`, aceras `surfaceAlt`/`Concrete`, puntos de travesura `interactive`/`Neon`, Guarida y depósitos `goal`/`Neon`, botín `reward`. `hazard` solo para policías y sus luces; nunca en Guaridas, escondites ni decoración. La arena de la Playa y el césped del Colegio son colores de ambiente propios del pase de arte, siempre más apagados que los puntos jugables. Cada distrito usa el preset de la tabla.
- **UI designer y builder:** tokens de `Theme.json` mediante `Style`; nada de colores ni fuentes escritos en el código. Estrellas de búsqueda en `hazard` con forma de estrella; Dinero y Cerebros en `reward`; botones de acción en `accent` con `textOnAccent`; los reto del check-in de la Sala usan íconos grandes (≥ 64 px) con contorno `text`.

## Pendientes

- art-director → builder: copiar `Style` y aplicar `lighting.style = Soft` y `prioritizeQuality = true` en `default.project.json` (abierto)
- art-director → environment-artist: elegir el preset por distrito según la tabla de iluminación (abierto)
- art-director → ui-designer: usar `LuckiestGuy` solo en títulos y avisos grandes y `FredokaOne` para los números del HUD (abierto)
