#!/usr/bin/env python3
"""Revisa el diseño de los datos guardados del jugador de un juego de la fábrica.

Uso:
    python check_data.py <carpeta-del-juego>
    python check_data.py <ruta/a/DataSchema.json>
    python check_data.py <...> --json

Comprueba:
  - DataSchema.json: formato, DataStore y clave (con {UserId} para el borrado de
    datos de Roblox), persistencia, secciones con dueño y rol, tipos, valores por
    defecto y límites;
  - antipatrones: un booleano por paso, listas por posición, datos personales, una
    sección con demasiados campos (perfil general) y la versión guardada como campo;
  - migraciones: una por versión, de 1 a la actual, simuladas sobre un perfil de
    ejemplo de cada versión guardada en history;
  - el tamaño del documento en el peor caso contra el límite por clave de Roblox;
  - con la carpeta del juego: design/DATA.md (promesas y secciones), el frontmatter
    del GDD (design.data, data.persistence, modo, LiveOps y Developer Products), los
    dueños contra el Mapa de módulos, las plantillas del servicio de datos sin cambios,
    las funciones de Migrations.luau, DataTypes.luau al día y que cada
    PlayerData.section(…, "x") esté en el core dueño de x.

Es un análisis estático: no prueba que el juego guarde bien. Sale con código 1 si hay
errores.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

SKILLS_DIR = Path(__file__).resolve().parents[2]
BUILDER_SCRIPTS = SKILLS_DIR / "roblox-game-builder" / "scripts"
TEMPLATES = Path(__file__).resolve().parents[1] / "assets" / "templates" / "src" / "server" / "Data"
SERVICE_FILES = ["PlayerData.luau", "Session.luau", "Profile.luau", "Store.luau", "DataDebug.luau"]
DATA_DIR = Path("src") / "server" / "Data"
SCHEMA_PATH = DATA_DIR / "DataSchema.json"
MIGRATIONS_PATH = DATA_DIR / "Migrations.luau"
TYPES_PATH = Path("src") / "shared" / "DataTypes.luau"
DOC_PATH = Path("design") / "DATA.md"
SECTION_CALL_RE = re.compile(r"\bPlayerData\.section\s*\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*([\"'])(\w+)\1")

KEY_LIMIT = 4_194_304  # caracteres por clave, medidos con JSONEncode (verificado el 2026-10-14)
DEFAULT_BUDGET = 1_000_000
NAME_LIMIT = 50
USER_ID_DIGITS = 19
DOCUMENT_OVERHEAD = 64  # versión y envoltorio del documento
SECTION_FIELDS = 12  # más campos en una sección suele ser un perfil general con varios dominios
SCALARS = {"boolean", "integer", "number", "string", "enum", "time"}
TYPES = SCALARS | {"map", "list", "record"}
ROLES = {"meta", "purchases", "entitlements"}
PERSISTENCE = {"persistent", "memory"}
OPS = {"move", "add", "set", "remove", "custom"}
SERVICE_OWNER = "PlayerData"
CAMEL_RE = re.compile(r"[a-z][A-Za-z0-9]*")
PASCAL_RE = re.compile(r"[A-Z][A-Za-z0-9]*")
PERSONAL_RE = re.compile(r"e-?mail|correo|phone|tel[eé]fono|address|direcci[oó]n|password|contrase|birth|nacimiento|"
                         r"realname|fullname|ipaddress|^ip$|location|ubicaci[oó]n|username|displayname", re.I)
STEP_RE = re.compile(r"first|second|third|fourth|fifth|step\d|paso\d|primer|segund|tercer|cuart", re.I)


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    info: list[str] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")

    def note(self, where: str, message: str) -> None:
        self.info.append(f"{where}: {message}")


def load_sibling(path: Path, name: str):
    """Carga un script de otro skill instalado al lado, o None si no está."""
    if not path.exists():
        return None
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        del sys.modules[name]
        raise
    return module


def spanish(number: int) -> str:
    """Entero con punto de miles: 4.194.304."""
    return f"{number:,}".replace(",", ".")


def percent(ratio: float) -> str:
    """Porcentaje con coma decimal: 3,0 %."""
    return f"{ratio * 100:.1f} %".replace(".", ",")


def is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value) -> bool:
    return (is_int(value) or isinstance(value, float)) and math.isfinite(value)


# --- Tipos ---------------------------------------------------------------------

def default_value(spec: dict):
    """Valor por defecto de un campo: el declarado o el del tipo."""
    if "default" in spec:
        return copy.deepcopy(spec["default"])
    kind = spec.get("type")
    if kind == "boolean":
        return False
    if kind in {"integer", "number"}:
        value = 0
        if is_number(spec.get("min")) and value < spec["min"]:
            value = spec["min"]
        if is_number(spec.get("max")) and value > spec["max"]:
            value = spec["max"]
        return value
    if kind == "string":
        return ""
    if kind == "enum":
        values = spec.get("values") or [""]
        return values[0]
    if kind == "time":
        return 0
    if kind == "map":
        return {}
    if kind == "list":
        return []
    if kind == "record":
        return {name: default_value(child) for name, child in (spec.get("fields") or {}).items() if isinstance(child, dict)}
    return None


def sample_value(spec: dict):
    """Valor de ejemplo con una entrada en cada mapa y lista, para simular migraciones."""
    kind = spec.get("type")
    if kind == "map" and isinstance(spec.get("value"), dict):
        return {"sample": sample_value(spec["value"])}
    if kind == "list" and isinstance(spec.get("items"), dict):
        return [sample_value(spec["items"])]
    if kind == "record":
        return {name: sample_value(child) for name, child in (spec.get("fields") or {}).items() if isinstance(child, dict)}
    return default_value(spec)


def value_problems(spec: dict, value, path: str, leftovers: list[str]) -> list[str]:
    """Diferencias entre un valor y su campo. Los campos que el esquema no conoce van a leftovers."""
    kind = spec.get("type")
    problems: list[str] = []

    def bounds(number) -> None:
        if is_number(spec.get("min")) and number < spec["min"]:
            problems.append(f"`{path}` vale {number}, menos que min {spec['min']}")
        if is_number(spec.get("max")) and number > spec["max"]:
            problems.append(f"`{path}` vale {number}, más que max {spec['max']}")

    if kind == "boolean":
        if not isinstance(value, bool):
            problems.append(f"`{path}` debe ser boolean")
    elif kind == "integer":
        if not is_int(value):
            problems.append(f"`{path}` debe ser integer")
        else:
            bounds(value)
    elif kind == "number":
        if not is_number(value):
            problems.append(f"`{path}` debe ser number")
        else:
            bounds(value)
    elif kind == "time":
        if not is_int(value) or value < 0:
            problems.append(f"`{path}` debe ser time (segundos UTC, entero ≥ 0)")
    elif kind == "string":
        if not isinstance(value, str):
            problems.append(f"`{path}` debe ser string")
        elif is_int(spec.get("maxLength")) and len(value) > spec["maxLength"]:
            problems.append(f"`{path}` pasa de maxLength {spec['maxLength']}")
    elif kind == "enum":
        if value not in (spec.get("values") or []):
            problems.append(f"`{path}` vale {value!r}, que no está en values")
    elif kind == "map":
        if not isinstance(value, dict):
            problems.append(f"`{path}` debe ser un mapa")
        else:
            limit = spec.get("maxEntries")
            if is_int(limit) and len(value) > limit:
                problems.append(f"`{path}` tiene más de maxEntries {limit}")
            for key, item in value.items():
                problems += value_problems(spec.get("value") or {}, item, f"{path}.{key}", leftovers)
    elif kind == "list":
        if not isinstance(value, list):
            problems.append(f"`{path}` debe ser una lista")
        else:
            limit = spec.get("maxItems")
            if is_int(limit) and len(value) > limit:
                problems.append(f"`{path}` tiene más de maxItems {limit}")
            for index, item in enumerate(value):
                problems += value_problems(spec.get("items") or {}, item, f"{path}[{index}]", leftovers)
    elif kind == "record":
        if not isinstance(value, dict):
            problems.append(f"`{path}` debe ser un registro")
        else:
            fields = spec.get("fields") or {}
            for key, item in value.items():
                if key not in fields:
                    leftovers.append(f"{path}.{key}")
                elif isinstance(fields[key], dict):
                    problems += value_problems(fields[key], item, f"{path}.{key}", leftovers)
    return problems


def max_size(spec: dict) -> int:
    """Largo máximo del JSON de un valor, en caracteres."""
    kind = spec.get("type")
    if kind == "boolean":
        return 5
    if kind == "integer":
        limits = [abs(spec[name]) for name in ("min", "max") if is_number(spec.get(name))]
        return (len(str(int(max(limits)))) + 1) if limits and is_number(spec.get("max")) else 17
    if kind == "number":
        return 24
    if kind == "time":
        return 10
    if kind == "string":
        return (spec.get("maxLength") if is_int(spec.get("maxLength")) else 0) + 2
    if kind == "enum":
        return max((len(str(value)) for value in spec.get("values") or [""]), default=0) + 2
    if kind == "map":
        entries = spec.get("maxEntries") if is_int(spec.get("maxEntries")) else 0
        key = spec.get("keyMaxLength") if is_int(spec.get("keyMaxLength")) else 32
        return 2 + entries * (key + 4 + max_size(spec.get("value") or {}))
    if kind == "list":
        items = spec.get("maxItems") if is_int(spec.get("maxItems")) else 0
        return 2 + items * (max_size(spec.get("items") or {}) + 1)
    if kind == "record":
        fields = spec.get("fields") or {}
        return 2 + sum(len(name) + 4 + max_size(child) for name, child in fields.items() if isinstance(child, dict))
    return 0


# --- Esquema -------------------------------------------------------------------

def check_spec(spec, where: str, report: Report, style: bool = True) -> None:
    """Valida la definición de un campo. style=False omite los avisos de estilo (para history)."""
    if not isinstance(spec, dict):
        report.error(where, "cada campo es un objeto con 'type'")
        return
    kind = spec.get("type")
    if kind not in TYPES:
        report.error(where, f"type debe ser uno de {', '.join(sorted(TYPES))} (es {kind!r})")
        return
    if kind in {"integer", "number"}:
        for name in ("min", "max"):
            if name in spec and not is_number(spec[name]):
                report.error(where, f"{name} debe ser un número")
        if is_number(spec.get("min")) and is_number(spec.get("max")) and spec["min"] > spec["max"]:
            report.error(where, "min es mayor que max")
    elif kind == "string":
        if not is_int(spec.get("maxLength")) or spec["maxLength"] < 1:
            report.error(where, "un string necesita maxLength (entero ≥ 1): sin él no se puede estimar el tamaño")
    elif kind == "enum":
        values = spec.get("values")
        if not isinstance(values, list) or not values or not all(isinstance(v, str) for v in values):
            report.error(where, "un enum necesita values: una lista de textos")
        elif len(set(values)) != len(values):
            report.error(where, "values tiene textos repetidos")
    elif kind == "map":
        if not isinstance(spec.get("key"), str) or not spec["key"]:
            report.error(where, "un map necesita key: el nombre del ID que usa como clave (por ejemplo questId)")
        if not is_int(spec.get("maxEntries")) or spec["maxEntries"] < 1:
            report.error(where, "un map necesita maxEntries: sin límite el perfil puede crecer hasta romper el límite por clave")
        if "keyMaxLength" in spec and (not is_int(spec["keyMaxLength"]) or spec["keyMaxLength"] < 1):
            report.error(where, "keyMaxLength debe ser un entero ≥ 1")
        if "value" not in spec:
            report.error(where, "un map necesita value: el tipo de cada entrada")
        else:
            check_spec(spec["value"], f"{where}.value", report, style)
    elif kind == "list":
        if not is_int(spec.get("maxItems")) or spec["maxItems"] < 1:
            report.error(where, "una lista necesita maxItems")
        if "items" not in spec:
            report.error(where, "una lista necesita items: el tipo de cada elemento")
        else:
            check_spec(spec["items"], f"{where}.items", report, style)
        if style and spec.get("ordered") is not True:
            report.warn(where, "lista por posición: usa un mapa por ID estable, o marca ordered: true y explica en why por qué importa el orden")
    elif kind == "record":
        fields = spec.get("fields")
        if not isinstance(fields, dict) or not fields:
            report.error(where, "un record necesita fields")
        else:
            check_fields(fields, where, report, style)
    if "default" in spec and kind in TYPES:
        problems = value_problems(spec, spec["default"], "default", [])
        for problem in problems:
            report.error(where, f"valor por defecto inválido: {problem}")


def check_fields(fields: dict, where: str, report: Report, style: bool = True) -> None:
    steps = []
    for name, spec in fields.items():
        here = f"{where}.{name}"
        if style:
            if not CAMEL_RE.fullmatch(name):
                report.warn(here, "los nombres de campo van en camelCase")
            if PERSONAL_RE.search(name):
                report.warn(here, "parece un dato personal: no lo guardes (el UserId ya está en la clave)")
            if isinstance(spec, dict) and spec.get("type") == "boolean" and STEP_RE.search(name):
                steps.append(name)
        check_spec(spec, here, report, style)
    if len(steps) >= 2:
        report.warn(where, f"un booleano por paso ({', '.join(steps)}): usa un mapa de banderas flagId → time")


def check_sections(sections, where: str, report: Report, style: bool = True) -> None:
    if not isinstance(sections, dict) or not sections:
        report.error(where, "sections debe tener al menos una sección")
        return
    for name, section in sections.items():
        here = f"{where}.{name}"
        if not isinstance(section, dict):
            report.error(here, "cada sección es un objeto con owner y fields")
            continue
        if style and not CAMEL_RE.fullmatch(name):
            report.warn(here, "los nombres de sección van en camelCase")
        owner = section.get("owner")
        role = section.get("role")
        if style:  # las formas viejas de history solo necesitan sus campos
            if not isinstance(owner, str) or not PASCAL_RE.fullmatch(owner):
                report.error(here, "owner debe ser el nombre de un core (PascalCase) o PlayerData")
            elif owner == SERVICE_OWNER and role != "meta":
                report.error(here, "PlayerData (el servicio de datos) solo es dueño de la sección con rol meta")
            if role is not None and role not in ROLES:
                report.error(here, f"role debe ser {', '.join(sorted(ROLES))} (es {role!r})")
        fields = section.get("fields")
        if not isinstance(fields, dict) or not fields:
            report.error(here, "una sección necesita fields")
            continue
        check_fields(fields, here, report, style)
        if style and len(fields) > SECTION_FIELDS:
            report.warn(here, f"tiene {len(fields)} campos: parece un perfil general; repártela en una sección por core")
        if style and any(name.lower() == "version" for name in fields):
            report.warn(here, "la versión del documento es 'version' del esquema y la guarda el servicio; no la guardes como campo")
        if style and role == "purchases" and not any(isinstance(s, dict) and s.get("type") == "map" for s in fields.values()):
            report.error(here, "la sección de recibos necesita un mapa purchaseId → time para que ProcessReceipt sea idempotente")


def section_spec(section: dict) -> dict:
    return {"type": "record", "fields": section.get("fields") or {}}


def document_sample(sections: dict) -> dict:
    return {name: sample_value(section_spec(section)) for name, section in sections.items() if isinstance(section, dict)}


def check_document(schema: dict, report: Report) -> None:
    where = "document"
    document = schema.get("document")
    if not isinstance(document, dict):
        report.error(where, "falta el objeto document (store, key, persistence)")
        return
    store = document.get("store")
    if not isinstance(store, str) or not 1 <= len(store) <= NAME_LIMIT:
        report.error(where, f"store debe ser el nombre del DataStore, de 1 a {NAME_LIMIT} caracteres")
    key = document.get("key")
    if not isinstance(key, str) or "{UserId}" not in key:
        report.error(where, "key debe contener {UserId} escrito así (las plantillas de borrado de datos de Roblox lo buscan con esas mayúsculas)")
    else:
        others = [token for token in re.findall(r"\{[^}]*\}", key) if token != "{UserId}"]
        if others:
            report.error(where, f"key solo admite {{UserId}}; sobra {', '.join(others)}")
        if len(key.replace("{UserId}", "9" * USER_ID_DIGITS)) > NAME_LIMIT:
            report.error(where, f"key con un UserId de {USER_ID_DIGITS} dígitos pasa de {NAME_LIMIT} caracteres")
    if document.get("persistence") not in PERSISTENCE:
        report.error(where, "persistence debe ser persistent o memory")
    if "legacy" in document and not isinstance(document["legacy"], bool):
        report.error(where, "legacy debe ser true o false")
    if "budget" in document and (not is_int(document["budget"]) or not 0 < document["budget"] <= KEY_LIMIT):
        report.error(where, f"budget debe ser un entero entre 1 y {KEY_LIMIT}")


# --- Migraciones -------------------------------------------------------------

def split_path(path) -> list[str] | None:
    if not isinstance(path, str) or not path or any(not part for part in path.split(".")):
        return None
    return path.split(".")


def matches(node, parts: list[str], keys: list[str] | None = None) -> list[tuple[list[str], list[str]]]:
    """Rutas concretas que coinciden con parts; cada una con las claves que tomó cada *."""
    keys = keys or []
    if not parts:
        return [([], keys)]
    if not isinstance(node, dict):
        return []
    head, rest = parts[0], parts[1:]
    found = []
    candidates = list(node) if head == "*" else ([head] if head in node else [])
    for key in candidates:
        for path, taken in matches(node[key], rest, keys + ([key] if head == "*" else [])):
            found.append(([key] + path, taken))
    return found


def get_at(node, path: list[str]):
    for key in path:
        node = node[key]
    return node


def set_at(node: dict, path: list[str], value, only_if_absent: bool = False) -> None:
    for key in path[:-1]:
        child = node.get(key)
        if not isinstance(child, dict):
            child = {}
            node[key] = child
        node = child
    if only_if_absent and path[-1] in node:
        return
    node[path[-1]] = value


def substitute(parts: list[str], keys: list[str]) -> list[str]:
    taken = iter(keys)
    return [next(taken) if part == "*" else part for part in parts]


def apply_op(document: dict, op: dict) -> list[str]:
    """Aplica una operación a un perfil de ejemplo. Devuelve los problemas encontrados."""
    kind = op.get("op")
    if kind == "move":
        source, target = split_path(op.get("from")), split_path(op.get("to"))
        found = matches(document, source)
        if not found:
            return [f"move no encuentra `{op.get('from')}`"]
        for path, keys in found:
            value = get_at(document, path)
            parent = get_at(document, path[:-1]) if len(path) > 1 else document
            del parent[path[-1]]
            set_at(document, substitute(target, keys), value)
        return []
    if kind in {"add", "set"}:
        parts = split_path(op.get("path"))
        if "*" not in parts:
            # Sin comodines, los registros intermedios que falten se crean.
            set_at(document, parts, copy.deepcopy(op.get("value")), kind == "add")
            return []
        parents = matches(document, parts[:-1])
        if not parents:
            return [f"{kind} no encuentra dónde poner `{op.get('path')}`"]
        for path, _ in parents:
            set_at(document, path + [parts[-1]], copy.deepcopy(op.get("value")), kind == "add")
        return []
    if kind == "remove":
        found = matches(document, split_path(op.get("path")))
        if not found:
            return [f"remove no encuentra `{op.get('path')}`"]
        for path, _ in found:
            parent = get_at(document, path[:-1]) if len(path) > 1 else document
            del parent[path[-1]]
        return []
    return []


def check_op(op, where: str, report: Report) -> None:
    if not isinstance(op, dict) or op.get("op") not in OPS:
        report.error(where, f"cada operación tiene op: {', '.join(sorted(OPS))}")
        return
    kind = op["op"]
    if kind == "move":
        source, target = split_path(op.get("from")), split_path(op.get("to"))
        if source is None or target is None:
            report.error(where, "move necesita from y to como rutas sección.campo")
        elif source.count("*") != target.count("*"):
            report.error(where, "en un move, from y to llevan la misma cantidad de *")
    elif kind in {"add", "set", "remove"}:
        parts = split_path(op.get("path"))
        if parts is None:
            report.error(where, f"{kind} necesita path como ruta sección.campo")
        elif parts[-1] == "*":
            report.error(where, f"{kind}: la ruta no puede terminar en *")
        if kind in {"add", "set"} and "value" not in op:
            report.error(where, f"{kind} necesita value")
    elif kind == "custom":
        if not isinstance(op.get("name"), str) or not op["name"]:
            report.error(where, "custom necesita name: la función de Migrations.luau")
        if not isinstance(op.get("sections"), list) or not op["sections"]:
            report.error(where, "custom necesita sections: las secciones que toca")


def check_migrations(schema: dict, report: Report) -> None:
    version = schema.get("version")
    if not is_int(version) or version < 1:
        report.error("version", "version debe ser un entero ≥ 1")
        return
    migrations = schema.get("migrations", [])
    if not isinstance(migrations, list):
        report.error("migrations", "migrations debe ser una lista")
        return
    # Con document.legacy, los perfiles de antes de PlayerData entran como versión 0.
    first = 0 if (schema.get("document") or {}).get("legacy") is True else 1
    by_from: dict[int, dict] = {}
    for index, migration in enumerate(migrations):
        where = f"migrations[{index}]"
        if not isinstance(migration, dict) or not is_int(migration.get("from")) or migration.get("to") != migration.get("from", 0) + 1:
            report.error(where, "cada migración va de una versión a la siguiente: from N, to N + 1")
            continue
        start = migration["from"]
        if not first <= start < version:
            report.error(where, f"from {start} está fuera de las versiones {first} a {version - 1}")
            continue
        if start in by_from:
            report.error(where, f"hay dos migraciones desde la versión {start}")
            continue
        ops = migration.get("ops")
        if not isinstance(ops, list) or not ops:
            report.error(where, "una migración necesita ops")
            continue
        valid = Report()
        for op_index, op in enumerate(ops):
            check_op(op, f"{where}.ops[{op_index}]", valid)
        report.errors += valid.errors
        if not valid.errors:
            by_from[start] = migration
    for missing in range(first, version):
        if missing not in by_from and not any(isinstance(m, dict) and m.get("from") == missing for m in migrations):
            report.error("migrations", f"falta la migración de la versión {missing} a la {missing + 1}")

    history = schema.get("history", {})
    if not isinstance(history, dict):
        report.error("history", "history debe ser un objeto: versión → { sections }")
        return
    for key in history:
        if not key.isdigit() or not first <= int(key) < version:
            report.error("history", f"history[{key!r}] no es una versión anterior a la {version}")
    current = schema.get("sections") if isinstance(schema.get("sections"), dict) else {}
    if first == 0 and isinstance(history.get("0"), dict) and "legacy" not in (history["0"].get("sections") or {}):
        report.warn("history", "con document.legacy, history[\"0\"] describe el perfil viejo en una sección llamada legacy")
    for start in range(first, version):
        past = history.get(str(start))
        if not isinstance(past, dict):
            report.warn("history", f"falta la forma de la versión {start}: sin ella no se simuló su migración")
            continue
        shape = Report()
        check_sections(past.get("sections"), f"history.{start}.sections", shape, style=False)
        report.errors += shape.errors
        if shape.errors or any(step not in by_from for step in range(start, version)):
            continue
        simulate(start, version, past["sections"], current, by_from, report)


def simulate(start: int, version: int, past_sections: dict, current: dict, by_from: dict, report: Report) -> None:
    document = document_sample(past_sections)
    opaque: set[str] = set()
    for step in range(start, version):
        for op in by_from[step]["ops"]:
            if op["op"] == "custom":
                opaque |= set(op["sections"])
                report.note("migraciones", f"{step}→{step + 1}: la operación custom {op['name']} no se simula; pruébala con el servicio de datos")
                continue
            for problem in apply_op(document, op):
                report.error("migraciones", f"{step}→{step + 1}, desde un perfil de la versión {start}: {problem}")
    where = f"migraciones desde la versión {start}"
    for name, value in document.items():
        if name in opaque:
            continue
        if name not in current:
            # Una sección que ya no existe: cada campo que quedó en ella se perdería.
            remaining = list(value) if isinstance(value, dict) else []
            for key in remaining:
                report.error(where, f"`{name}.{key}` quedaría sin migrar y se perdería (la sección `{name}` ya no existe); muévelo o bórralo")
            if not isinstance(value, dict):
                report.error(where, f"la sección `{name}` quedaría sin migrar y se perdería; muévela o bórrala")
            continue
        leftovers: list[str] = []
        for problem in value_problems(section_spec(current[name]), value, name, leftovers):
            report.error(where, f"el resultado no respeta el esquema actual: {problem}")
        for path in leftovers:
            report.error(where, f"`{path}` quedaría sin migrar y se perdería (el servicio descarta lo que el esquema no conoce); muévelo o bórralo")


def check_schema(schema, report: Report) -> None:
    if not isinstance(schema, dict):
        report.error("DataSchema.json", "debe ser un objeto")
        return
    if schema.get("schemaVersion") != 1:
        report.error("schemaVersion", "debe ser 1")
    check_document(schema, report)
    check_sections(schema.get("sections"), "sections", report)
    check_migrations(schema, report)
    sections = schema.get("sections") if isinstance(schema.get("sections"), dict) else {}
    valid = {name: section for name, section in sections.items() if isinstance(section, dict) and isinstance(section.get("fields"), dict)}
    if valid and not any(section.get("role") == "meta" for section in valid.values()):
        report.warn("sections", "falta la sección meta (firstJoinAt, lastJoinAt, sessions, playTimeSec) con dueño PlayerData")
    if not report.errors:
        sizes = {name: max_size(section_spec(section)) + len(name) + 4 for name, section in valid.items()}
        total = sum(sizes.values()) + DOCUMENT_OVERHEAD
        document = schema.get("document") or {}
        budget = document.get("budget") if is_int(document.get("budget")) else DEFAULT_BUDGET
        biggest = max(sizes, key=sizes.get) if sizes else "—"
        detail = (f"{spanish(total)} caracteres en el peor caso ({percent(total / KEY_LIMIT)} del límite por clave); "
                  f"la sección que más pesa es {biggest}")
        if total > KEY_LIMIT:
            report.error("tamaño", f"{detail}: baja maxEntries, maxItems o maxLength")
        elif total > budget:
            report.warn("tamaño", f"{detail}: pasa el presupuesto de {spanish(budget)}; baja los límites o súbelo en document.budget explicando por qué")
        else:
            report.note("tamaño", detail)


def spec_at(sections: dict, path: str) -> dict | None:
    """Campo del esquema en una ruta sección.campo.subcampo (por * o por clave dentro de mapas)."""
    parts = split_path(path)
    if not parts or parts[0] not in sections or not isinstance(sections[parts[0]], dict):
        return None
    spec: dict | None = section_spec(sections[parts[0]])
    for part in parts[1:]:
        if spec is None:
            return None
        if spec.get("type") == "record":
            spec = (spec.get("fields") or {}).get(part)
        elif spec.get("type") == "map":
            spec = spec.get("value")
        else:
            return None
    return spec if isinstance(spec, dict) else None


# --- Juego ---------------------------------------------------------------------

def read_frontmatter(text: str) -> dict:
    builder = load_sibling(BUILDER_SCRIPTS / "check_game.py", "factory_check_game")
    if builder is not None:
        return builder.read_frontmatter(text)
    import yaml  # sin el builder al lado, se necesita PyYAML

    match = re.match(r"^---\n(.*?)\n---", text.lstrip("﻿"), re.DOTALL)
    data = yaml.safe_load(match.group(1)) if match else None
    if not isinstance(data, dict):
        raise ValueError("falta el frontmatter entre líneas ---")
    return data


def promise_paths(doc_text: str) -> list[str] | None:
    """Rutas de la tabla "Promesas del GDD" de DATA.md (segunda columna). None si no está."""
    heading = re.search(r"^#{2,4}[ \t]+Promesas del GDD[ \t]*$", doc_text, re.M)
    if not heading:
        return None
    paths: list[str] = []
    header_seen = False
    for line in doc_text[heading.end():].split("\n"):
        stripped = line.strip()
        if stripped.startswith("#"):
            break
        if not stripped.startswith("|"):
            if header_seen and not stripped:
                break
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if not header_seen:
            header_seen = True
            continue
        if all(set(cell) <= set("-: ") for cell in cells) or len(cells) < 2:
            continue
        paths += re.findall(r"`([^`]+)`", cells[1])
    return paths


def strip_luau_comments(code: str) -> str:
    builder = load_sibling(BUILDER_SCRIPTS / "check_game.py", "factory_check_game")
    if builder is not None:
        return builder.strip_comments(code)
    code = re.sub(r"--\[(=*)\[.*?\]\1\]", "", code, flags=re.S)
    return re.sub(r"--[^\n]*", "", code)


def check_service(game: Path, schema: dict, report: Report) -> None:
    """Plantillas del servicio de datos, Migrations.luau y DataTypes.luau."""
    data_dir = game / DATA_DIR
    present = [name for name in SERVICE_FILES if (data_dir / name).exists()]
    if not present:
        report.note("servicio", "el juego todavía no tiene el servicio de datos: el builder copia las plantillas a src/server/Data/")
    else:
        for name in SERVICE_FILES:
            copy = data_dir / name
            template = TEMPLATES / name
            if not copy.exists():
                report.error((DATA_DIR / name).as_posix(), "falta; copia todas las plantillas del servicio de datos")
            elif template.exists() and copy.read_text(encoding="utf-8").replace("\r\n", "\n") != template.read_text(encoding="utf-8").replace("\r\n", "\n"):
                report.warn((DATA_DIR / name).as_posix(), "difiere de la plantilla de roblox-data-architect; cópiala sin cambios")
    customs = sorted({op.get("name") for migration in schema.get("migrations") or [] if isinstance(migration, dict)
                      for op in migration.get("ops") or [] if isinstance(op, dict) and op.get("op") == "custom" and op.get("name")})
    migrations = game / MIGRATIONS_PATH
    if customs or present:
        if not migrations.exists():
            report.error(MIGRATIONS_PATH.as_posix(), "falta; copia la plantilla y agrega una función por cada operación custom")
        else:
            code = strip_luau_comments(migrations.read_text(encoding="utf-8"))
            for name in customs:
                if not re.search(rf"\bfunction\s+Migrations\.{re.escape(name)}\s*\(|\bMigrations\.{re.escape(name)}\s*=(?!=)", code):
                    report.error(MIGRATIONS_PATH.as_posix(), f"falta la función Migrations.{name} de la operación custom")
    generator = load_sibling(Path(__file__).resolve().parent / "gen_types.py", "factory_gen_types")
    types_path = game / TYPES_PATH
    if generator is not None:
        if not types_path.exists():
            report.warn(TYPES_PATH.as_posix(), "falta; genéralo con gen_types.py para tipar las fachadas de los cores")
        elif types_path.read_text(encoding="utf-8").replace("\r\n", "\n") != generator.generate(schema):
            report.warn(TYPES_PATH.as_posix(), "está desactualizado; vuelve a correr gen_types.py")


def check_access(game: Path, sections: dict, layers, report: Report) -> None:
    """Cada PlayerData.section(…, "x") está en el core dueño de la sección x."""
    src = game / "src"
    if not src.is_dir():
        return
    for path in sorted(src.rglob("*.luau")):
        relative = path.relative_to(src)
        if relative.parts[:2] == ("server", "Data"):
            continue
        code = strip_luau_comments(path.read_text(encoding="utf-8"))
        unit = layers.unit_of(relative.parts) if layers is not None else None
        for match in SECTION_CALL_RE.finditer(code):
            name = match.group(2)
            where = f"{path.relative_to(game).as_posix()}:{code.count(chr(10), 0, match.start()) + 1}"
            section = sections.get(name)
            if not isinstance(section, dict):
                report.error(where, f"la sección {name} no existe en DataSchema.json")
                continue
            owner = section.get("owner")
            if unit is None:
                continue
            if unit.kind != "module":
                report.error(where, f"{unit.label()} usa la sección {name}; solo la usa su core dueño ({owner}), los demás llaman a su API")
            elif unit.name != owner:
                report.error(where, f"el core {unit.name} usa la sección {name}, que es de {owner}: llama a la API de {owner}")


def check_game(game: Path) -> Report:
    report = Report()
    schema_path = game / SCHEMA_PATH
    doc_path = game / DOC_PATH
    schema = None
    if not schema_path.exists():
        report.error(SCHEMA_PATH.as_posix(), "no existe")
    else:
        try:
            schema = json.loads(schema_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            report.error(SCHEMA_PATH.as_posix(), f"JSON inválido: {exc}")
        else:
            check_schema(schema, report)
    sections = schema.get("sections") if isinstance(schema, dict) and isinstance(schema.get("sections"), dict) else {}
    persistence = (schema.get("document") or {}).get("persistence") if isinstance(schema, dict) else None

    # GDD
    gdd_path = game / "GDD.md"
    frontmatter: dict = {}
    gdd_text = ""
    if not gdd_path.exists():
        report.warn("GDD.md", "no existe; no se comprobaron la persistencia, el modo ni la monetización")
    else:
        gdd_text = gdd_path.read_text(encoding="utf-8")
        try:
            frontmatter = read_frontmatter(gdd_text)
        except Exception as exc:  # errores de YAML o sin frontmatter
            report.warn("GDD.md", f"no se pudo leer el frontmatter ({exc})")
    if frontmatter:
        design = frontmatter.get("design") if isinstance(frontmatter.get("design"), dict) else {}
        data = frontmatter.get("data") if isinstance(frontmatter.get("data"), dict) else {}
        project = frontmatter.get("project") if isinstance(frontmatter.get("project"), dict) else {}
        liveops = frontmatter.get("liveops") if isinstance(frontmatter.get("liveops"), dict) else {}
        monetization = frontmatter.get("monetization") if isinstance(frontmatter.get("monetization"), dict) else {}
        if design.get("data") is not True:
            report.warn("GDD.md", "el frontmatter no activa design.data")
        declared = data.get("persistence")
        if declared is None:
            report.warn("GDD.md", f"agrega data.persistence: {persistence or 'persistent'} al frontmatter")
        elif persistence in PERSISTENCE and declared != persistence:
            report.error("GDD.md", f"data.persistence es {declared!r} y el esquema dice {persistence!r}")
        if persistence == "memory":
            if liveops.get("enabled") is True:
                report.error("persistencia", "LiveOps necesita persistent: lo que da un evento tiene que guardarse")
            if project.get("mode") == "release-candidate":
                report.warn("persistencia", "un release-candidate que promete progreso usa persistent")
        enabled = monetization.get("enabled") if isinstance(monetization.get("enabled"), list) else []
        if "developer-products" in enabled and not any(isinstance(s, dict) and s.get("role") == "purchases" for s in sections.values()):
            report.error("compras", "con developer-products hace falta una sección con role purchases que registre los PurchaseId procesados")

    # Dueños contra el Mapa de módulos
    layers = load_sibling(BUILDER_SCRIPTS / "check_modules.py", "factory_check_modules")
    rows = layers.module_map(gdd_text) if layers is not None and gdd_text else None
    owners = {name: s.get("owner") for name, s in sections.items() if isinstance(s, dict) and isinstance(s.get("owner"), str)}
    if rows is None:
        if any(owner != SERVICE_OWNER for owner in owners.values()):
            report.note("dueños", "el GDD todavía no tiene Mapa de módulos; los dueños se comprueban cuando el builder lo escriba")
    else:
        for name, owner in sorted(owners.items()):
            if owner == SERVICE_OWNER:
                continue
            row = rows.get(owner)
            if row is None:
                report.warn("dueños", f"la sección {name} es del core {owner}, que no está en el Mapa de módulos: pídeselo al builder")
            elif row["layer"] != "core":
                report.error("dueños", f"la sección {name} es de {owner}, que no es un core (capa {row['layer'] or 'sin capa'})")
            elif "data" in row and name not in row["data"]:
                report.warn("dueños", f"en el Mapa de módulos, la columna de datos de {owner} no nombra la sección {name}")

    if isinstance(schema, dict) and sections:
        check_service(game, schema, report)
        check_access(game, sections, layers, report)

    # DATA.md
    if not doc_path.exists():
        report.error(DOC_PATH.as_posix(), "no existe; usa la plantilla de references/data-doc-template.md")
    else:
        doc_text = doc_path.read_text(encoding="utf-8")
        paths = promise_paths(doc_text)
        if paths is None:
            report.warn(DOC_PATH.as_posix(), "falta la tabla \"Promesas del GDD\": qué se promete conservar y dónde se guarda")
        else:
            if not paths and persistence == "persistent":
                report.warn(DOC_PATH.as_posix(), "la tabla \"Promesas del GDD\" no nombra ningún campo")
            for path in paths:
                if sections and spec_at(sections, path) is None:
                    report.error(DOC_PATH.as_posix(), f"la promesa apunta a `{path}`, que no existe en el esquema")
        for name in sorted(sections):
            if f"`{name}`" not in doc_text:
                report.warn(DOC_PATH.as_posix(), f"no explica la sección `{name}`")
    return report


def check_file(path: Path) -> Report:
    report = Report()
    try:
        schema = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        report.error(path.name, f"JSON inválido: {exc}")
        return report
    check_schema(schema, report)
    return report


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa el diseño de los datos guardados del jugador.")
    parser.add_argument("target", type=Path, help="carpeta del juego o un DataSchema.json")
    parser.add_argument("--json", action="store_true", help="imprime el resultado como JSON")
    args = parser.parse_args(argv)
    if args.target.is_dir():
        report = check_game(args.target.resolve())
    elif args.target.is_file():
        report = check_file(args.target)
    else:
        print(f"ERROR no existe {args.target}")
        return 2
    if args.json:
        print(json.dumps({"errors": report.errors, "warnings": report.warnings, "info": report.info},
                         ensure_ascii=False, indent=2))
    else:
        print(f"Datos del jugador: {args.target}")
        for line in report.errors:
            print(f"ERROR {line}")
        for line in report.warnings:
            print(f"WARN  {line}")
        for line in report.info:
            print(f"INFO  {line}")
        print(f"Resultado: {len(report.errors)} errores, {len(report.warnings)} advertencias, {len(report.info)} notas")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
