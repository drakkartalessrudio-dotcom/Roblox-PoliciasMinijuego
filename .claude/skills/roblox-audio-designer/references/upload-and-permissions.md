# Subir audio a Roblox: límites, formatos y permisos

Verificado contra la documentación de Creator Hub el 11 de noviembre de 2026 ([Audio assets](https://create.roblox.com/docs/audio/assets)). Los límites cambian: si una subida falla por algo que esta guía no menciona, lee esa página primero.

## Límites del archivo

| Qué | Límite documentado |
| --- | --- |
| Formatos | `.mp3`, `.ogg`, `.wav` y `.flac`, una sola pista |
| Peso | Menos de 20 MB |
| Duración | Menos de 7 minutos |
| Frecuencia de muestreo | 48 kHz o menos |
| Canales | Mono, o estéreo 2.0, 3.0 y 5.1 |

`prepare_audio.py inspect <archivo>` comprueba todo esto sin dependencias.

Un efecto corto pesa poco en cualquier formato, pero **`.ogg` (Vorbis) es la opción por defecto del skill**: 1,4 s de timbre pesaron 122 KB en `.wav` y 17 KB en `.ogg`, y evita las cabeceras raras. Para música usa `.ogg` o `.mp3`. `.flac` solo si importa la calidad sin pérdida.

## Si el importador rechaza el archivo

Studio **transcodifica** el audio al importarlo. Un error casi siempre significa que lo rechazó la transcodificación, no que el formato esté vetado:

1. Corre `prepare_audio.py inspect`. Un `.wav` de coma flotante o de 24 bits, o con una cabecera escrita por una herramienta vieja, es el sospechoso habitual.
2. Reescríbelo: `prepare_audio.py convert <archivo> --to ogg` (usa ffmpeg si está; si no, `soundfile`).
3. Si sigue fallando, mira el mensaje exacto en Studio (Output) y en Creator Hub; un nombre con caracteres raros, una cuenta sin verificar con la cuota agotada o un contenido que moderación no acepta dan errores distintos.

## Cuotas

Sin verificación de identidad, **100** audios gratis cada 30 días; con ella, **2 000**. Cada subida cuenta, incluidas las que se rechazan después, así que no subas pruebas sueltas: prepara y revisa el lote antes.

## Cómo se sube (lo hace el usuario)

Nunca subas, compres ni cambies permisos por tu cuenta.

- **Studio, Asset Manager:** botón *Import*, elegir los archivos y esperar la marca verde. Al importar así, la experiencia abierta recibe permiso de uso.
- **Creator Hub:** *Development Items > Audio > Upload Asset*; nombre, descripción y archivo.
- **Open Cloud:** `POST https://apis.roblox.com/assets/v1/assets` con `assetType: "Audio"`; sirve para lotes grandes.

Después de subir, el audio pasa por **moderación**; mientras tanto solo lo ve su dueño. Roblox lo clasifica solo como *efecto de sonido* o *canción*. Las canciones tienen más condiciones (verificación de identidad, términos de audio). El skill pide efectos cortos y música con licencia clara.

Hay que tener los **derechos** del audio y respetar las normas de la comunidad. Para música o efectos de otros, usa la Creator Store y anota autor y licencia en `source` y `license`; no uses grabaciones de canciones, juegos ni películas.

## Permisos: lo que más falla

Un ID de audio **no concede acceso**. El audio es privado por defecto, y la experiencia necesita permiso para reproducirlo; sin él, Studio muestra un error en Output y en el juego no suena nada.

- Al importar con Asset Manager o insertarlo desde el inventario, la experiencia abierta recibe permiso automáticamente.
- Un audio subido por Creator Hub, o con otra cuenta, o dentro de un modelo, necesita permiso explícito: *Audio > Configure > Permissions > Experiences > Add experiences* (con el universe ID). Para varios a la vez: la página del juego, *Configurations > Permissions*.
- Si el equipo comparte audios, el dueño debe dar permiso a cada colaborador (amigo o miembro del grupo).
- **Los permisos a una experiencia son permanentes**: no se pueden revocar.
- Una experiencia sin publicar no tiene universe ID: publícala antes de dar permisos.
- Si pasas el juego a otra experiencia (copia, otro place de prueba), repite los permisos: cruzar un place no los copia.

## IDs

Roblox muestra el ID como un número. En `Audio.json` va como `rbxassetid://` + ese número. No inventes IDs ni pegues uno que no hayas visto en Creator Hub: un ID inventado puede apuntar al audio de otra persona o a nada.
