# Instalar SoundBank y disparar los cues

`assets/templates/src/shared/SoundBank.luau` es una plantilla: cópiala sin editarla a `src/shared/SoundBank.luau`. Lee `src/shared/Audio.json`, que Rojo convierte en un `ModuleScript` llamado `Audio` junto a ella. No hace falta tocar `default.project.json` si `src/shared` ya está mapeado a `ReplicatedStorage`.

## API

```lua
local SoundBank = require(ReplicatedStorage.Shared.SoundBank)

SoundBank.play("SpotDoorbell", { position = spot.Position })  -- cue espacial en un punto
SoundBank.play("SpotDoorbell", { parent = policeHead })        -- sigue a una pieza que se mueve
SoundBank.play("UiClick")                                      -- 2D
local music = SoundBank.play("MusicCity")                      -- en bucle: el Sound es tuyo
SoundBank.setBusVolume("music", 0.3)                           -- ajustes del jugador (0 a 1)
SoundBank.preload({ "SpotDoorbell", "UiClick" })               -- sin lista, precarga todo
```

- `play` devuelve el `Sound` o `nil` (cue desconocido, sin ID, o dentro del `cooldown`). Un cue sin ID **avisa una sola vez y no rompe nada**: el juego se puede construir antes de que el audio esté subido.
- Un sonido sin bucle se destruye solo al terminar (y por `Debris` si nunca termina, por ejemplo sin permiso). Uno **con bucle** lo detienes tú con `music:Destroy()`.
- Un cue espacial sin `position` ni `parent` suena sin posición y avisa una vez.

## Quién dispara qué

| Sonido | Dónde se llama |
| --- | --- |
| Interfaz (clics, avisos, premios) | Cliente, en el kit de UI |
| Respuesta a una acción del propio jugador | Cliente, apenas la inicia (no esperes al servidor para el sonido) |
| Efecto de un evento del servidor (un timbre, un policía) | El servidor avisa por un `RemoteEvent` con el cue y la posición; el cliente llama a `play` |
| Música y ambiente de un lugar | Cliente, al entrar; el servidor no |
| Ambiente compartido de un nivel | `Environment.json` del environment artist |

El servidor puede llamar a `play` solo para ambiente compartido: un `Sound` creado en el servidor se replica a todos y nace con retraso.

**El servidor decide cuándo y el cliente decide cómo suena.** El nombre del cue y la posición viajan por el remote; el ID, el volumen y el bus nunca.

## Los ajustes del jugador

Si el GDD promete controles de volumen, la UI llama a `SoundBank.setBusVolume(bus, valor)` y guarda el valor por jugador. Para guardarlo entre sesiones es un dato nuevo: pásalo por el [data architect](../../roblox-data-architect/SKILL.md) (una sección pequeña con un número por bus) y no uses un DataStore propio.

## Sound o AudioPlayer

Roblox recomienda hoy los objetos de audio nuevos (`AudioPlayer`, `AudioEmitter`, `AudioListener`, `AudioDeviceOutput` y `Wire`) y desaconseja `Sound`, `SoundGroup` y `SoundEffect`. La plantilla usa `Sound` porque funciona en todas partes y se prueba igual en Studio; cambiar a los objetos nuevos es reescribir `SoundBank.play` sin cambiar `Audio.json` ni las llamadas del juego. Si el juego ya usa un `Sound` suelto (un script que crea `Sound` con un ID leído de `Config`), migrarlo a un cue es parte del trabajo del skill: el ID pasa a `Audio.json` y la llamada pasa a `SoundBank.play`.

Lo que **no** se ha probado en Studio en esta plantilla: la mezcla real de los buses, el decaimiento 3D con auriculares y el comportamiento con muchos disparos a la vez. Dilo al entregar.

## Rendimiento

- Precarga los cues del inicio (`preload`) detrás de la pantalla de carga; no los de la zona 5.
- Sonidos cortos y mono. Una música de 3 minutos en `.ogg` ocupa del orden de 3 MB; no cargues más de una música a la vez.
- Los efectos que se repiten muchas veces por segundo (pasos, monedas) llevan `cooldown` y `pitchVariance`.
