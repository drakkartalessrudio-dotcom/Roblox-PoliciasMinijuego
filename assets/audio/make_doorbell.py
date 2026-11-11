"""
Genera doorbell_toyphone.wav: el timbre de un teléfono de juguete.

Un "tic" del botón y dos "trrring" electrónicos: una onda cuadrada que alterna dos
tonos (E6 y A6) unas 16 veces por segundo, como los teléfonos de plástico baratos.
No usa dependencias: solo la biblioteca estándar de Python.

    python assets/audio/make_doorbell.py

Después sube el .wav a Creator Hub (Assets > Audio) y pega el ID en
Config.SpotFx.DoorbellSoundId (src/shared/Config.luau).
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
LOW, HIGH = 1318.5, 1760.0  # E6 y A6
WARBLE_HZ = 16  # cuántas veces por segundo se alternan los tonos
RING_SECONDS = 0.55
GAP_SECONDS = 0.13
VOLUME = 0.42


def tone(seconds, freq_at, fade=0.008, volume=VOLUME):
    """Onda cuadrada con fase continua y entrada/salida cortas (sin chasquidos)."""
    count = int(seconds * RATE)
    phase = 0.0
    out = []
    for i in range(count):
        t = i / RATE
        phase += freq_at(t) / RATE
        sample = 1.0 if (phase % 1.0) < 0.5 else -1.0
        envelope = min(1.0, t / fade, (seconds - t) / fade)
        out.append(sample * envelope * volume)
    return out


def ring():
    return tone(RING_SECONDS, lambda t: HIGH if int(t * WARBLE_HZ * 2) % 2 else LOW)


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def soften(samples):
    """Promedio de 2 muestras: quita lo más áspero de la cuadrada sin volverla un pitido."""
    return [(samples[i] + samples[i - 1]) / 2 if i else samples[0] for i in range(len(samples))]


def main():
    click = tone(0.018, lambda t: 420.0, fade=0.002, volume=0.5)
    samples = click + silence(0.05) + ring() + silence(GAP_SECONDS) + ring() + silence(0.12)
    samples = soften(samples)
    path = Path(__file__).with_name("doorbell_toyphone.wav")
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print(f"{path} · {len(samples) / RATE:.2f} s")


if __name__ == "__main__":
    main()
