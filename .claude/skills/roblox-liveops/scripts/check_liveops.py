#!/usr/bin/env python3
"""Revisa la configuración en vivo (LiveOps) de un juego de la fábrica.

Uso:
    python check_liveops.py <carpeta-del-juego>
    python check_liveops.py <carpeta-del-juego> --json

Comprueba:
  - src/server/LiveSchema.json: formato; cada clave en vivo apunta a una ruta de
    Config con un valor literal y tiene nombre de config válido y único; rangos
    coherentes; eventos con id único, fechas ISO en UTC (terminadas en Z), inicio
    anterior al fin y overrides con rutas y tipos de Config (y dentro del rango);
  - src/shared/LiveConfig.luau: existe y define getOverride;
  - design/LIVEOPS.md: existe, documenta cada clave y evento y tiene runbook.
Avisa si dos eventos se superponen en el tiempo y cambian la misma ruta.

Usa el lector de Config de check_game.py (roblox-game-builder), que debe estar
instalado al lado. Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

BUILDER_CHECK = Path(__file__).resolve().parents[2] / "roblox-game-builder" / "scripts" / "check_game.py"
CONFIG_KEY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
ISO_UTC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
JSON_TYPES = {bool: "boolean", int: "number", float: "number", str: "string"}
RUNBOOK_WORDS = ("activar", "revertir", "verificar")


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def load_builder_check():
    if not BUILDER_CHECK.exists():
        return None
    name = "factory_check_game"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, BUILDER_CHECK)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        del sys.modules[name]
        raise
    return module


def json_type(value) -> str:
    return JSON_TYPES.get(type(value), "other")


def parse_utc(text) -> datetime | None:
    if not isinstance(text, str) or not ISO_UTC_RE.match(text):
        return None
    try:
        return datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None


def check_value(path: str, value, keys_spec: dict, config, builder, where: str, result: Result) -> None:
    if config is None:
        return
    expected = builder.leaf_type(config, path)
    if expected is None:
        result.error(where, f"la ruta {path!r} no existe en Config")
        return
    if expected in {"table", "other"}:
        result.error(where, f"{path!r} no es un valor literal de Config (es {expected}); LiveOps solo ajusta números, textos y booleanos")
        return
    if value is not None and json_type(value) != expected:
        result.error(where, f"{path!r} es {expected} en Config y el valor es {json_type(value)}")
        return
    spec = keys_spec.get(path)
    if isinstance(value, (int, float)) and not isinstance(value, bool) and isinstance(spec, dict):
        low, high = spec.get("min"), spec.get("max")
        if (isinstance(low, (int, float)) and value < low) or (isinstance(high, (int, float)) and value > high):
            result.error(where, f"{path!r} = {value} está fuera del rango [{low}, {high}] del esquema")


def check_game(game: Path) -> Result:
    result = Result()
    builder = load_builder_check()
    config = None
    config_path = game / "src" / "shared" / "Config.luau"
    if builder is None:
        result.warn("Config.luau", "roblox-game-builder no está instalado al lado; no se comprobaron rutas ni tipos")
    elif not config_path.exists():
        result.error("src/shared/Config.luau", "no existe")
    else:
        try:
            config = builder.config_keys(config_path.read_text(encoding="utf-8"))
        except ValueError as exc:
            result.warn("src/shared/Config.luau", f"no se pudo analizar ({exc}); no se comprobaron rutas ni tipos")

    schema_where = "src/server/LiveSchema.json"
    schema_path = game / "src" / "server" / "LiveSchema.json"
    keys_spec: dict = {}
    event_ids: list[str] = []
    config_keys_used: list[str] = []
    if not schema_path.exists():
        result.error(schema_where, "no existe")
    else:
        try:
            schema = json.loads(schema_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            result.error(schema_where, f"JSON inválido: {exc}")
            schema = None
        if isinstance(schema, dict):
            if schema.get("schemaVersion") != 1:
                result.error(schema_where, "schemaVersion debe ser 1")
            if schema.get("refresh", "immediate") not in {"immediate", "manual"}:
                result.error(schema_where, "refresh debe ser 'immediate' o 'manual'")
            keys_spec = schema.get("keys", {})
            if not isinstance(keys_spec, dict):
                result.error(schema_where, "'keys' debe ser un objeto ruta de Config → {key, min?, max?}")
                keys_spec = {}
            for path, spec in keys_spec.items():
                where = f"{schema_where} keys[{path}]"
                if not isinstance(spec, dict) or not isinstance(spec.get("key"), str):
                    result.error(where, "necesita 'key' con el nombre del config en Creator Hub")
                    continue
                if not CONFIG_KEY_RE.match(spec["key"]):
                    result.error(where, f"nombre de config inválido: {spec['key']!r}")
                config_keys_used.append(spec["key"])
                low, high = spec.get("min"), spec.get("max")
                for bound in (low, high):
                    if bound is not None and (not isinstance(bound, (int, float)) or isinstance(bound, bool)):
                        result.error(where, "min y max deben ser números")
                if isinstance(low, (int, float)) and isinstance(high, (int, float)) and low > high:
                    result.error(where, "min es mayor que max")
                check_value(path, None, keys_spec, config, builder, where, result)
                if (low is not None or high is not None) and config is not None and builder.leaf_type(config, path) not in {None, "number"}:
                    result.error(where, "min y max solo valen para valores numéricos")
            duplicates = {key for key in config_keys_used if config_keys_used.count(key) > 1}
            for key in sorted(duplicates):
                result.error(schema_where, f"el config {key!r} se usa para más de una ruta")

            events = schema.get("events", [])
            if not isinstance(events, list):
                result.error(schema_where, "'events' debe ser una lista")
                events = []
            windows = []
            for index, event in enumerate(events):
                where = f"{schema_where} events[{index}]"
                if not isinstance(event, dict):
                    result.error(where, "cada evento debe ser un objeto")
                    continue
                event_id = event.get("id")
                if not isinstance(event_id, str) or not re.match(r"^[a-z0-9_]+$", event_id):
                    result.error(where, "'id' debe ser snake_case")
                elif event_id in event_ids:
                    result.error(where, f"id repetido: {event_id!r}")
                else:
                    event_ids.append(event_id)
                start, end = parse_utc(event.get("start")), parse_utc(event.get("end"))
                if start is None or end is None:
                    result.error(where, "start y end deben ser fechas ISO en UTC, por ejemplo 2026-10-25T00:00:00Z")
                elif start >= end:
                    result.error(where, "start debe ser anterior a end")
                overrides = event.get("overrides", {})
                if not isinstance(overrides, dict) or not overrides:
                    result.error(where, "'overrides' debe ser un objeto ruta de Config → valor, no vacío")
                    overrides = {}
                for path, value in overrides.items():
                    check_value(path, value, keys_spec, config, builder, f"{where} overrides[{path}]", result)
                if start and end:
                    windows.append((event_id, start, end, set(overrides)))
            for i, (first_id, first_start, first_end, first_paths) in enumerate(windows):
                for second_id, second_start, second_end, second_paths in windows[i + 1:]:
                    shared = first_paths & second_paths
                    if shared and first_start < second_end and second_start < first_end:
                        result.warn(schema_where, f"los eventos {first_id!r} y {second_id!r} se superponen y cambian {', '.join(sorted(shared))}; gana el que está después en la lista")
        elif schema is not None:
            result.error(schema_where, "debe ser un objeto JSON")

    module = game / "src" / "shared" / "LiveConfig.luau"
    if not module.exists():
        result.error("src/shared/LiveConfig.luau", "no existe; cópialo de assets/templates de roblox-liveops")
    elif not re.search(r"\bfunction\s+LiveConfig\.getOverride\s*\(", module.read_text(encoding="utf-8")):
        result.error("src/shared/LiveConfig.luau", "no define LiveConfig.getOverride")

    doc = game / "design" / "LIVEOPS.md"
    if not doc.exists():
        result.error("design/LIVEOPS.md", "no existe")
    else:
        text = doc.read_text(encoding="utf-8")
        lowered = text.lower()
        for name in config_keys_used + event_ids:
            if name not in text:
                result.warn("design/LIVEOPS.md", f"no documenta {name!r}")
        missing = [word for word in RUNBOOK_WORDS if word not in lowered]
        if missing:
            result.warn("design/LIVEOPS.md", f"el runbook no explica cómo {', '.join(missing)}")
    return result


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa la configuración en vivo de un juego de la fábrica.")
    parser.add_argument("game", type=Path, help="carpeta del juego (la que contiene GDD.md)")
    parser.add_argument("--json", action="store_true", help="imprime el resultado como JSON")
    args = parser.parse_args(argv)
    if not args.game.is_dir():
        print(f"ERROR no existe la carpeta {args.game}")
        return 2
    result = check_game(args.game.resolve())
    if args.json:
        print(json.dumps({"errors": result.errors, "warnings": result.warnings}, ensure_ascii=False, indent=2))
    else:
        print(f"Revisión de LiveOps: {args.game}")
        for line in result.errors:
            print(f"ERROR {line}")
        for line in result.warnings:
            print(f"WARN  {line}")
        print(f"Resultado: {len(result.errors)} errores, {len(result.warnings)} advertencias")
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
