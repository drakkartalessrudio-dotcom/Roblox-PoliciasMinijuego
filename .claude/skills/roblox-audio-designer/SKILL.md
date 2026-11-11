---
name: roblox-audio-designer
description: Diseñar e integrar el sonido de juegos de Roblox. Define la intención sonora, la mezcla por buses (efectos, interfaz, música, ambiente) y los cues del juego en design/AUDIO.md y src/shared/Audio.json, prepara los archivos para subirlos (formatos, límites, conversión a .ogg, cuotas y permisos de la experiencia) y deja el módulo SoundBank que los reproduce con volumen, sonido 3D, variación de tono y espera. Un validador (check_audio.py) revisa los archivos contra los límites de Roblox, los cues contra el código y los IDs pendientes. Úsalo cuando el usuario quiera agregar o mejorar efectos de sonido, música, timbres o ambiente, cuando un audio no se sube o no suena en el juego (permisos, ID, formato), cuando haya IDs de audio escritos a mano en el código, o cuando el GDD prometa música, voces o ajustes de volumen. No compone audio con IA, no sube nada a Roblox (lo hace el usuario), no decide el ambiente fijo de un nivel (roblox-environment-artist) ni escribe la lógica del juego (roblox-game-builder).
metadata:
  version: "1.0.0"
  last_verified: "2026-11-11"
---

# Roblox Audio Designer

Convierte "que suene mejor" en un sistema: una intención sonora → una mezcla con buses → una lista de **cues** (momentos sonoros) → archivos preparados y subidos por el usuario → un solo módulo que los reproduce → un validador. El código del juego nunca guarda un ID de audio: dice `SoundBank.play("SpotDoorbell")` y `Audio.json` decide qué suena, cuánto y dónde.

## Qué produces y qué no

- `design/AUDIO.md` ([plantilla](references/audio-doc-template.md)): intención, mezcla, tabla de cues, assets y lo que debe hacer el usuario.
- `src/shared/Audio.json` ([formato](references/audio-format.md)): buses, assets y cues.
- `src/shared/SoundBank.luau`: copia sin editar de la [plantilla](assets/templates/src/shared/SoundBank.luau) ([cómo usarla](references/luau-side.md)).
- Archivos fuente en `assets/audio/` del juego, listos para subir (`.ogg` por defecto).
- **No subes nada a Roblox**: ni archivos, ni permisos, ni compras. Eso lo hace el usuario con tu lista ([guía](references/upload-and-permissions.md)). Tampoco abres la Creator Store ni eliges un ID que no hayas visto: nunca inventes un `rbxassetid://`.
- **No generas audio con IA ni lo compones.** Sí puedes sintetizar efectos simples con un script de la biblioteca estándar (como el timbre de juguete de este repositorio), y siempre dices que suena a síntesis básica.
- **No escribes la lógica del juego**: los puntos donde se dispara un cue los pone [roblox-game-builder](../roblox-game-builder/SKILL.md) (o tú, con una línea, si el cambio es solo agregar la llamada).

## Archivos del skill

```
SKILL_DIR = skills/roblox-audio-designer   (la carpeta donde esté instalado)
  SKILL.md                              este archivo ← léelo primero
  scripts/check_audio.py                validador del audio de un juego
  scripts/prepare_audio.py              inspect y convert (ffmpeg o soundfile)
  scripts/audioinfo.py                  lector de wav, ogg, flac y mp3 sin dependencias
  references/audio-format.md            formato de Audio.json y cómo elegir valores
  references/upload-and-permissions.md  límites, cuotas, moderación y permisos
  references/luau-side.md               SoundBank, quién dispara qué, Sound o AudioPlayer
  references/audio-doc-template.md      plantilla de design/AUDIO.md
  assets/templates/src/shared/SoundBank.luau
  assets/example/                       Audio.json, AUDIO.md y un .ogg de un juego real
```

Requisitos: Python 3.10 o superior para los scripts (sin dependencias). `prepare_audio.py convert` usa ffmpeg si está instalado o, si no, `soundfile` (`python -m pip install soundfile`). Opcional: luau-lsp para analizar la plantilla.

## Flujo

### 1 · Entender el juego y lo que ya suena ⏸

Lee el GDD (loop, tono, plataformas, público) y busca el audio existente: `assets/audio/`, `assets/ASSETS.md`, `Sound` y `SoundId` en `src/`, `sounds` en `Environment.json`. Haz como máximo una pregunta, solo si cambia el resultado: ¿tiene audios propios o hay que buscarlos?, ¿hay música? Si el usuario ya tiene archivos, esos mandan.

### 2 · Intención y mezcla

Escribe en `AUDIO.md` cómo debe sonar el juego y define los buses (casi siempre `sfx`, `ui`, `music`, `ambience`). Reglas de diseño que valen casi siempre:

- **El sonido confirma y avisa, no es la única señal.** Cada aviso importante tiene también texto o icono (hay jugadores sin sonido, en mute o con la pestaña en segundo plano). Un aviso solo auditivo es un error de accesibilidad.
- **Cuatro familias bastan:** acción del jugador (inmediato, corto, nítido), recompensa (sube de tono, más "cálido"), peligro o alerta (distinto de todo lo demás, no se mezcla con la música) y ambiente (continuo, bajo, nunca tapa lo anterior).
- **Lo que se repite se disimula:** variación de tono pequeña y espera mínima. Lo que se oye mil veces no puede ser largo ni agudo.
- **La música deja sitio:** volumen de bus bajo (0,3 a 0,5) y sin picos; el jugador debe poder bajarla sin bajar los efectos.
- **Móvil primero:** auriculares o altavoz pequeño; evita graves que solo se oyen en un buen equipo.

### 3 · Cues ⏸

Lista cada momento sonoro (acción → cue). Para cada uno decide: asset, bus, volumen, si es 3D (`spatial`), variación y espera. Esos valores son contenido de `Audio.json`; el código no los repite. Enséñale la tabla al usuario antes de buscar o preparar audio: es lo que más cambia con su opinión.

### 4 · Archivos

Para cada asset sin archivo, dile al usuario qué necesitas (duración, mono o estéreo, tono) y de dónde puede salir (grabado por él, Creator Store, un script de síntesis). Para cada archivo:

```bash
python scripts/prepare_audio.py inspect assets/audio/*
python scripts/prepare_audio.py convert assets/audio/timbre.wav --to ogg --mono
```

Un efecto 3D debe ser **mono**. Si un `.wav` fue rechazado por el importador, no supongas que el formato está prohibido (hoy Roblox acepta `.mp3`, `.ogg`, `.wav` y `.flac`): inspecciónalo y reescríbelo, como explica la [guía de subida](references/upload-and-permissions.md).

### 5 · Subir y dar permisos (lo hace el usuario) ⏸

Entrega una lista corta: qué archivo subir, por dónde (Asset Manager de Studio o Creator Hub), que espere la moderación, que dé permiso a la experiencia, y que pegue el ID en `Audio.json` (o te lo pase y lo pegas tú). El orden importa: **sin permiso, el ID no suena** y el error solo se ve en Output.

### 6 · Instalar y conectar

Copia `SoundBank.luau` a `src/shared/`, escribe `Audio.json`, y cambia cada `Sound` o `SoundId` a mano por una llamada a `SoundBank.play`: el ID sale del código y entra a `Audio.json`. Los cues espaciales se disparan en el cliente; el servidor manda el nombre del cue y la posición, nunca el ID ([reglas](references/luau-side.md)). Si ya hay un ajuste en `Config` para el ID (`SpotFx.DoorbellSoundId`), conviértelo: un solo lugar para los IDs.

### 7 · Validar

```bash
python scripts/check_audio.py <carpeta-del-juego>
```

Un **error** es un cue roto, un archivo fuera de los límites de Roblox o un ID mal escrito. Un **aviso** es algo pendiente (IDs sin subir, assets sin cue, IDs escritos a mano en el código) o dudoso; se corrige o se explica en `AUDIO.md`. El script no oye nada: no puede decir si el audio suena bien, si está en el volumen justo ni si la experiencia tiene permiso.

### 8 · Entregar

Cierra con: qué cues quedaron conectados, qué IDs faltan (la lista exacta), qué debe hacer el usuario (subir, permisos, escuchar en Studio con auriculares y en el emulador de teléfono) y qué **no probaste**: la mezcla real, el decaimiento 3D y el comportamiento con muchos disparos a la vez solo se comprueban en Studio.

## Reglas que no se negocian

1. **Ningún ID de audio en el código.** Viven en `Audio.json`; el código nombra cues.
2. **Nunca inventes ni adivines un ID.** Sin ID, `"id": ""` y el cue calla.
3. **Cada asset lleva `source` y `license`.** La licencia la confirma el usuario; tú la registras. No uses grabaciones de música, películas o juegos de terceros.
4. **El servidor no manda IDs ni volúmenes**: manda el nombre del cue. El cliente decide cómo suena.
5. **Ningún aviso importante depende solo del sonido.**
6. **Lo que no se escuchó en Studio se dice como no probado.**

## Con el resto de la fábrica

- [roblox-game-designer](../roblox-game-designer/SKILL.md): si el GDD promete música, voces o ajustes de volumen, ahí se declara (en "Assets y servicios" y en los criterios de aceptación) y el audio designer lo concreta. El skill no tiene flag propio en el frontmatter del GDD: se activa por el pedido y `factory_status.py` aún no lo recorre.
- [roblox-art-director](../roblox-art-director/SKILL.md): el tono sonoro acompaña el estilo visual (juguetón, sobrio, de terror); si hay `ART.md`, léelo antes de la intención sonora.
- [roblox-environment-artist](../roblox-environment-artist/SKILL.md): el ambiente fijo de un nivel y sus `sounds` son suyos. Tú das el cue de lo que cambia con el juego (una alarma, un timbre) y la mezcla general. Un mismo ID no vive en los dos archivos.
- [roblox-ui-designer](../roblox-ui-designer/SKILL.md): decide qué botón o aviso lleva sonido y cuál es su señal visual equivalente; tú defines el cue.
- [roblox-data-architect](../roblox-data-architect/SKILL.md): los ajustes de volumen del jugador que deben persistir son un dato nuevo y pasan por él.
- [roblox-game-builder](../roblox-game-builder/SKILL.md): conecta los disparos, el RemoteEvent de efectos y el mapeo de `src/shared`.
- [roblox-analytics-dev](../roblox-analytics-dev/SKILL.md): si hace falta medir si los jugadores apagan la música, es un evento de analíticas, no de este skill.

## Probar la instalación

```bash
python -m unittest tools.tests.test_check_audio -v     # desde la raíz del repositorio
python scripts/check_audio.py assets/example           # el ejemplo avisa de sus IDs pendientes y no da errores
```
