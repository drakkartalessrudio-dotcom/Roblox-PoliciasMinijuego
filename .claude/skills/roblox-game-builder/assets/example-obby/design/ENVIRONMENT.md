# Pase de arte de ObbyEjemplo

Fuente: `design/ART.md` y `src/shared/Theme.json` ("Noche volcánica"), `design/LEVELS.md` y `src/shared/Levels.json`. Datos: `src/shared/Environment.json`, aplicado por `EnvironmentLoader` después de construir los niveles. Verificado con `check_environment.py` el 13 de octubre de 2026: 0 errores, 0 advertencias.

## Referencias y assets del usuario

Ninguno: es el ejemplo de la fábrica y usa solo Parts, terreno y luces. En un juego real, aquí van las referencias del usuario y lo que se toma de cada una, y los assets que aportó con su origen y licencia.

## Intención

Un camino de piedra suspendido sobre un mar de lava, de noche. El jugador ve siempre dos cosas: dónde puede pisar (piedra con borde claro) y hacia dónde va (la meta celeste iluminada bajo un arco). Todo lo demás es fondo oscuro: agujas de basalto, rocas y volcanes de terreno que nacen de un suelo de basalto, lejos del alcance de los saltos.

## Reglas que se mantienen

- La geometría jugable es la de `Levels.json`: el pase de arte no mueve, agranda ni quita piezas, y conserva la física de cada material original.
- La lava, los checkpoints y las metas conservan los colores de su rol (`hazard`, `interactive` y `goal`).
- Nada de decoración en el aire de los saltos ni con colisión al alcance de un salto (9,7 studs con la física del juego) o en la caída hacia la lava.

## Superficies y piezas jugables

En un obby no hay muros ni pisos grandes: las superficies son las plataformas, y lo que más las mejora es el borde que marca el filo.

| Tipo | Aspecto | Adornos |
| --- | --- | --- |
| `platform` | `surface` (stone) en `Slate`, con variación de brillo de 6 % por pieza para que no parezcan copiadas | Borde `mist` en la cara de arriba para leer el filo del salto; roca `dusk` debajo, como piedra flotante |
| `spawn` y plataformas `entrada` | `surfaceAlt` (stoneLight) en `Basalt`: el punto de partida se distingue del resto | Borde y roca, como las plataformas |
| `checkpoint` | Color de rol (`sun`) en `SmoothPlastic` | Roca debajo |
| `goal` | Color de rol (`sky`) en `Neon` | Roca debajo |
| `hazard` | Color de rol (`lava`) en `Neon` | Ninguno |
| Plataformas móviles | `surfaceAlt` en `Basalt`, sin adornos (el loader no adorna lo que se mueve) | — |

## Decoración por nivel

| Nivel | Props | Terreno | Luces |
| --- | --- | --- | --- |
| `nivel-1` | 4 agujas y 2 grupos de rocas en la lava a más de 20 studs del camino; 1 cristal; farol al costado del checkpoint; arco detrás de la meta | Suelo de `Basalt` bajo los tres niveles, hasta y = -20 (7 studs por debajo de la lava), 2 volcanes (esferas de `Basalt` y `Rock`) y 1 cono de `Basalt` en el horizonte | Luz `goal` sobre la meta |
| `nivel-2` | 3 agujas, rocas y un cristal; farol del checkpoint; arco de la meta | 2 volcanes | Luz sobre la meta |
| `nivel-3` | 3 agujas, rocas y un cristal; farol del checkpoint (más alto: su punta no debe quedar a la altura de un salto desde `p3`); arco de la meta | 1 volcán y 1 cono | Luz sobre la meta |

Los faroles salen de la lava a 7 studs del eje del camino, fuera del aire del salto que llega al checkpoint y del que sale. Los arcos quedan detrás de la meta: enmarcan el final sin tapar el último salto.

## Iluminación y cielo

Preset `default` del tema (atardecer de las 19:36 con bloom). Nubes con cobertura 0,45 en `mist`. Colores del terreno: `Basalt` en `dusk` y `Rock` en `stone`. Las luces de los faroles usan `ember` y no proyectan sombra.

## Rendimiento

221 piezas en total (28 de los niveles, 108 de adornos y 85 de props) y 6 luces sin sombra, muy por debajo del presupuesto de la fábrica (3.000 piezas, 24 luces y 2 con sombra). Roblox no publica un presupuesto oficial; estos números son una referencia conservadora para celulares.

## Revisión visual

La vista previa (`preview_environment.py`) mostró que los volcanes flotaban en el vacío: fuera de la lava no había suelo. Se agregó el suelo de basalto, a más de 4 studs de la lava para que el terreno no asome a través de ella, y los volcanes ahora nacen de él.

## Verificación en Studio

1. Recorre los tres niveles: ningún adorno tapa la vista del salto siguiente y el borde claro marca dónde termina cada plataforma.
2. Cae a la lava desde cada tramo: nada te ataja en la caída.
3. Mira el juego en el emulador de un teléfono chico: la meta y los checkpoints se distinguen del fondo.
4. En el MicroProfiler (Ctrl+F6), el tiempo de render no sube de forma notable respecto del blockout.

## Pendientes

Ninguno.
