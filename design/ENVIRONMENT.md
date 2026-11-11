# Pase de arte de TravesurasBrainrot

Fuente: `design/ART.md` y `src/shared/Theme.json` ("Caramelo Brainrot"), `design/LEVELS.md` y `src/shared/Levels.json`. Datos: `src/shared/Environment.json`. Verificado con `check_environment.py` el 29 de octubre de 2026 (resultado al final).

## Referencias y assets del usuario

**Imágenes y assets:** ninguno. El usuario no dejó imágenes en `assets/reference/` ni modelos, texturas, sonidos o animaciones; en su lugar dio **referencias de lugar por escrito** para tres distritos y dejó las demás a mi elección. No se bajó ni se inventó ningún asset: todo está armado con Parts, prefabs de la fábrica y prefabs nuevos de este juego.

Qué se toma de cada referencia (estilo, nunca marcas, logos ni edificios reconocibles):

| Distrito | Referencia | Qué se toma |
| --- | --- | --- |
| Centro Neón | Times Square (Nueva York), elegida por el usuario | Cañón de rascacielos oscuros a ambos lados de una avenida, pantallas gigantes apiladas a dos alturas, mucho color luminoso contra fachadas oscuras, y una bola luminosa sobre el edificio más alto |
| Playa Podrida | Playa de Los Ángeles con rueda de la fortuna en el muelle, elegida por el usuario | Arena abierta, rueda de la fortuna como silueta lejana, torres de salvavidas, sombrillas, palmeras y kioscos de madera de colores |
| Colegio Brainrot | Escuela japonesa, elegida por el usuario | Edificio blanco con franja de color y torre de reloj, patio de concreto, portal torii a la entrada, cerezos en flor, máquinas expendedoras en la vereda |
| Barrio Papa | Barrio residencial de dibujos animados (elección mía) | Casitas bajas de colores pastel con zócalo y cornisa, faroles, bancos y árboles; un monumento gigante a la papa como punto de referencia |
| Distrito Queso | Barrio financiero de torres de vidrio (elección mía) | Torres altas claras con franjas naranja de queso, un banco con columnas y un queso gigante sobre su techo |
| Puerto Podrido | Terminal de contenedores (elección mía) | Pilas de contenedores de colores, grúa naranja, faroles y cajas; el mar al este |

Si más adelante el usuario aporta imágenes o modelos, se suman sin rehacer el pase (los prefabs se pueden reemplazar por modelos con `asset`).

## Intención

- **Barrio Papa:** una tarde soleada de barrio de juguete. La vista va a la papa gigante sobre el edificio central, visible desde el spawn.
- **Colegio:** recreo luminoso. El torii y el reloj enmarcan el patio; los cerezos marcan las calles.
- **Playa:** mediodía de verano. La rueda de la fortuna (80 × 92 studs) se ve desde todo el distrito y guía hacia el fondo de la arena.
- **Centro Neón:** noche de neón. Cada fachada tiene dos pantallas con color distinto; la bola luminosa corona la torre más alta.
- **Distrito Queso:** hora dorada de oficinas. El queso gigante sobre el banco es el punto de referencia.
- **Puerto Podrido:** atardecer nublado, contenedores de colores y la grúa; mar a un lado.

## Reglas que se mantienen

- La geometría de `Levels.json` no cambia: posiciones, tamaños, colisión y transparencia quedan como las diseñó el level designer. Los muros invisibles de límite no se tocan.
- Los colores de juego (`interactive` amarillo, `goal` cian, `reward` violeta, `hazard` rojo sirena) **no se usan en la decoración**. El naranja de los cosméticos y del queso es el `accent` del tema.
- La decoración no tiene colisión (los policías y los jugadores la atraviesan): en una ciudad abierta nada sólido debe estorbar la persecución ni al pathfinding.
- Sin terreno de Roblox: el mundo es de piezas llanas y el mar es un prop sin colisión detrás del muro de límite.

## Superficies y piezas jugables

| Tipo | Aspecto | Adornos |
| --- | --- | --- |
| `platform` (calles, aceras, arena, paseo) | Material del nivel (asfalto, concreto, arena, madera) con `variation` 0,04 | Ninguno: son superficies de juego grandes y llanas |
| `prop` (edificios, kioscos, contenedores) | Barrio y Colegio `Plaster`; Playa `WoodPlanks`; Centro y Queso `Concrete`; Puerto `Metal`; colores por edificio de `mist`, `snow`, `skyBlue`, `orange`, `curb`, `grape`, `grapeLight`, `ink` | `baseboard` (zócalo) y `cornice` (cornisa) en todos, `band` de color (en el Centro, de material `Neon`), `pilasters` en el colegio y en el banco |

La calle sigue siendo asfalto liso de `Levels.json`: se lee como superficie de juego frente a fachadas con color y relieve; la textura de calle llega con una variante de material del usuario.

## Decoración por nivel

| Nivel | Props | Terreno | Luces |
| --- | --- | --- | --- |
| `lobby` | 30: 16 árboles detrás de las parcelas, 6 faroles (uno por portal) y 8 bancas alrededor de la plaza | — | 7: una por portal (color del distrito) y una sobre la plaza |
| `barrio-papa` | 19: papa monumental, árboles, faroles, bancos y maceteros | — | 2 (Guaridas) + faroles |
| `colegio` | 24: torre del reloj, torii, cerezos, máquinas expendedoras, bancos, cercas | — | 2 (Guaridas) |
| `playa-podrida` | 31: rueda de la fortuna, 2 torres de salvavidas, palmeras, 14 sombrillas, faroles, mar | — | 3 (Guaridas) + faroles |
| `centro-neon` | 35: 16 pantallas luminosas, bola de confeti | — | 3 (Guaridas) + pantallas |
| `distrito-queso` | 7: queso gigante, faroles | — | 3 (Guaridas) + faroles |
| `puerto-podrido` | 10: cajas, faroles, mar | — | 2 (Guaridas) + faroles |

## Puntos de travesura (graffiti y timbre)

Los puntos de `Levels.json` son zonas invisibles; el jugador no sabía dónde pintar ni dónde tocar. Los viste `Game/SpotProps.luau` al arrancar (no son datos de `Environment.json`), con Parts y los colores del tema, y marcados con el color de rol `interactive` (amarillo neón) como el resto de lo que se toca:

- **Graffiti y Mural Gigante:** muro de dos caras con un lienzo **a medio pintar** (manchas, goteras, esquinas de neón), latas de aerosol, charcos y un cartel "PINTA AQUÍ" / "MURAL EN BANDA" visible desde 120 studs. Al completarlo estalla pintura y aparece el mural terminado hasta que pasa el enfriamiento del punto.
- **Timbrazo:** fachada de casa (puerta, toldo, ventanas, macetas, felpudo) con el timbre justo en el punto del prompt y un cartel "TOCA EL TIMBRE". Al tocarlo el botón se hunde y parpadea, se encienden las ventanas unos segundos y suena un timbre de teléfono de juguete 3D (`SpotFeedback.client.luau`).
- Todo es decoración sin colisión ni consulta de rayos: no cambia la visión de los policías, el ruido, las guardias ni las rutas. Unas 1.500 piezas más en todo el mapa; el muro del tutorial (`tutorial_graffiti`) ahora es un graffiti normal.
- **Sonido:** `assets/audio/doorbell_toyphone.wav` (se regenera con `make_doorbell.py`) se sube a Creator Hub y su ID va en `Config.SpotFx.DoorbellSoundId`. Mientras esté vacío el timbre se ve pero no suena.

## Iluminación y cielo

Preset `default` del tema para todo el mapa, con nubes de cobertura 0,45. **Roblox aplica una sola iluminación a todos los jugadores**, así que los presets `playa`, `neon`, `queso`, `puerto` y `sala` del tema no se pueden usar por distrito desde el servidor. Cada distrito cuenta su clima con color y luz propia (neón en el Centro, tonos cálidos en Queso) y la iluminación por distrito queda como pedido de interfaz (ver Pendientes).

## Rendimiento

`check_environment.py`: 1.349 piezas (niveles, adornos y props) de 9.000 de presupuesto y 65 luces de 90, ninguna con sombra. Las luces vienen de las pantallas del Centro (una por pantalla, alcance 28), las Guaridas y los faroles. En celular conviene medir; si hace falta, se quitan las luces de las pantallas altas.

## Revisión visual

Pendiente del usuario: capturas de cada distrito en Studio (vista general y desde el inicio), en PC y en el emulador de un teléfono. No se generó la vista previa de `preview_environment.py`.

## Advertencias que quedan (explicadas)

- **Bancos, máquinas expendedoras, cajas y el mar "parecen pisables":** son decoración sin colisión en una ciudad llana; nadie debe poder subirse a ellos y nada sólido hay cerca. Si se quiere que bloqueen el paso, se pide al level designer.
- **Árboles, palmeras, cerezos y torres de salvavidas** usan verde y rosa, que el validador marca como parecidos al rojo sirena con ciertas visiones de color. Se mantienen por ser vegetación y detalles pequeños; ninguno es rojo ni tiene luz roja, y los policías llevan luz de sirena y etiqueta.
- **`paseo` y los `spawn` de la Playa comparten plano:** es geometría del nivel (ver Pendientes).
- **Partes de prefab fuera de la caja** en `sakura`, `billboard` y `relojTorre`: se pasan por pocos studs a propósito (copas, pantalla y cara del reloj).

## Pendientes

- environment-artist → level-designer: el `paseo` de la Playa y los `spawn` comparten la cara de arriba (y = 1,00): separar al menos 0,05 studs (abierto)
- environment-artist → art-director: pedir a futuro un color rosa de cerezo y un verde que no se confundan con el rojo sirena en protanopia/deuteranopia (abierto)
- environment-artist → ui-designer: aplicar en el cliente el preset de iluminación de cada distrito según el atributo `District` (abierto)
- environment-artist → builder: ya llama a `EnvironmentLoader.apply` en `Bootstrap` y no aplica `Style.applyLighting` (cerrado)
- environment-artist → usuario: aportar imágenes en `assets/reference/` o modelos en `assets/models/` si quiere reemplazar los prefabs (abierto)
