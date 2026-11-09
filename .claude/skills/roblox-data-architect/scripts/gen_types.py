#!/usr/bin/env python3
"""Genera src/shared/DataTypes.luau con los tipos de Luau de DataSchema.json.

Uso:
    python gen_types.py <carpeta-del-juego>            escribe src/shared/DataTypes.luau
    python gen_types.py <carpeta-del-juego> --check    sale con 1 si está desactualizado
    python gen_types.py <ruta/DataSchema.json> --stdout

Un tipo por sección (Meta, Quests…) y Document con todas. Las fachadas de los cores los
usan para tipar lo que devuelven get() y update():

    local DataTypes = require(ReplicatedStorage.Shared.DataTypes)
    local data: DataTypes.Quests? = PlayerData.section(player, "quests"):get()
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SCHEMA_PATH = Path("src") / "server" / "Data" / "DataSchema.json"
TYPES_PATH = Path("src") / "shared" / "DataTypes.luau"
INDENT = "\t"


def type_name(section: str) -> str:
    return section[:1].upper() + section[1:]


def luau_type(spec: dict, depth: int) -> str:
    kind = spec.get("type")
    if kind == "boolean":
        return "boolean"
    if kind in {"integer", "number", "time"}:
        return "number"
    if kind == "string":
        return "string"
    if kind == "enum":
        return " | ".join(json.dumps(value, ensure_ascii=False) for value in spec.get("values", [])) or "string"
    if kind == "map":
        return f"{{ [string]: {luau_type(spec.get('value') or {}, depth)} }}"
    if kind == "list":
        return f"{{ {luau_type(spec.get('items') or {}, depth)} }}"
    if kind == "record":
        return record_type(spec.get("fields") or {}, depth)
    return "any"


def record_type(fields: dict, depth: int) -> str:
    inner = INDENT * (depth + 1)
    lines = ["{"]
    for name, spec in fields.items():
        key = name if re.fullmatch(r"[A-Za-z_]\w*", name) else f"[{json.dumps(name)}]"
        comment = f" -- {spec['description']}" if isinstance(spec, dict) and spec.get("description") else ""
        lines.append(f"{inner}{key}: {luau_type(spec if isinstance(spec, dict) else {}, depth + 1)},{comment}")
    lines.append(INDENT * depth + "}")
    return "\n".join(lines)


def generate(schema: dict) -> str:
    sections = schema.get("sections") or {}
    out = [
        "--!strict",
        "--[[",
        "\tDataTypes · generado por gen_types.py (roblox-data-architect) desde",
        f"\tsrc/server/Data/DataSchema.json, versión {schema.get('version')}. No lo edites a mano:",
        "\tvuelve a generarlo cuando cambie el esquema.",
        "]]",
        "",
    ]
    for name, section in sections.items():
        if section.get("description"):
            out.append(f"-- {section['description']}")
        out.append(f"export type {type_name(name)} = {record_type(section.get('fields') or {}, 0)}")
        out.append("")
    out.append("export type Document = {")
    for name in sections:
        out.append(f"{INDENT}{name}: {type_name(name)},")
    out.append("}")
    out.append("")
    out.append("return {}")
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Genera src/shared/DataTypes.luau desde DataSchema.json.")
    parser.add_argument("target", type=Path, help="carpeta del juego o un DataSchema.json")
    parser.add_argument("--check", action="store_true", help="no escribe; sale con 1 si DataTypes.luau está desactualizado")
    parser.add_argument("--stdout", action="store_true", help="imprime los tipos en lugar de escribirlos")
    args = parser.parse_args(argv)
    schema_path = args.target / SCHEMA_PATH if args.target.is_dir() else args.target
    if not schema_path.is_file():
        print(f"ERROR no existe {schema_path}")
        return 2
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        print(f"ERROR {schema_path}: JSON inválido: {exc}")
        return 2
    text = generate(schema)
    if args.stdout or not args.target.is_dir():
        print(text, end="")
        return 0
    output = args.target / TYPES_PATH
    current = output.read_text(encoding="utf-8").replace("\r\n", "\n") if output.exists() else None
    if args.check:
        if current != text:
            print(f"{TYPES_PATH.as_posix()} está desactualizado; corre gen_types.py")
            return 1
        print(f"{TYPES_PATH.as_posix()} está al día")
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8", newline="\n")
    print(f"Escrito {TYPES_PATH.as_posix()} ({len(schema.get('sections') or {})} secciones, versión {schema.get('version')})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
