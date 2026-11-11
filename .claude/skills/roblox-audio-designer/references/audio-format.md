# Formato de Audio.json

`src/shared/Audio.json` es la fuente de verdad del sonido del juego. Lo escribe el audio designer, lo lee `SoundBank` (en el cliente y el servidor) y lo revisa `check_audio.py`. El código del juego nunca guarda IDs de audio: nombra un **cue**.

Tres ideas:

- **Asset**: un audio concreto (un archivo, un ID de Roblox). Dice de dónde salió y con qué permiso se usa.
- **Cue**: un momento sonoro del juego ("suena el timbre", "se abre la tienda"). Apunta a un asset y decide volumen, bus, espacio y variación. Dos cues pueden usar el mismo asset con otro volumen o tono.
- **Bus**: un grupo de la mezcla (`sfx`, `ui`, `music`, `ambience`). Su volumen multiplica el de sus cues y el jugador puede ajustarlo.

```json
{
  "schema": 1,
  "buses": {
    "sfx": { "volume": 1 },
    "music": { "volume": 0.5 }
  },
  "assets": {
    "Doorbell": {
      "kind": "sfx",
      "id": "rbxassetid://1234567890",
      "file": "assets/audio/doorbell_toyphone.ogg",
      "durationSeconds": 1.42,
      "source": "generado con make_doorbell.py",
      "license": "propio"
    }
  },
  "cues": {
    "SpotDoorbell": {
      "asset": "Doorbell",
      "bus": "sfx",
      "volume": 0.9,
      "spatial": { "minDistance": 12, "maxDistance": 110 },
      "pitchVariance": 0.04,
      "cooldown": 0.3
    }
  }
}
```

(El ID del ejemplo es de relleno: nunca inventes uno; un asset sin subir lleva `"id": ""`.)

## `buses`

| Campo | Tipo | Regla |
| --- | --- | --- |
| clave | texto | Letra inicial, luego letras, números o `_` |
| `volume` | número | De 0 a 1 |

## `assets`

| Campo | Tipo | Regla |
| --- | --- | --- |
| clave | texto | Letra inicial, luego letras, números o `_` |
| `kind` | texto | `sfx` (efecto), `ui`, `music`, `ambience` o `voice` |
| `id` | texto | `rbxassetid://123`, o `""` mientras no esté subido (el cue no suena y `SoundBank` avisa una vez) |
| `source` | texto | De dónde salió: generado con un script, grabado, Creator Store (con el nombre del creador), etc. |
| `license` | texto | Con qué permiso se usa. Lo confirma el usuario; el skill lo registra, no lo verifica |
| `file` | texto, opcional | Ruta del archivo fuente respecto a la carpeta del juego (`assets/audio/…`). Si está, `check_audio.py` lo revisa contra los límites de Roblox |
| `durationSeconds` | número, opcional | Duración. `SoundBank` la usa para limpiar el sonido si nunca termina |

## `cues`

| Campo | Tipo | Regla |
| --- | --- | --- |
| clave | texto | Letra inicial, luego letras, números o `_`. Es lo que escribe el código: `SoundBank.play("SpotDoorbell")` |
| `asset` | texto | Un asset declarado |
| `bus` | texto | Un bus declarado |
| `volume` | número, opcional (1) | De 0 a 1 |
| `looped` | booleano, opcional | En bucle. La música casi siempre lo lleva |
| `spatial` | objeto, opcional | `minDistance` > 0 y `maxDistance` > `minDistance`, en studs. Sin `spatial`, el cue es 2D |
| `pitchVariance` | número, opcional (0) | De 0 a 0,5. Cambia la velocidad hasta ±esa fracción, para que un sonido repetido no suene idéntico |
| `cooldown` | número, opcional (0) | Segundos mínimos entre dos disparos del mismo cue |

## Qué es de quién

- **Este skill** (`Audio.json`): efectos de acciones y eventos, interfaz, música, voces y la mezcla.
- **roblox-environment-artist** (`Environment.json`, `sounds`): el ambiente fijo de un nivel o un punto del mapa. Si el mismo ID aparece en los dos, `check_audio.py` avisa: un audio, un dueño.
- **roblox-game-builder**: el código que dispara los cues y el RemoteEvent que avisa al cliente.
- **roblox-ui-designer**: decide qué botón o aviso lleva sonido; el audio designer define el cue.

## Cómo elegir valores

- **Efectos 3D**: `minDistance` es hasta dónde se oye a volumen pleno (el tamaño del objeto, de 8 a 15 studs); `maxDistance` es dónde deja de oírse. Los efectos espaciales deben ser **mono**: un archivo estéreo no se espacializa bien.
- **Volumen**: deja margen. Un cue base de 0,6 a 0,9 permite subir uno importante y evita que todo suene al máximo.
- **Variación**: de 0,03 a 0,08 para pasos, golpes y clics repetidos; 0 para un sonido de marca o una alerta que debe reconocerse.
- **Espera**: `cooldown` evita que 20 disparos en un frame se sumen en un chillido.
- **Música y ambiente**: con bucle, que el archivo empalme sin salto; si no empalma, el bucle se oirá como un corte.
