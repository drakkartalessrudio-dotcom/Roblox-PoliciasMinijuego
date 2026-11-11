#!/usr/bin/env python3
"""Prepara un audio para subirlo a Roblox.

Uso:
    python prepare_audio.py inspect <archivo> [<archivo> ...]
    python prepare_audio.py convert <archivo> [--to ogg|mp3|flac|wav] [--mono] [--out <archivo>]

inspect  muestra formato, frecuencia, canales, duración y peso, y dice si cumple los
         límites de Roblox (.mp3, .ogg, .wav o .flac; menos de 20 MB y 7 minutos; 48 kHz o menos).
convert  reescribe el audio en un archivo limpio. Un .wav con cabecera rara, de 24 bits o
         de coma flotante es la causa más común de que el importador lo rechace; pasarlo a
         .ogg lo resuelve. Usa ffmpeg si está instalado; si no, la librería soundfile
         (python -m pip install soundfile), que no cambia la frecuencia de muestreo.

No sube nada a Roblox: la subida la hace el usuario (Asset Manager o Creator Hub).
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audioinfo  # noqa: E402

FORMATS = {
    "ogg": ["-c:a", "libvorbis", "-q:a", "5"],
    "mp3": ["-c:a", "libmp3lame", "-q:a", "2"],
    "flac": ["-c:a", "flac"],
    "wav": ["-c:a", "pcm_s16le"],
}


def inspect(paths: list[Path]) -> int:
    status = 0
    for path in paths:
        if not path.is_file():
            print(f"ERROR  {path}: no existe")
            status = 1
            continue
        info = audioinfo.read_audio(path)
        errors, warnings = audioinfo.problems(info)
        print(audioinfo.describe(info))
        for message in errors:
            print(f"  ERROR  {message}")
            status = 1
        for message in warnings:
            print(f"  AVISO  {message}")
        if not errors and info.readable:
            print("  cumple los límites documentados de Roblox")
    return status


def convert_ffmpeg(ffmpeg: str, source: Path, target: Path, fmt: str, mono: bool, info: audioinfo.AudioInfo) -> bool:
    command = [ffmpeg, "-y", "-loglevel", "error", "-i", str(source), "-map_metadata", "-1", "-vn"]
    if mono or (info.channels and info.channels > 2):
        command += ["-ac", "1" if mono else "2"]
    if info.sample_rate and info.sample_rate > audioinfo.MAX_RATE:
        command += ["-ar", str(audioinfo.MAX_RATE)]
    command += FORMATS[fmt] + [str(target)]
    return subprocess.run(command).returncode == 0


def convert_soundfile(source: Path, target: Path, fmt: str, mono: bool) -> bool:
    try:
        import soundfile
    except ImportError:
        print("ERROR  no hay ffmpeg ni soundfile. Instala uno: winget install Gyan.FFmpeg, o python -m pip install soundfile")
        return False
    data, rate = soundfile.read(str(source))
    if rate > audioinfo.MAX_RATE:
        print(f"ERROR  el audio es de {rate} Hz y soundfile no remuestrea; instala ffmpeg")
        return False
    if data.ndim > 1:
        if mono or data.shape[1] > 2:
            data = data.mean(axis=1)
    subtypes = {"ogg": ("OGG", "VORBIS"), "flac": ("FLAC", "PCM_16"), "wav": ("WAV", "PCM_16"), "mp3": ("MP3", None)}
    container, subtype = subtypes[fmt]
    soundfile.write(str(target), data, rate, format=container, subtype=subtype)
    return True


def convert(source: Path, fmt: str, mono: bool, out: Path | None) -> int:
    if not source.is_file():
        print(f"ERROR  {source}: no existe")
        return 1
    target = out or source.with_suffix(f".{fmt}")
    if target.resolve() == source.resolve():
        print("ERROR  el destino es el mismo archivo; usa --to u --out distintos")
        return 1
    info = audioinfo.read_audio(source)
    ffmpeg = shutil.which("ffmpeg")
    ok = convert_ffmpeg(ffmpeg, source, target, fmt, mono, info) if ffmpeg else convert_soundfile(source, target, fmt, mono)
    if not ok:
        return 1
    print(f"Escrito {target}")
    return inspect([target])


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # igual en la consola de Windows
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p_inspect = sub.add_parser("inspect")
    p_inspect.add_argument("files", nargs="+", type=Path)
    p_convert = sub.add_parser("convert")
    p_convert.add_argument("file", type=Path)
    p_convert.add_argument("--to", choices=sorted(FORMATS), default="ogg")
    p_convert.add_argument("--mono", action="store_true", help="mezclar a mono (los efectos 3D deben ser mono)")
    p_convert.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.command == "inspect":
        return inspect(args.files)
    return convert(args.file, args.to, args.mono, args.out)


if __name__ == "__main__":
    sys.exit(main())
