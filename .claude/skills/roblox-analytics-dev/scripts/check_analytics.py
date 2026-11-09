#!/usr/bin/env python3
"""Revisa la instrumentación de analíticas de un juego de la fábrica.

Uso:
    python check_analytics.py <carpeta-del-juego>
    python check_analytics.py <carpeta-del-juego> --json

Comprueba:
  - src/server/AnalyticsSchema.json: formato y límites de Roblox (10 monedas,
    10 funnels, 100 eventos propios, 3 campos propios con ranuras CustomField01-03);
  - src/server/Analytics.luau: existe y define la API de Telemetry;
  - cada nombre literal que el código pasa a Telemetry (camino de progresión,
    funnel, moneda, evento propio) está declarado en el esquema; si no, Analytics
    lo descartaría en silencio;
  - design/ANALYTICS.md existe y menciona cada nombre del esquema.

Sale con código 1 si hay errores. check_game.py del builder lo ejecuta cuando el
GDD activa analytics.enabled y este skill está instalado al lado.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

TELEMETRY_API = ["onboarding", "funnel", "progressionStart", "progressionComplete", "progressionFail", "economy", "custom"]
SLOTS = {"CustomField01", "CustomField02", "CustomField03"}
LIMITS = {"currencies": 10, "funnels": 10, "customEvents": 100}
NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
SNAKE_RE = re.compile(r"^[a-z][a-z0-9_]*$")


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def strip_comments(code: str) -> str:
    """Quita comentarios de Luau (aproximado: suficiente para buscar llamadas)."""
    code = re.sub(r"--\[(=*)\[.*?\]\1\]", "", code, flags=re.DOTALL)
    return re.sub(r"--[^\n]*", "", code)


def string_constants(code: str) -> dict[str, str]:
    return {m.group(1): m.group(3) for m in re.finditer(r"\blocal\s+(\w+)\s*(?::\s*\w+)?\s*=\s*([\"'])([^\"'\n]*)\2", code)}


def resolve(argument: str, constants: dict[str, str]) -> str | None:
    argument = argument.strip()
    literal = re.fullmatch(r"([\"'])([^\"']*)\1", argument)
    if literal:
        return literal.group(2)
    return constants.get(argument)


def call_arguments(code: str, function: str):
    """Para cada llamada Telemetry.<function>(...), la lista de argumentos de primer nivel."""
    for match in re.finditer(rf"\bTelemetry\.{function}\s*\(", code):
        depth, index, start, args = 1, match.end(), match.end(), []
        while index < len(code) and depth:
            char = code[index]
            if char in "\"'`":
                end = code.find(char, index + 1)
                index = len(code) if end == -1 else end + 1
                continue
            if char in "({[":
                depth += 1
            elif char in ")}]":
                depth -= 1
                if depth == 0:
                    args.append(code[start:index])
                    break
            elif char == "," and depth == 1:
                args.append(code[start:index])
                start = index + 1
            index += 1
        yield args


def check_schema(schema, where: str, result: Result) -> dict[str, set[str]]:
    names: dict[str, set[str]] = {"progressionPaths": set(), "funnels": set(), "currencies": set(), "customEvents": set(), "dimensions": set()}
    if not isinstance(schema, dict):
        result.error(where, "debe ser un objeto JSON")
        return names
    if schema.get("schemaVersion") != 1:
        result.error(where, "schemaVersion debe ser 1")
    budget = schema.get("budgetPerPlayerPerMinute", 20)
    if not isinstance(budget, (int, float)) or isinstance(budget, bool) or not 0 < budget <= 20:
        result.error(where, "budgetPerPlayerPerMinute debe estar entre 1 y 20 (el límite global es 120 + 20 × CCU por minuto)")
    for key in ("progressionPaths", "funnels", "currencies", "customEvents"):
        value = schema.get(key, [])
        if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
            result.error(where, f"'{key}' debe ser una lista de nombres")
            continue
        if len(set(value)) != len(value):
            result.error(where, f"'{key}' repite nombres")
        for name in value:
            if not NAME_RE.match(name):
                result.error(where, f"nombre inválido en '{key}': {name!r}")
            elif key == "customEvents" and not SNAKE_RE.match(name):
                result.warn(where, f"el evento propio {name!r} debería estar en snake_case")
        if key in LIMITS and len(value) > LIMITS[key]:
            result.error(where, f"'{key}' tiene {len(value)} nombres; Roblox admite {LIMITS[key]}")
        names[key] = set(value)
    fields = schema.get("customFields", {})
    if not isinstance(fields, dict):
        result.error(where, "'customFields' debe ser un objeto ranura → dimensión")
    else:
        for slot, dimension in fields.items():
            if slot not in SLOTS:
                result.error(where, f"ranura desconocida {slot!r}; usa CustomField01, CustomField02 o CustomField03")
            if not isinstance(dimension, str) or not NAME_RE.match(dimension):
                result.error(where, f"dimensión inválida para {slot}: {dimension!r}")
        dimensions = [d for d in fields.values() if isinstance(d, str)]
        if len(set(dimensions)) != len(dimensions):
            result.error(where, "dos ranuras usan la misma dimensión")
        names["dimensions"] = set(dimensions)
    return names


def check_game(game: Path) -> Result:
    result = Result()
    server = game / "src" / "server"
    schema_path = server / "AnalyticsSchema.json"
    analytics_path = server / "Analytics.luau"
    names = {"progressionPaths": set(), "funnels": set(), "currencies": set(), "customEvents": set(), "dimensions": set()}
    if not schema_path.exists():
        result.error("src/server/AnalyticsSchema.json", "no existe")
    else:
        try:
            schema = json.loads(schema_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            result.error("src/server/AnalyticsSchema.json", f"JSON inválido: {exc}")
        else:
            names = check_schema(schema, "src/server/AnalyticsSchema.json", result)

    if not analytics_path.exists():
        result.error("src/server/Analytics.luau", "no existe; cópialo de assets/templates de roblox-analytics-dev")
    else:
        code = strip_comments(analytics_path.read_text(encoding="utf-8"))
        defined = set(re.findall(r"\bfunction\s+Analytics\.(\w+)\s*\(", code))
        missing = [name for name in TELEMETRY_API if name not in defined]
        if missing:
            result.error("src/server/Analytics.luau", f"faltan funciones de la API de Telemetry: {', '.join(missing)}")

    used: dict[str, set[str]] = {key: set() for key in names}
    positions = {"progressionStart": ("progressionPaths", 1), "progressionComplete": ("progressionPaths", 1),
                 "progressionFail": ("progressionPaths", 1), "funnel": ("funnels", 1),
                 "economy": ("currencies", 2), "custom": ("customEvents", 1)}
    src = game / "src"
    for path in sorted(src.rglob("*.luau")) if src.is_dir() else []:
        if path.name in {"Telemetry.luau", "Analytics.luau"}:
            continue
        code = strip_comments(path.read_text(encoding="utf-8"))
        constants = string_constants(code)
        where = path.relative_to(game).as_posix()
        for function, (kind, position) in positions.items():
            for args in call_arguments(code, function):
                if len(args) <= position:
                    continue
                name = resolve(args[position], constants)
                if name is None:
                    continue  # nombre calculado: no se puede comprobar estáticamente
                used[kind].add(name)
                if names[kind] is not None and name not in names[kind] and schema_path.exists():
                    result.error(where, f"Telemetry.{function} usa {name!r}, que no está en AnalyticsSchema.json ({kind}); Analytics lo descartaría")
    for kind in ("progressionPaths", "funnels", "currencies", "customEvents"):
        for name in sorted(names[kind] - used[kind]):
            result.warn("src/server/AnalyticsSchema.json", f"{name!r} ({kind}) no aparece en ninguna llamada literal de Telemetry")

    doc = game / "design" / "ANALYTICS.md"
    if not doc.exists():
        result.error("design/ANALYTICS.md", "no existe")
    else:
        text = doc.read_text(encoding="utf-8")
        for kind in ("progressionPaths", "funnels", "currencies", "customEvents", "dimensions"):
            for name in sorted(names[kind]):
                if name not in text:
                    result.warn("design/ANALYTICS.md", f"no documenta {name!r} ({kind})")
    return result


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa las analíticas de un juego de la fábrica.")
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
        print(f"Revisión de analíticas: {args.game}")
        for line in result.errors:
            print(f"ERROR {line}")
        for line in result.warnings:
            print(f"WARN  {line}")
        print(f"Resultado: {len(result.errors)} errores, {len(result.warnings)} advertencias")
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
