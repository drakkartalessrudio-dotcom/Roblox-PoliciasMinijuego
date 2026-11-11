# Audio · Travesuras

## Intención sonora

Un barrio de día con un humor de dibujo animado: los efectos son cortos, agudos y de juguete, y la música no compite con ellos. El sonido confirma lo que el jugador hizo y avisa de lo que viene (el timbre se oye a la distancia del policía), pero ningún aviso depende solo del oído: cada uno tiene su texto o su icono.

## Mezcla

| Bus | Volumen | Qué lleva |
| --- | --- | --- |
| sfx | 1,0 | Efectos de las travesuras, a veces en un punto del mapa |
| ui | 0,8 | Clics, avisos y premios de la interfaz |
| music | 0,5 | Música de fondo, en bucle |
| ambience | 0,7 | Ambiente de un lugar |

Prioridad cuando se pisan: ui > sfx > ambience > music. El jugador puede bajar `music` y `sfx` por separado (`SoundBank.setBusVolume`).

## Cues

| Cue | Asset | Bus | Dónde suena | Quién lo dispara | Estado |
| --- | --- | --- | --- | --- | --- |
| `SpotDoorbell` | Doorbell | sfx | En el timbre, hasta 110 studs | `SpotFeedback` (cliente), a pedido del servidor | Archivo listo; falta subirlo |
| `UiClick` | UiClick | ui | 2D | Botones del kit de UI | Por elegir |
| `MusicCity` | CityLoop | music | 2D, en bucle | Cliente al entrar al barrio | Por elegir |

## Lo que debe hacer el usuario

1. Subir `assets/audio/doorbell_toyphone.ogg` (Asset Manager de Studio o Creator Hub > Audio) y pegar el ID en `Audio.json`, en `assets.Doorbell.id`.
2. Elegir un clic y una música de la Creator Store (o subir los propios) y confirmar su licencia.
3. Esperar la moderación y dar permiso a la experiencia (Audio > Configure > Permissions > Experiences). Un permiso a una experiencia no se puede revocar.
4. Escuchar cada cue en Studio, con auriculares y en el emulador de teléfono.
