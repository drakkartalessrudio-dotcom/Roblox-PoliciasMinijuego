#!/usr/bin/env python3
"""Revisa el audio de un juego de la fábrica.

Uso:
    python check_audio.py <carpeta-del-juego>
    python check_audio.py <carpeta-del-juego> --json

Comprueba:
  - src/shared/Audio.json: formato (schema 1), buses, assets y cues con sus
    referencias cruzadas (cada cue apunta a un asset y a un bus que existen);
  - cada asset: tipo, origen y licencia, ID con la forma rbxassetid://123 (o vacío
    mientras esté pendiente de subir) y, si declara un archivo, que exista y cumpla
    los límites de Roblox (formato, menos de 20 MB, menos de 7 minutos, 48 kHz o menos);
  - cada cue: volumen, alcance 3D, variación de tono y espera coherentes;
  - el código: que ningún .luau use un cue que no existe (SoundBank.play("X")) y que no
    haya IDs rbxassetid:// escritos a mano fuera de Audio.json;
  - design/AUDIO.md: existe y menciona cada cue; el GDD menciona cada ID subido.
Avisa de los assets con ID pendiente, de assets sin cue y de IDs repetidos en
Environment.json (el audio de ambiente por nivel es de roblox-environment-artist).

No puede oír el audio ni comprobar que la experiencia tenga permiso para usarlo:
eso se prueba en Studio y en Creator Hub. Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audioinfo  # noqa: E402

ASSET_KINDS = {"sfx", "ui", "music", "ambience", "voice"}
KEY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
ID_RE = re.compile(r"^rbxassetid://\d+$")
ID_ANYWHERE_RE = re.compile(r"rbxassetid://\d+")
PLAY_RE = re.compile(r"SoundBank[.:]play\(\s*[\"']([^\"']+)[\"']")
LONG_SFX_SECONDS = 30


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")

    def note(self, message: str) -> None:
        self.notes.append(message)


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def check_buses(data: dict, result: Result) -> dict:
    buses = data.get("buses")
    if not isinstance(buses, dict) or not buses:
        result.error("buses", "falta el objeto buses con al menos un bus (por ejemplo sfx)")
        return {}
    for name, bus in buses.items():
        where = f"buses.{name}"
        if not KEY_RE.match(name):
            result.error(where, "el nombre debe empezar con letra y usar solo letras, números y _")
        volume = bus.get("volume") if isinstance(bus, dict) else None
        if not is_number(volume) or not 0 <= volume <= 1:
            result.error(where, "volume debe ser un número entre 0 y 1")
    return buses


def check_asset_file(name: str, asset: dict, game: Path, result: Result) -> None:
    where = f"assets.{name}"
    file_value = asset.get("file")
    if file_value is None:
        return
    if not isinstance(file_value, str) or not file_value.strip():
        result.error(where, "file debe ser una ruta relativa a la carpeta del juego")
        return
    path = game / file_value
    if not path.is_file():
        result.error(where, f"el archivo {file_value} no existe")
        return
    info = audioinfo.read_audio(path)
    errors, warnings = audioinfo.problems(info)
    for message in errors:
        result.error(where, f"{file_value}: {message}")
    for message in warnings:
        result.warn(where, f"{file_value}: {message}")
    declared = asset.get("durationSeconds")
    if info.duration is not None and is_number(declared) and not info.estimated and abs(declared - info.duration) > 0.25:
        result.warn(where, f"durationSeconds declara {declared} s y el archivo dura {info.duration:.2f} s")
    if info.duration is not None and asset.get("kind") in {"sfx", "ui"} and info.duration > LONG_SFX_SECONDS:
        result.warn(where, f"un {asset['kind']} de {info.duration:.0f} s es largo: ¿es música o ambiente?")


def check_assets(data: dict, game: Path, result: Result) -> dict:
    assets = data.get("assets")
    if not isinstance(assets, dict):
        result.error("assets", "falta el objeto assets")
        return {}
    seen_ids: dict[str, str] = {}
    for name, asset in assets.items():
        where = f"assets.{name}"
        if not KEY_RE.match(name):
            result.error(where, "el nombre debe empezar con letra y usar solo letras, números y _")
        if not isinstance(asset, dict):
            result.error(where, "debe ser un objeto")
            continue
        if asset.get("kind") not in ASSET_KINDS:
            result.error(where, f"kind debe ser uno de {sorted(ASSET_KINDS)}")
        for key in ("source", "license"):
            if not isinstance(asset.get(key), str) or not asset[key].strip():
                result.error(where, f"falta {key} (de dónde salió el audio y con qué permiso se usa)")
        asset_id = asset.get("id", "")
        if not isinstance(asset_id, str):
            result.error(where, "id debe ser texto: rbxassetid://123, o vacío si falta subirlo")
        elif asset_id == "":
            result.warn(where, "id vacío: el audio está pendiente de subir a Creator Hub (el juego no sonará)")
        elif not ID_RE.match(asset_id):
            result.error(where, f"id {asset_id!r} no tiene la forma rbxassetid://123")
        else:
            if asset_id in seen_ids:
                result.warn(where, f"comparte el id {asset_id} con assets.{seen_ids[asset_id]}")
            seen_ids[asset_id] = name
        check_asset_file(name, asset, game, result)
    return assets


def check_cues(data: dict, assets: dict, buses: dict, result: Result) -> dict:
    cues = data.get("cues")
    if not isinstance(cues, dict) or not cues:
        result.error("cues", "falta el objeto cues con al menos un cue")
        return {}
    used_assets: set[str] = set()
    for name, cue in cues.items():
        where = f"cues.{name}"
        if not KEY_RE.match(name):
            result.error(where, "el nombre debe empezar con letra y usar solo letras, números y _")
        if not isinstance(cue, dict):
            result.error(where, "debe ser un objeto")
            continue
        asset = cue.get("asset")
        if asset not in assets:
            result.error(where, f"asset {asset!r} no está declarado en assets")
        else:
            used_assets.add(asset)
        bus = cue.get("bus")
        if bus not in buses:
            result.error(where, f"bus {bus!r} no está declarado en buses")
        volume = cue.get("volume", 1)
        if not is_number(volume) or not 0 <= volume <= 1:
            result.error(where, "volume debe ser un número entre 0 y 1")
        pitch = cue.get("pitchVariance", 0)
        if not is_number(pitch) or not 0 <= pitch <= 0.5:
            result.error(where, "pitchVariance debe ser un número entre 0 y 0.5")
        cooldown = cue.get("cooldown", 0)
        if not is_number(cooldown) or cooldown < 0:
            result.error(where, "cooldown debe ser un número mayor o igual que 0")
        if "looped" in cue and not isinstance(cue["looped"], bool):
            result.error(where, "looped debe ser true o false")
        spatial = cue.get("spatial")
        if spatial is not None:
            lo = spatial.get("minDistance") if isinstance(spatial, dict) else None
            hi = spatial.get("maxDistance") if isinstance(spatial, dict) else None
            if not is_number(lo) or not is_number(hi) or lo <= 0 or hi <= lo:
                result.error(where, "spatial pide minDistance > 0 y maxDistance mayor que minDistance (en studs)")
            elif hi > 500:
                result.warn(where, f"maxDistance de {hi} studs: más de 500 casi no se atenúa; ¿es ambiente sin posición?")
            if asset in assets and assets[asset].get("kind") in {"music", "ui"}:
                result.warn(where, f"un {assets[asset]['kind']} no suele ser espacial")
        if asset in assets and assets[asset].get("kind") == "music" and cue.get("looped") is not True:
            result.warn(where, "la música casi siempre va en bucle (looped: true)")
    for name in assets:
        if name not in used_assets:
            result.warn(f"assets.{name}", "ningún cue lo usa")
    return cues


def luau_files(game: Path) -> list[Path]:
    src = game / "src"
    if not src.is_dir():
        return []
    return sorted(src.rglob("*.luau")) + sorted(src.rglob("*.lua"))


def check_code(game: Path, cues: dict, result: Result) -> None:
    for path in luau_files(game):
        text = path.read_text(encoding="utf-8", errors="replace")
        where = path.relative_to(game).as_posix()
        if path.name != "SoundBank.luau":
            for match in PLAY_RE.finditer(text):
                if cues and match.group(1) not in cues:
                    line = text.count("\n", 0, match.start()) + 1
                    result.error(f"{where}:{line}", f"SoundBank.play({match.group(1)!r}): ese cue no está en Audio.json")
        if ID_ANYWHERE_RE.search(text):
            result.warn(where, "tiene un rbxassetid:// escrito en el código: los IDs de audio van en Audio.json")


def check_docs(game: Path, assets: dict, cues: dict, result: Result) -> None:
    doc = game / "design" / "AUDIO.md"
    if not doc.is_file():
        result.warn("design/AUDIO.md", "no existe: documenta la intención sonora, los cues y qué debe subir el usuario")
    else:
        text = doc.read_text(encoding="utf-8", errors="replace")
        for name in cues:
            if name not in text:
                result.warn("design/AUDIO.md", f"no menciona el cue {name}")
    gdd = game / "GDD.md"
    if gdd.is_file():
        text = gdd.read_text(encoding="utf-8", errors="replace")
        for name, asset in assets.items():
            asset_id = asset.get("id") if isinstance(asset, dict) else ""
            if asset_id and ID_RE.match(str(asset_id)) and str(asset_id) not in text:
                result.warn("GDD.md", f"la sección Assets y servicios no lista el ID de assets.{name} ({asset_id})")


def check_environment_overlap(game: Path, assets: dict, result: Result) -> None:
    path = game / "src" / "shared" / "Environment.json"
    if not path.is_file():
        return
    try:
        environment = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return
    env_assets = environment.get("assets", {}) if isinstance(environment, dict) else {}
    own = {a.get("id"): n for n, a in assets.items() if isinstance(a, dict) and a.get("id")}
    for name, asset in env_assets.items() if isinstance(env_assets, dict) else []:
        if isinstance(asset, dict) and asset.get("kind") == "sound" and asset.get("id") in own:
            result.warn(f"assets.{own[asset['id']]}", f"el mismo ID está en Environment.json (assets.{name}): un audio, un dueño")


def check_game(game: Path) -> Result:
    result = Result()
    path = game / "src" / "shared" / "Audio.json"
    if not path.is_file():
        result.error("src/shared/Audio.json", "no existe")
        return result
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        result.error("src/shared/Audio.json", f"JSON no válido: {error}")
        return result
    if not isinstance(data, dict):
        result.error("src/shared/Audio.json", "debe ser un objeto")
        return result
    if data.get("schema") != 1:
        result.error("schema", "debe ser 1")
    buses = check_buses(data, result)
    assets = check_assets(data, game, result)
    cues = check_cues(data, assets, buses, result)
    check_code(game, cues, result)
    check_docs(game, assets, cues, result)
    check_environment_overlap(game, assets, result)
    pending = [n for n, a in assets.items() if isinstance(a, dict) and a.get("id", "") == ""]
    uploaded = [n for n, a in assets.items() if isinstance(a, dict) and ID_RE.match(str(a.get("id", "")))]
    if pending:
        result.note(f"Pendientes de subir a Creator Hub ({len(pending)}): {', '.join(pending)}")
    if uploaded:
        result.note(
            "Con ID: el audio es privado por defecto. Comprueba en Creator Hub (Audio > Configure > Permissions) "
            "que la experiencia tenga permiso, y escucha cada cue en Studio: si no, solo se ve un error en Output."
        )
    return result


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # igual en la consola de Windows
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("game", type=Path, help="carpeta del juego")
    parser.add_argument("--json", action="store_true", help="salida en JSON")
    args = parser.parse_args()
    result = check_game(args.game.resolve())
    if args.json:
        print(json.dumps({"errors": result.errors, "warnings": result.warnings, "notes": result.notes}, ensure_ascii=False, indent=2))
    else:
        for message in result.errors:
            print(f"ERROR  {message}")
        for message in result.warnings:
            print(f"AVISO  {message}")
        for message in result.notes:
            print(f"NOTA   {message}")
        print(f"{len(result.errors)} errores, {len(result.warnings)} avisos")
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
