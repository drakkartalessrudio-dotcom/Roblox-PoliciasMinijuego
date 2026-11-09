#!/usr/bin/env python3
"""Lleva la sección de datos de un módulo de la librería (Roblox-Library) al DataSchema.json del juego.

Uso:
    python library_section.py <Juego> <data/section.json del módulo>
    python library_section.py <Juego> <data/section.json del módulo> --since <versión que tenía el juego>

- Si el juego no tiene la sección, la agrega tal cual. No sube la versión: al cargar, el
  servicio completa la sección nueva con sus valores por defecto.
- Si la tiene igual, no cambia nada.
- Si la tiene distinta (el módulo se actualizó), --since dice qué versión del módulo
  tenía el juego. Las migraciones del fragmento posteriores a esa versión se agregan como
  una versión nueva del esquema: copia las secciones actuales a history, sube version en 1,
  reemplaza la sección y junta sus operaciones en una migración. Sin migraciones, solo
  reemplaza la sección (vale para campos nuevos con valor por defecto).

Formato del fragmento (el de data/section.json en la librería):
    { "section": "rewards", "definition": { "owner": "Rewards", ... },
      "migrations": [ { "version": "2.0.0", "description": "…", "ops": [ { "op": "move", ... } ] } ] }
Las rutas de las operaciones empiezan por la sección, como en DataSchema.json; custom no
está permitido (Migrations.luau es del juego).

Al final corre check_data.py sobre el juego. Después hay que volver a correr gen_types.py.
Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
SEMVER_RE = re.compile(r"\d+\.\d+\.\d+")
OPS = {"move": ("from", "to"), "add": ("path",), "set": ("path",), "remove": ("path",)}


class SectionError(Exception):
    pass


def version_tuple(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in str(text).split("."))


def fragment_migrations(fragment: dict, since: str | None) -> list[dict]:
    """Migraciones del fragmento más nuevas que since, validadas y en orden."""
    section = fragment["section"]
    found = []
    for index, migration in enumerate(fragment.get("migrations") or []):
        where = f"migrations[{index}]"
        if not isinstance(migration, dict) or not SEMVER_RE.fullmatch(str(migration.get("version", ""))):
            raise SectionError(f"{where}: cada migración tiene version (semver del módulo), description y ops")
        ops = migration.get("ops")
        if not isinstance(ops, list) or not ops:
            raise SectionError(f"{where}: ops debe ser una lista con al menos una operación")
        for op in ops:
            keys = OPS.get(op.get("op")) if isinstance(op, dict) else None
            if keys is None:
                raise SectionError(f"{where}: operación {op!r}; una librería solo usa {', '.join(OPS)}")
            for key in keys:
                path = str(op.get(key, ""))
                if not path.startswith(section + "."):
                    raise SectionError(f"{where}: {key} {path!r} debe empezar por la sección {section}.")
        if since is None or version_tuple(migration["version"]) > version_tuple(since):
            found.append(migration)
    return sorted(found, key=lambda migration: version_tuple(migration["version"]))


def merge(game: Path, fragment_path: Path, since: str | None = None) -> list[str]:
    """Aplica el fragmento al esquema del juego. Devuelve qué hizo."""
    schema_path = game / "src" / "server" / "Data" / "DataSchema.json"
    if not schema_path.exists():
        raise SectionError(f"{game.resolve().name} no tiene src/server/Data/DataSchema.json: diseña primero sus datos")
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    fragment = json.loads(fragment_path.read_text(encoding="utf-8"))
    section, definition = fragment.get("section"), fragment.get("definition")
    if not isinstance(section, str) or not isinstance(definition, dict):
        raise SectionError(f"{fragment_path.name} necesita section y definition")
    if since is not None and not SEMVER_RE.fullmatch(since):
        raise SectionError("--since debe ser una versión semver (x.y.z)")
    migrations = fragment_migrations(fragment, since)
    sections = schema.setdefault("sections", {})
    current = sections.get(section)
    done = []
    if current is None:
        sections[section] = definition
        done.append(f"sección {section} agregada (dueño {definition.get('owner')}); la versión del esquema no cambia")
    elif current == definition:
        return [f"la sección {section} ya es igual a la de la librería"]
    else:
        if current.get("owner") != definition.get("owner"):
            raise SectionError(f"la sección {section} del juego es de {current.get('owner')} y la de la librería de "
                               f"{definition.get('owner')}: no es la misma sección")
        if since is None:
            raise SectionError(f"la sección {section} ya existe y es distinta: pasa --since con la versión del módulo que tenía el juego")
        if migrations:
            old = int(schema.get("version", 1))
            schema.setdefault("history", {})[str(old)] = {"sections": copy.deepcopy(sections)}
            schema["version"] = old + 1
            sections[section] = definition
            schema.setdefault("migrations", []).append({
                "from": old,
                "to": old + 1,
                "description": f"{definition.get('owner')} {since} → {migrations[-1]['version']}: "
                               + "; ".join(str(migration.get("description", "")).strip() for migration in migrations),
                "ops": [op for migration in migrations for op in migration["ops"]],
            })
            done.append(f"versión {old} → {old + 1}: la sección {section} sigue a {definition.get('owner')}@{migrations[-1]['version']} "
                        f"con {sum(len(migration['ops']) for migration in migrations)} operaciones; la forma anterior quedó en history[\"{old}\"]")
        else:
            sections[section] = definition
            done.append(f"sección {section} reemplazada sin migración: solo vale si agregó campos con valor por defecto")
    schema_path.write_text(json.dumps(schema, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    done.append("vuelve a generar los tipos: python gen_types.py " + game.resolve().name)
    return done


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Lleva la sección de datos de un módulo de la librería al esquema del juego.")
    parser.add_argument("game", type=Path)
    parser.add_argument("fragment", type=Path, help="data/section.json del módulo en la librería")
    parser.add_argument("--since", help="versión del módulo que tenía el juego (cuando la sección ya existe)")
    args = parser.parse_args(argv)
    try:
        done = merge(args.game, args.fragment, args.since)
    except (SectionError, json.JSONDecodeError, OSError) as exc:
        print(f"ERROR {exc}")
        return 2
    for line in done:
        print(f"- {line}")
    sys.path.insert(0, str(SCRIPTS))
    import check_data  # noqa: E402

    report = check_data.check_game(args.game)
    for line in report.errors:
        print(f"ERROR {line}")
    for line in report.warnings:
        print(f"WARN  {line}")
    print(f"check_data.py: {len(report.errors)} errores, {len(report.warnings)} advertencias")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
