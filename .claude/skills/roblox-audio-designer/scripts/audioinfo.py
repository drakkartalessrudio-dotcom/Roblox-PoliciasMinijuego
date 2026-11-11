#!/usr/bin/env python3
"""Lee los datos técnicos de un archivo de audio sin dependencias externas.

Soporta .wav (módulo wave), .ogg Vorbis, .flac y .mp3. Devuelve la frecuencia de
muestreo, los canales y la duración, y los compara con los límites de Roblox
(documentación de Creator Hub, verificada el 11 de noviembre de 2026):

  - formatos: .mp3, .ogg, .wav y .flac, una sola pista;
  - menos de 20 MB y menos de 7 minutos;
  - frecuencia de muestreo de 48 kHz o menos;
  - mono o estéreo (también se admiten 3.0 y 5.1, que aquí se avisan).

La duración de un .mp3 es una estimación (tamaño / tasa de bits de la primera
trama); la del resto sale de la cabecera o del último bloque del archivo.
"""
from __future__ import annotations

import struct
import wave
from dataclasses import dataclass, field
from pathlib import Path

ALLOWED_EXTENSIONS = (".mp3", ".ogg", ".wav", ".flac")
MAX_BYTES = 20 * 1024 * 1024
MAX_SECONDS = 7 * 60
MAX_RATE = 48000

MP3_BITRATES = {
    # (versión MPEG, capa) -> tasas de bits en kbps por índice
    ("1", 3): [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
    ("1", 2): [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
    ("1", 1): [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
    ("2", 3): [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    ("2", 2): [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    ("2", 1): [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
}
MP3_RATES = {"1": [44100, 48000, 32000], "2": [22050, 24000, 16000], "2.5": [11025, 12000, 8000]}


@dataclass
class AudioInfo:
    path: str
    extension: str
    size_bytes: int
    sample_rate: int | None = None
    channels: int | None = None
    duration: float | None = None
    estimated: bool = False
    readable: bool = True
    notes: list[str] = field(default_factory=list)


def _read_wav(info: AudioInfo, path: Path) -> None:
    try:
        with wave.open(str(path), "rb") as handle:
            info.sample_rate = handle.getframerate()
            info.channels = handle.getnchannels()
            frames = handle.getnframes()
            info.duration = frames / info.sample_rate if info.sample_rate else None
    except (wave.Error, EOFError) as error:
        # wave solo lee PCM; un .wav de coma flotante o de 24 bits entra aquí.
        info.readable = False
        info.notes.append(f"no se pudo leer la cabecera del .wav ({error}); conviértelo con prepare_audio.py")


def _read_ogg(info: AudioInfo, path: Path) -> None:
    data = path.read_bytes()
    marker = data.find(b"\x01vorbis")
    if marker < 0:
        if data.find(b"OpusHead") >= 0:
            info.notes.append("es Opus dentro de Ogg: Roblox documenta Vorbis; conviértelo a .ogg Vorbis")
        info.readable = False
        info.notes.append("no se encontró la cabecera Vorbis")
        return
    channels = data[marker + 11]
    rate = struct.unpack("<I", data[marker + 12 : marker + 16])[0]
    info.channels = channels
    info.sample_rate = rate
    last = data.rfind(b"OggS")
    if last >= 0 and rate:
        granule = struct.unpack("<q", data[last + 6 : last + 14])[0]
        if granule > 0:
            info.duration = granule / rate


def _read_flac(info: AudioInfo, path: Path) -> None:
    head = path.read_bytes()[:64]
    if head[:4] != b"fLaC" or len(head) < 26:
        info.readable = False
        info.notes.append("cabecera FLAC no válida")
        return
    # STREAMINFO empieza en el byte 8 del archivo; los datos útiles, 10 bytes después.
    packed = int.from_bytes(head[18:26], "big")
    rate = (packed >> 44) & 0xFFFFF
    channels = ((packed >> 41) & 0x7) + 1
    total = packed & 0xFFFFFFFFF
    info.sample_rate = rate
    info.channels = channels
    if rate and total:
        info.duration = total / rate


def _read_mp3(info: AudioInfo, path: Path) -> None:
    data = path.read_bytes()
    offset = 0
    if data[:3] == b"ID3" and len(data) >= 10:
        size = (data[6] << 21) | (data[7] << 14) | (data[8] << 7) | data[9]
        offset = 10 + size
    limit = min(len(data) - 4, offset + 65536)
    for index in range(offset, limit):
        if data[index] != 0xFF or (data[index + 1] & 0xE0) != 0xE0:
            continue
        header = data[index : index + 4]
        version_bits = (header[1] >> 3) & 0x3
        layer_bits = (header[1] >> 1) & 0x3
        bitrate_index = (header[2] >> 4) & 0xF
        rate_index = (header[2] >> 2) & 0x3
        if version_bits == 1 or layer_bits == 0 or bitrate_index in (0, 15) or rate_index == 3:
            continue
        version = {3: "1", 2: "2", 0: "2.5"}[version_bits]
        layer = {3: 1, 2: 2, 1: 3}[layer_bits]
        table = MP3_BITRATES.get(("1" if version == "1" else "2", layer))
        if table is None:
            continue
        bitrate = table[bitrate_index] * 1000
        info.sample_rate = MP3_RATES[version][rate_index]
        info.channels = 1 if (header[3] >> 6) == 3 else 2
        info.duration = (len(data) - index) * 8 / bitrate
        info.estimated = True
        return
    info.readable = False
    info.notes.append("no se encontró ninguna trama MP3")


def read_audio(path: Path) -> AudioInfo:
    extension = path.suffix.lower()
    info = AudioInfo(path=str(path), extension=extension, size_bytes=path.stat().st_size)
    try:
        if extension == ".wav":
            _read_wav(info, path)
        elif extension == ".ogg":
            _read_ogg(info, path)
        elif extension == ".flac":
            _read_flac(info, path)
        elif extension == ".mp3":
            _read_mp3(info, path)
        else:
            info.readable = False
            info.notes.append(f"extensión {extension or '(ninguna)'} no admitida")
    except (OSError, struct.error, IndexError) as error:
        info.readable = False
        info.notes.append(f"no se pudo leer: {error}")
    return info


def problems(info: AudioInfo) -> tuple[list[str], list[str]]:
    """Devuelve (errores, avisos) contra los límites de Roblox."""
    errors: list[str] = []
    warnings: list[str] = []
    if info.extension not in ALLOWED_EXTENSIONS:
        errors.append(f"formato {info.extension or '(sin extensión)'} no admitido (usa .ogg, .mp3, .wav o .flac)")
    if info.size_bytes >= MAX_BYTES:
        errors.append(f"pesa {info.size_bytes / 1048576:.1f} MB y el límite es menos de 20 MB")
    if info.sample_rate and info.sample_rate > MAX_RATE:
        errors.append(f"frecuencia de {info.sample_rate} Hz: el límite es 48000 Hz o menos")
    if info.channels and info.channels > 2:
        warnings.append(f"{info.channels} canales: Roblox admite mono, estéreo, 3.0 y 5.1, pero un efecto de juego debería ser mono o estéreo")
    if info.duration is not None and info.duration >= MAX_SECONDS:
        errors.append(f"dura {info.duration:.0f} s y el límite es menos de 7 minutos")
    for note in info.notes:
        warnings.append(note)
    return errors, warnings


def describe(info: AudioInfo) -> str:
    parts = [Path(info.path).name, f"{info.size_bytes / 1024:.1f} KB"]
    if info.sample_rate:
        parts.append(f"{info.sample_rate} Hz")
    if info.channels:
        parts.append({1: "mono", 2: "estéreo"}.get(info.channels, f"{info.channels} canales"))
    if info.duration is not None:
        parts.append(f"{info.duration:.2f} s" + (" (estimada)" if info.estimated else ""))
    return " · ".join(parts)
