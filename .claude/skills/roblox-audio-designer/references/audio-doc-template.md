# Plantilla de design/AUDIO.md

Copia esta estructura a `design/AUDIO.md` del juego y complétala. Cada cue de `Audio.json` debe aparecer en la tabla de cues (lo revisa `check_audio.py`). Hay un ejemplo completo en `assets/example/design/AUDIO.md`.

```markdown
# Audio · <Juego>

## Intención sonora

<Dos o tres frases: cómo debe sonar el juego y por qué. Qué emoción refuerza cada familia de
sonidos. Qué NO debe pasar (nada que asuste en un juego para niños, nada que se vuelva
molesto tras mil repeticiones). Cada aviso importante tiene también texto o icono.>

## Mezcla

| Bus | Volumen | Qué lleva |
| --- | --- | --- |
| sfx | 1,0 | … |
| ui | 0,8 | … |
| music | 0,5 | … |

Prioridad cuando se pisan: <orden>. El jugador puede ajustar: <buses>.

## Cues

| Cue | Asset | Bus | Dónde suena | Quién lo dispara | Estado |
| --- | --- | --- | --- | --- | --- |
| `NombreDelCue` | NombreDelAsset | sfx | 2D / en un punto hasta N studs | Módulo o script y evento | Subido / Falta subir / Por elegir |

## Assets

| Asset | Origen | Licencia | ID | Notas |
| --- | --- | --- | --- | --- |
| NombreDelAsset | Generado / grabado / Creator Store (autor) | Propio / la del autor | rbxassetid://… o pendiente | Duración, formato, bucle |

## Lo que debe hacer el usuario

1. <Subir tal archivo y pegar el ID en Audio.json>
2. <Elegir tal sonido de la Creator Store y confirmar su licencia>
3. <Dar permiso a la experiencia>
4. <Escuchar cada cue en Studio, con auriculares y en el emulador de teléfono>

## Fuera de alcance

<Lo que se dejó para después: voces, música dinámica, ambiente por zona…>
```
