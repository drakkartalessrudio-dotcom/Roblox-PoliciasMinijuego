#!/usr/bin/env python3
"""Revisa un juego de la fábrica contra el contrato del builder.

Uso:
    python check_game.py <carpeta-del-juego>
    python check_game.py <carpeta-del-juego> --json

Comprueba:
  - estructura: GDD.md con frontmatter válido, default.project.json, README.md;
  - módulos activados en el GDD y sus artefactos (niveles, arte, interfaz, pase de
    arte, datos del jugador, analíticas, LiveOps);
  - puntos de enganche: Tuning, Telemetry, LevelLoader, Style y EnvironmentLoader con
    la API de las plantillas;
  - Levels.json, Theme.json, la UI y Environment.json con los validadores de sus
    skills, si están instalados al lado;
  - con varios places: Places.json contra el GDD, Place y Travel, un proyecto de
    Rojo por place con su PlaceKey y las mismas carpetas compartidas, y el place
    de cada nivel;
  - reglas de código que suelen romper juegos: rutas de Tuning.get que no existen en
    Config, requires a módulos inexistentes, APIs de servidor en el cliente,
    LocalPlayer en el servidor, funciones obsoletas, IDs de assets que el GDD no
    declara y más de un ProcessReceipt;
  - las capas de módulos (núcleo, cores, puentes y Game) con check_modules.py.

Es un análisis estático heurístico: no ejecuta el juego ni reemplaza la prueba en
Studio. Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - depende del entorno
    yaml = None

MODES = {"prototype", "release-candidate"}
PLATFORMS = {"desktop", "mobile", "tablet", "console", "vr"}
MONETIZATION_KEYS = {"developer-products", "game-passes", "creator-rewards", "avatar-ugc"}
TELEMETRY_API = ["onboarding", "funnel", "progressionStart", "progressionComplete", "progressionFail", "economy", "custom"]
LEVELLOADER_API = ["build", "applyPhysics", "applyToHumanoid", "standCFrame"]
STYLE_API = ["color", "font", "material", "metric", "applyLighting"]
ENVIRONMENTLOADER_API = ["apply"]
PLACE_API = ["start", "current", "info", "role", "id", "all", "levels"]
TRAVEL_API = ["to", "toStart", "arrival", "onBeforeTravel"]
PLACE_ROLES = {"start", "match", "area"}
PLACE_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")
SHARED_NODES = [("ReplicatedStorage", "Shared"), ("ServerScriptService", "Server"), ("StarterPlayer", "StarterPlayerScripts", "Client")]
CLIENT_FORBIDDEN = ["DataStoreService", "ServerStorage", "ServerScriptService", "MessagingService", "MemoryStoreService"]
PHYSICS_KEYS = {"walkspeed", "jumpheight", "jumppower", "gravity"}
SKILLS_DIR = Path(__file__).resolve().parents[2]
LEVEL_VALIDATOR = SKILLS_DIR / "roblox-level-designer" / "scripts" / "validate_levels.py"
ANALYTICS_CHECKER = SKILLS_DIR / "roblox-analytics-dev" / "scripts" / "check_analytics.py"
LIVEOPS_CHECKER = SKILLS_DIR / "roblox-liveops" / "scripts" / "check_liveops.py"
ART_CHECKER = SKILLS_DIR / "roblox-art-director" / "scripts" / "check_art.py"
UI_CHECKER = SKILLS_DIR / "roblox-ui-designer" / "scripts" / "check_ui.py"
ENVIRONMENT_CHECKER = SKILLS_DIR / "roblox-environment-artist" / "scripts" / "check_environment.py"
MODULES_CHECKER = Path(__file__).resolve().parent / "check_modules.py"
DATA_CHECKER = SKILLS_DIR / "roblox-data-architect" / "scripts" / "check_data.py"


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


# --- Frontmatter -------------------------------------------------------------

def _scalar(value: str):
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        return [_scalar(item) for item in value[1:-1].split(",") if item.strip()]
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    lowered = value.lower()
    if lowered in {"true", "false"}:
        return lowered == "true"
    if lowered in {"null", "~", ""}:
        return None
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        return value


def _strip_yaml_comment(line: str) -> str:
    quote = None
    for index, char in enumerate(line):
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "#" and (index == 0 or line[index - 1] in " \t"):
            return line[:index]
    return line


def mini_yaml(text: str) -> dict:
    """Subconjunto de YAML suficiente para el frontmatter del GDD: mapas anidados,
    escalares y listas en línea. Se usa solo si PyYAML no está instalado."""
    root: dict = {}
    stack: list[tuple[int, dict]] = [(-1, root)]
    for raw in text.split("\n"):
        line = _strip_yaml_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        key, separator, value = line.strip().partition(":")
        if not separator or not key.strip():
            raise ValueError(f"línea no válida: {raw.strip()!r}")
        while indent <= stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if value.strip() == "":
            child: dict = {}
            parent[key.strip()] = child
            stack.append((indent, child))
        else:
            parent[key.strip()] = _scalar(value)
    return root


def read_frontmatter(text: str) -> dict:
    text = text.lstrip("﻿")
    match = re.match(r"^---\n(.*?)\n---[ \t]*(?:\n|$)", text, re.DOTALL)
    if not match:
        raise ValueError("falta el frontmatter entre líneas ---")
    raw = match.group(1)
    data = yaml.safe_load(raw) if yaml is not None else mini_yaml(raw)
    if not isinstance(data, dict):
        raise ValueError("el frontmatter debe ser un mapa")
    return data


# --- Luau ---------------------------------------------------------------------

def _long_bracket_end(code: str, start: int) -> int | None:
    """Si en start hay un corchete largo ([[ o [==[), devuelve el índice tras su cierre."""
    match = re.match(r"\[(=*)\[", code[start:])
    if not match:
        return None
    closing = "]" + match.group(1) + "]"
    end = code.find(closing, start + match.end())
    return len(code) if end == -1 else end + len(closing)


def _string_end(code: str, start: int) -> int:
    quote = code[start]
    index = start + 1
    while index < len(code):
        char = code[index]
        if char == "\\":
            index += 2
            continue
        if char == quote or (char == "\n" and quote != "`"):
            return index + 1
        index += 1
    return index


def strip_comments(code: str) -> str:
    """Quita comentarios de Luau y conserva strings y saltos de línea."""
    out: list[str] = []
    index = 0
    while index < len(code):
        char = code[index]
        if code.startswith("--", index):
            end = _long_bracket_end(code, index + 2)
            if end is None:
                newline = code.find("\n", index)
                index = len(code) if newline == -1 else newline
            else:
                out.append("\n" * code.count("\n", index, end))
                index = end
            continue
        if char in "\"'`":
            end = _string_end(code, index)
            out.append(code[index:end])
            index = end
            continue
        if char == "[":
            end = _long_bracket_end(code, index)
            if end is not None:
                out.append(code[index:end])
                index = end
                continue
        out.append(char)
        index += 1
    return "".join(out)


def _skip_ws(code: str, index: int) -> int:
    while index < len(code) and code[index] in " \t\r\n":
        index += 1
    return index


def _skip_expression(code: str, index: int) -> int:
    """Avanza hasta el fin de un valor de tabla: ',', ';' o '}' al mismo nivel."""
    depth = 0
    while index < len(code):
        char = code[index]
        if char in "\"'`":
            index = _string_end(code, index)
            continue
        if char == "[":
            end = _long_bracket_end(code, index)
            if end is not None:
                index = end
                continue
        if char in "({[":
            depth += 1
        elif char in ")]}":
            if depth == 0:
                return index
            depth -= 1
        elif char in ",;" and depth == 0:
            return index
        index += 1
    return index


KEY_RE = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)|\[\s*([\"'])(.*?)\2\s*\]\s*=(?!=)")


NUMBER_RE = re.compile(r"^-?(?:0x[0-9A-Fa-f_]+|[0-9_]*\.?[0-9_]+(?:[eE][-+]?\d+)?)$")


def literal_type(expression: str) -> str:
    """Tipo de un valor literal de Luau: number, string, boolean u other."""
    expression = expression.strip()
    if NUMBER_RE.match(expression):
        return "number"
    if expression in {"true", "false"}:
        return "boolean"
    if expression[:1] in {'"', "'", "`"} or re.match(r"^\[=*\[", expression):
        return "string"
    return "other"


def parse_table(code: str, index: int) -> tuple[dict, int]:
    """Lee un constructor de tabla desde '{' y devuelve sus claves y el índice tras '}'.
    Cada hoja guarda el tipo de su valor literal (number, string, boolean u other)."""
    keys: dict = {}
    index += 1
    while index < len(code):
        index = _skip_ws(code, index)
        if index >= len(code):
            break
        if code[index] == "}":
            return keys, index + 1
        match = KEY_RE.match(code, index)
        if match:
            key = match.group(1) or match.group(3)
            index = _skip_ws(code, match.end())
            if index < len(code) and code[index] == "{":
                keys[key], index = parse_table(code, index)
            else:
                end = _skip_expression(code, index)
                keys[key] = literal_type(code[index:end])
                index = end
        else:
            index = _skip_expression(code, index)
        index = _skip_ws(code, index)
        if index < len(code) and code[index] in ",;":
            index += 1
    raise ValueError("tabla sin cerrar")


def config_keys(code: str) -> dict | None:
    """Claves de Config.luau. None si no se reconoce la tabla principal."""
    code = strip_comments(code)
    match = re.search(r"\blocal\s+Config\s*(?::[^=]+)?=\s*\{", code) or re.search(r"\breturn\s*\{", code)
    if not match:
        return None
    keys, _ = parse_table(code, match.end() - 1)
    for assignment in re.finditer(r"\bConfig((?:\.[A-Za-z_]\w*)+)\s*=(?!=)\s*", code):
        parts = assignment.group(1).strip(".").split(".")
        node = keys
        for part in parts[:-1]:
            if not isinstance(node.get(part), dict):
                node[part] = {}
            node = node[part]
        end = assignment.end()
        if end < len(code) and code[end] == "{":
            node[parts[-1]], _ = parse_table(code, end)
        else:
            # Una asignación termina en el fin de línea, no en una coma.
            node[parts[-1]] = literal_type(code[end:_skip_expression(code, end)].split("\n", 1)[0])
    return keys


def leaf_type(keys: dict, path: str) -> str | None:
    """Tipo literal de la hoja en la ruta, "table" si es una tabla, o None si no existe."""
    node = keys
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return "table" if isinstance(node, dict) else node


def path_exists(keys: dict, path: str) -> bool:
    node = keys
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return False
        node = node[part]
    return True


def all_keys(keys: dict) -> set[str]:
    found: set[str] = set()
    for key, value in keys.items():
        found.add(key.lower())
        if isinstance(value, dict):
            found |= all_keys(value)
    return found


def module_names(src: Path) -> set[str]:
    names: set[str] = set()
    for path in src.rglob("*"):
        if not path.is_file():
            continue
        name = path.name
        if name in {"init.luau", "init.lua", "init.server.luau", "init.client.luau"}:
            names.add(path.parent.name)
        elif name.endswith((".server.luau", ".client.luau", ".server.lua", ".client.lua")):
            names.add(name.split(".")[0])
        elif path.suffix in {".luau", ".lua"} or (path.suffix == ".json" and not name.endswith((".meta.json", ".model.json", ".project.json"))):
            names.add(path.stem)
    return names


REQUIRE_RE = re.compile(r"\brequire\s*\(")


def require_targets(code: str) -> list[str]:
    """Último nombre de cada require(...) que apunta a una instancia por nombre."""
    targets = []
    for match in REQUIRE_RE.finditer(code):
        start = match.end()
        depth, index = 1, start
        while index < len(code) and depth:
            if code[index] in "\"'`":
                index = _string_end(code, index)
                continue
            depth += {"(": 1, ")": -1}.get(code[index], 0)
            index += 1
        expression = code[start:index - 1].strip()
        if re.fullmatch(r"\d+", expression):
            targets.append(f"#{expression}")
            continue
        names = [(m.start(), m.group(1)) for m in re.finditer(r"\.([A-Za-z_]\w*)", expression)]
        names += [(m.start(), m.group(2)) for m in re.finditer(r":(?:WaitForChild|FindFirstChild)\(\s*([\"'])(\w+)\1", expression)]
        names = [(pos, name) for pos, name in names if name not in {"Parent", "WaitForChild", "FindFirstChild"}]
        if names:
            targets.append(max(names)[1])
    return targets


# --- Comprobaciones ------------------------------------------------------------

def side_of(path: Path, src: Path) -> str:
    rel = path.relative_to(src).parts
    name = path.name
    if name.endswith((".client.luau", ".client.lua")) or rel[0] == "client":
        return "client"
    if name.endswith((".server.luau", ".server.lua")) or rel[0] == "server":
        return "server"
    return "shared"


def load_sibling(path: Path, name: str):
    """Carga el script de otro skill instalado al lado del builder, o None si no está."""
    if not path.exists():
        return None
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module  # dataclasses necesita el módulo registrado al cargarse
    try:
        spec.loader.exec_module(module)
    except Exception:
        del sys.modules[name]
        raise
    return module


def load_level_validator():
    return load_sibling(LEVEL_VALIDATOR, "factory_validate_levels")


def check_structure(game: Path, report: Report) -> dict:
    frontmatter: dict = {}
    gdd = game / "GDD.md"
    if not gdd.exists():
        report.error("GDD.md", "no existe")
    else:
        try:
            frontmatter = read_frontmatter(gdd.read_text(encoding="utf-8"))
        except (ValueError, UnicodeDecodeError) as exc:
            report.error("GDD.md", f"frontmatter inválido: {exc}")
        except Exception as exc:  # errores de YAML
            report.error("GDD.md", f"frontmatter inválido: {exc}")
    if not (game / "README.md").exists():
        report.warn("README.md", "no existe; explica cómo abrir, jugar y ajustar el juego")

    project_path = game / "default.project.json"
    if not project_path.exists():
        report.error("default.project.json", "no existe")
    else:
        try:
            project = json.loads(project_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            report.error("default.project.json", f"JSON inválido: {exc}")
        else:
            if project.get("name") in {None, "", "RobloxGame"}:
                report.warn("default.project.json", "cambia 'name' por el nombre del juego")
            paths = []

            def collect(node):
                if isinstance(node, dict):
                    for key, value in node.items():
                        if key == "$path" and isinstance(value, str):
                            paths.append(value)
                        else:
                            collect(value)

            collect(project.get("tree", {}))
            for path in paths:
                if not (game / path).exists():
                    report.error("default.project.json", f"$path '{path}' no existe")
    return frontmatter


def read_places(places, report: Report) -> list[dict]:
    """project.places: 1 (un solo place) o una lista de {id, role, maxPlayers}."""
    if isinstance(places, bool) or not isinstance(places, (int, list)):
        report.error("GDD.md", "project.places debe ser 1 o una lista de places con id y role")
        return []
    if isinstance(places, int):
        if places < 1:
            report.error("GDD.md", "project.places debe ser 1 o más")
        elif places > 1:
            report.warn("GDD.md", "project.places es un número; con varios places descríbelos como lista (id, role, maxPlayers)")
        return []
    entries, seen, starts = [], set(), 0
    for index, entry in enumerate(places):
        where = f"project.places[{index}]"
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str) or not PLACE_KEY_RE.match(entry["id"]):
            report.error("GDD.md", f"{where} necesita 'id' con letras, números, _ o -")
            continue
        if entry["id"] in seen:
            report.error("GDD.md", f"{where}: id de place repetido '{entry['id']}'")
            continue
        seen.add(entry["id"])
        if entry.get("role") not in PLACE_ROLES:
            report.error("GDD.md", f"{where}: 'role' debe ser start, match o area")
        starts += entry.get("role") == "start"
        players = entry.get("maxPlayers")
        if players is not None and (not isinstance(players, int) or isinstance(players, bool) or players < 1):
            report.error("GDD.md", f"{where}: 'maxPlayers' debe ser un entero mayor que 0")
        entries.append(entry)
    if entries and starts != 1:
        report.error("GDD.md", "project.places necesita exactamente un place con role start (la entrada de la experiencia)")
    return entries


def project_tree(path: Path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None
    return data.get("tree") if isinstance(data, dict) and isinstance(data.get("tree"), dict) else None


def node_at(tree: dict, names) -> dict | None:
    node = tree
    for name in names:
        node = node.get(name) if isinstance(node, dict) else None
    return node if isinstance(node, dict) else None


def project_place_key(tree: dict) -> str | None:
    node = node_at(tree, ("ReplicatedStorage", "PlaceKey"))
    value = ((node or {}).get("$properties") or {}).get("Value")
    if isinstance(value, dict):
        value = value.get("String")
    return value if isinstance(value, str) else None


def check_places(game: Path, src: Path, flags: dict, sources: dict, gdd_text: str, levels_data, report: Report) -> None:
    places = flags["places"]
    registry_path = src / "shared" / "Places.json"
    if len(places) <= 1:
        if registry_path.exists():
            report.warn("places", "src/shared/Places.json existe pero el GDD declara un solo place")
        return
    keys = [place["id"] for place in places]
    roles = {place["id"]: place.get("role") for place in places}
    start = next((key for key, role in roles.items() if role == "start"), None)

    # Registro de places
    if not registry_path.exists():
        report.error("places", "falta src/shared/Places.json con los places del GDD (start y places con placeId y role)")
    else:
        try:
            registry = json.loads(registry_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            report.error("places", f"src/shared/Places.json: JSON inválido: {exc}")
            registry = {}
        entries = registry.get("places") if isinstance(registry, dict) and isinstance(registry.get("places"), dict) else {}
        if registry.get("start") != start:
            report.error("places", f"Places.json: 'start' debe ser '{start}', el place con role start del GDD")
        for key in sorted(set(keys) - set(entries)):
            report.error("places", f"Places.json no tiene el place '{key}' del GDD")
        for key in sorted(set(entries) - set(keys)):
            report.error("places", f"Places.json tiene el place '{key}', que el GDD no declara")
        pending = []
        for key, entry in entries.items():
            if not isinstance(entry, dict):
                report.error("places", f"Places.json: '{key}' debe ser un objeto")
                continue
            if key in roles and entry.get("role") != roles[key]:
                report.error("places", f"Places.json: el role de '{key}' debe ser {roles[key]} como en el GDD")
            place_id = entry.get("placeId")
            if not isinstance(place_id, int) or isinstance(place_id, bool) or place_id < 0:
                report.error("places", f"Places.json: placeId de '{key}' debe ser un entero (0 mientras esté pendiente)")
            elif place_id == 0:
                pending.append(key)
            elif str(place_id) not in gdd_text:
                report.error("places", f"Places.json: el PlaceId {place_id} de '{key}' no está en el GDD; no inventes IDs: los carga el usuario")
        if pending:
            report.warn("places", f"PlaceId pendiente en {', '.join(sorted(pending))}: el usuario crea cada place en la experiencia "
                                  "(Publicar como → Agregar como place nuevo) y carga su ID en Places.json y en el GDD")

    # Plantillas
    for path, api, module in ((src / "shared" / "Place.luau", PLACE_API, "Place"), (src / "server" / "Travel.luau", TRAVEL_API, "Travel")):
        if not path.exists():
            report.error("places", f"falta {path.relative_to(game).as_posix()}; cópialo de assets/templates del builder")
            continue
        defined = set(re.findall(rf"\bfunction\s+{module}\.(\w+)\s*\(", sources.get(path, "")))
        missing = [name for name in api if name not in defined]
        if missing:
            report.error("places", f"{path.relative_to(game).as_posix()}: faltan funciones del contrato: {', '.join(missing)}")

    # Un proyecto de Rojo por place, con las mismas carpetas compartidas
    default_tree = project_tree(game / "default.project.json")
    if default_tree is not None:
        if project_place_key(default_tree) != start:
            report.error("places", f"default.project.json es el place de inicio: necesita ReplicatedStorage.PlaceKey (StringValue) con Value \"{start}\"")
        for key in keys:
            if key == start:
                continue
            path = game / "places" / f"{key}.project.json"
            tree = project_tree(path)
            if tree is None:
                report.error("places", f"falta places/{key}.project.json (o no es un proyecto válido) para el place '{key}'")
                continue
            if project_place_key(tree) != key:
                report.error("places", f"places/{key}.project.json necesita ReplicatedStorage.PlaceKey (StringValue) con Value \"{key}\"")
            for names in SHARED_NODES:
                expected = node_at(default_tree, names)
                if not expected or not isinstance(expected.get("$path"), str):
                    continue
                actual = node_at(tree, names)
                wanted = (game / expected["$path"]).resolve()
                found = (path.parent / actual["$path"]).resolve() if actual and isinstance(actual.get("$path"), str) else None
                if found != wanted:
                    report.error("places", f"places/{key}.project.json debe mapear {'.'.join(names)} a la misma carpeta que default.project.json ({expected['$path']})")
        extra = sorted(p.stem.removesuffix(".project") for p in (game / "places").glob("*.project.json") if p.stem.removesuffix(".project") not in keys)
        if extra:
            report.warn("places", f"places/ tiene proyectos que el GDD no declara: {', '.join(extra)}")

    # Niveles por place
    if isinstance(levels_data, dict):
        without = []
        for level in levels_data.get("levels", []) if isinstance(levels_data.get("levels"), list) else []:
            if not isinstance(level, dict):
                continue
            place = level.get("place")
            if place is None:
                without.append(str(level.get("id")))
            elif place not in keys:
                report.error("places", f"Levels.json: el nivel '{level.get('id')}' pertenece al place '{place}', que el GDD no declara")
        if without:
            report.warn("places", f"niveles sin 'place' ({', '.join(without)}): se construyen en el place de inicio")

    if "Places y viajes" not in gdd_text:
        report.warn("places", "falta la sección \"Places y viajes\" del GDD: qué place hay, cómo se viaja y qué pasa si un viaje falla")
    for path, code in sources.items():
        if path.name != "Travel.luau" and re.search(r"\bTeleportService\b", code):
            report.warn("places", f"{path.relative_to(game).as_posix()} usa TeleportService directamente; usa Travel (reintentos, datos guardados antes de viajar)")
    stores = any(re.search(r"\bDataStoreService\b", code) for code in sources.values())
    if stores and not any(re.search(r"\bUpdateAsync\b", code) for code in sources.values()):
        report.warn("places", "con varios places un jugador se guarda en un servidor y se carga en otro: usa UpdateAsync con bloqueo de sesión")


def check_frontmatter(frontmatter: dict, report: Report) -> dict:
    flags = {"levels": False, "art": False, "ui": False, "environment": False, "data": False, "analytics": False,
             "liveops": False, "monetization": [], "mode": None, "places": []}
    if not frontmatter:
        return flags
    project = frontmatter.get("project")
    if not isinstance(project, dict):
        report.error("GDD.md", "falta el mapa 'project'")
        project = {}
    if not project.get("name"):
        report.error("GDD.md", "falta project.name")
    mode = project.get("mode")
    flags["mode"] = mode
    if mode not in MODES:
        report.error("GDD.md", f"project.mode debe ser prototype o release-candidate (es {mode!r})")
    flags["places"] = read_places(project.get("places", 1), report)
    platforms = project.get("platforms")
    if not isinstance(platforms, list) or not platforms:
        report.warn("GDD.md", "project.platforms debería listar las plataformas objetivo")
    else:
        unknown = [p for p in platforms if p not in PLATFORMS]
        if unknown:
            report.warn("GDD.md", f"plataformas desconocidas: {', '.join(map(str, unknown))}")

    def flag(section: str, key: str) -> bool:
        node = frontmatter.get(section)
        if node is None:
            return False  # un campo ausente vale false
        if not isinstance(node, dict):
            report.error("GDD.md", f"'{section}' debe ser un mapa con '{key}'")
            return False
        value = node.get(key, False)
        if not isinstance(value, bool):
            report.error("GDD.md", f"{section}.{key} debe ser true o false")
            return False
        return value

    flags["levels"] = flag("design", "levels")
    flags["art"] = flag("design", "art")
    flags["ui"] = flag("design", "ui")
    flags["environment"] = flag("design", "environment")
    flags["data"] = flag("design", "data")
    flags["analytics"] = flag("analytics", "enabled")
    flags["liveops"] = flag("liveops", "enabled")
    monetization = frontmatter.get("monetization", {})
    enabled = monetization.get("enabled", []) if isinstance(monetization, dict) else None
    if not isinstance(enabled, list):
        report.error("GDD.md", "monetization.enabled debe ser una lista")
        enabled = []
    unknown = [m for m in enabled if m not in MONETIZATION_KEYS]
    if unknown:
        report.error("GDD.md", f"monetization.enabled tiene claves desconocidas: {', '.join(map(str, unknown))}")
    flags["monetization"] = [m for m in enabled if m in MONETIZATION_KEYS]
    if flags["liveops"] and mode == "prototype":
        report.warn("GDD.md", "liveops.enabled en un prototype: LiveOps requiere persistencia y operación")
    return flags


def check_game(game: Path) -> Report:
    report = Report()
    frontmatter = check_structure(game, report)
    flags = check_frontmatter(frontmatter, report)
    src = game / "src"
    if not src.is_dir():
        report.error("src", "no existe la carpeta src/")
        return report

    files = sorted(p for p in src.rglob("*") if p.is_file() and p.suffix in {".luau", ".lua"})
    sources = {p: strip_comments(p.read_text(encoding="utf-8")) for p in files}
    modules = module_names(src)
    gdd_text = (game / "GDD.md").read_text(encoding="utf-8") if (game / "GDD.md").exists() else ""

    def rel(path: Path) -> str:
        return path.relative_to(game).as_posix()

    # Puntos de enganche
    tuning = src / "shared" / "Tuning.luau"
    telemetry = src / "server" / "Telemetry.luau"
    if not tuning.exists():
        report.error("src/shared/Tuning.luau", "falta; cópialo de assets/templates del builder")
    elif not re.search(r"\bfunction\s+Tuning\.get\s*\(", sources.get(tuning, "")):
        report.error(rel(tuning), "no define Tuning.get")
    if not telemetry.exists():
        report.error("src/server/Telemetry.luau", "falta; cópialo de assets/templates del builder")
    else:
        defined = set(re.findall(r"\bfunction\s+Telemetry\.(\w+)\s*\(", sources.get(telemetry, "")))
        missing = [name for name in TELEMETRY_API if name not in defined]
        if missing:
            report.error(rel(telemetry), f"faltan funciones del contrato: {', '.join(missing)}")

    # Config y rutas de Tuning
    config_path = src / "shared" / "Config.luau"
    keys = None
    if not config_path.exists():
        report.error("src/shared/Config.luau", "no existe")
    else:
        try:
            keys = config_keys(config_path.read_text(encoding="utf-8"))
        except ValueError as exc:
            report.warn(rel(config_path), f"no se pudo analizar ({exc}); no se verificaron las rutas de Tuning")
        if keys is None and config_path.exists():
            report.warn(rel(config_path), "no se encontró la tabla Config; no se verificaron las rutas de Tuning")
    tuning_calls = 0
    for path, code in sources.items():
        for match in re.finditer(r"\bTuning\.get\(\s*([\"'])([^\"']+)\1\s*\)", code):
            tuning_calls += 1
            if keys is not None and not path_exists(keys, match.group(2)):
                report.error(rel(path), f"Tuning.get(\"{match.group(2)}\") no existe en Config")
    if tuning_calls == 0:
        report.warn("src", "ningún archivo lee valores con Tuning.get")

    # Niveles
    levels_json = src / "shared" / "Levels.json"
    level_loader = src / "server" / "LevelLoader.luau"
    if flags["levels"]:
        if not (game / "design" / "LEVELS.md").exists():
            report.error("design/LEVELS.md", "no existe y el GDD activa design.levels")
        if not levels_json.exists():
            report.error("src/shared/Levels.json", "no existe y el GDD activa design.levels")
    elif levels_json.exists():
        report.warn("src/shared/Levels.json", "existe pero el GDD no activa design.levels")
    if levels_json.exists():
        if not level_loader.exists():
            report.error("src/server/LevelLoader.luau", "falta; con Levels.json el mundo se construye con la plantilla de assets/templates")
        else:
            defined = set(re.findall(r"\bfunction\s+LevelLoader\.(\w+)\s*\(", sources.get(level_loader, "")))
            missing = [name for name in LEVELLOADER_API if name not in defined]
            if missing:
                report.error(rel(level_loader), f"faltan funciones del contrato: {', '.join(missing)}")
            if not any("LevelLoader" in require_targets(code) for path, code in sources.items() if path != level_loader):
                report.warn(rel(level_loader), "ningún script lo requiere; el mundo no se construye desde Levels.json")
        try:
            levels_data = json.loads(levels_json.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            report.error(rel(levels_json), f"JSON inválido: {exc}")
        else:
            validator = load_level_validator()
            if validator is None:
                report.warn(rel(levels_json), "roblox-level-designer no está instalado al lado del builder; no se validaron los saltos")
            else:
                result = validator.validate(levels_data)
                for message in result.errors:
                    report.error(rel(levels_json), message)
                for message in result.warnings:
                    report.warn(rel(levels_json), message)
        if keys and all_keys(keys) & PHYSICS_KEYS:
            report.warn(rel(config_path), "Config repite valores de física; la fuente única es Levels.json")

    # Dirección de arte
    theme_path = src / "shared" / "Theme.json"
    style_path = src / "shared" / "Style.luau"
    if flags["art"] and not theme_path.exists():
        report.warn("src/shared/Theme.json", "pendiente: design.art requiere roblox-art-director")
    elif theme_path.exists() and not flags["art"]:
        report.warn("src/shared/Theme.json", "existe pero el GDD no activa design.art")
    if theme_path.exists():
        if not style_path.exists():
            report.error("src/shared/Style.luau", "falta; con Theme.json el juego lee el tema con la plantilla de assets/templates")
        else:
            defined = set(re.findall(r"\bfunction\s+Style\.(\w+)\s*\(", sources.get(style_path, "")))
            missing = [name for name in STYLE_API if name not in defined]
            if missing:
                report.error(rel(style_path), f"faltan funciones del contrato: {', '.join(missing)}")
        checker = load_sibling(ART_CHECKER, "factory_check_art")
        if checker is None:
            report.warn(rel(theme_path), "roblox-art-director no está instalado al lado del builder; no se revisaron contrastes ni legibilidad")
        else:
            art = checker.check_game(game)
            for message in art.errors:
                report.error("arte", message)
            for message in art.warnings:
                report.warn("arte", message)
        try:
            theme = json.loads(theme_path.read_text(encoding="utf-8"))
            project = json.loads((game / "default.project.json").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, UnicodeDecodeError):
            theme, project = {}, {}
        wanted = (theme.get("lighting") or {}).get("style") if isinstance(theme, dict) else None
        actual = (((project.get("tree") or {}).get("Lighting") or {}).get("$properties") or {}).get("LightingStyle") if isinstance(project, dict) else None
        if wanted and actual != wanted:
            report.warn("default.project.json", f"Lighting.LightingStyle debería ser {wanted!r} como pide el tema (no se puede cambiar por script)")
        literal = 0
        for path, code in sources.items():
            if side_of(path, src) == "client":
                literal += len(re.findall(r"\bColor3\.(?:fromRGB|fromHex|new)\s*\(|\bEnum\.Font\.\w+", code))
        if literal:
            report.warn("src/client", f"{literal} colores o fuentes escritos en el código del cliente; usa Style para que sigan el tema")

    # Pase de arte
    environment_json = src / "shared" / "Environment.json"
    environment_loader = src / "server" / "EnvironmentLoader.luau"
    if flags["environment"]:
        if not flags["levels"] or not flags["art"]:
            report.warn("GDD.md", "design.environment necesita design.levels y design.art: el pase de arte viste los niveles de Levels.json con el tema")
        if not environment_json.exists():
            report.warn("src/shared/Environment.json", "pendiente: design.environment requiere roblox-environment-artist")
    elif environment_json.exists():
        report.warn("src/shared/Environment.json", "existe pero el GDD no activa design.environment")
    if environment_json.exists():
        if not environment_loader.exists():
            report.error("src/server/EnvironmentLoader.luau", "falta; con Environment.json el pase de arte se aplica con la plantilla de assets/templates")
        else:
            defined = set(re.findall(r"\bfunction\s+EnvironmentLoader\.(\w+)\s*\(", sources.get(environment_loader, "")))
            missing = [name for name in ENVIRONMENTLOADER_API if name not in defined]
            if missing:
                report.error(rel(environment_loader), f"faltan funciones del contrato: {', '.join(missing)}")
            if not any(re.search(r"\bEnvironmentLoader\.apply\s*\(", code) for path, code in sources.items() if path != environment_loader):
                report.warn(rel(environment_loader), "nadie llama a EnvironmentLoader.apply; el pase de arte no se ve en el juego")
        checker = load_sibling(ENVIRONMENT_CHECKER, "factory_check_environment")
        if checker is None:
            report.warn(rel(environment_json), "roblox-environment-artist no está instalado al lado del builder; no se revisó el pase de arte")
        else:
            environment = checker.check_game(game)
            for message in environment.errors:
                report.error("entorno", message)
            for message in environment.warnings:
                report.warn("entorno", message)
            for message in getattr(environment, "notes", []):
                report.note("entorno", message)

    # Interfaz
    ui_dir = src / "client" / "UI"
    if flags["ui"]:
        checker = load_sibling(UI_CHECKER, "factory_check_ui") if ui_dir.is_dir() else None
        if not ui_dir.is_dir():
            report.warn("src/client/UI", "pendiente: design.ui requiere roblox-ui-designer")
        elif checker is None:
            report.warn("src/client/UI", "roblox-ui-designer no está instalado al lado del builder; no se revisó la interfaz")
        else:
            # check_ui también revisa que el tema tenga lo que usa el kit.
            ui = checker.check_game(game)
            for message in ui.errors:
                report.error("ui", message)
            for message in ui.warnings:
                report.warn("ui", message)
        if checker is None and not theme_path.exists():
            report.warn("src/shared/Theme.json", "design.ui necesita el tema (Theme.json) para el kit de UI")

    # Datos del jugador
    schema_path = src / "server" / "Data" / "DataSchema.json"
    if flags["data"]:
        if not schema_path.exists():
            report.warn("src/server/Data/DataSchema.json", "pendiente: design.data requiere roblox-data-architect")
        else:
            checker = load_sibling(DATA_CHECKER, "factory_check_data")
            if checker is None:
                report.warn(rel(schema_path), "roblox-data-architect no está instalado al lado del builder; no se revisaron los datos")
            else:
                result = checker.check_game(game)
                for message in result.errors:
                    report.error("datos", message)
                for message in result.warnings:
                    report.warn("datos", message)
                for message in result.info:
                    report.note("datos", message)
    elif schema_path.exists():
        report.warn(rel(schema_path), "existe pero el GDD no activa design.data")
    player_data = src / "server" / "Data" / "PlayerData.luau"
    if player_data.exists() and not any(re.search(r"\bPlayerData\.start\s*\(", code) for path, code in sources.items() if path != player_data):
        report.warn(rel(player_data), "nadie llama a PlayerData.start(); Bootstrap lo llama antes de Game.start")

    # Módulos activados
    analytics_module = src / "server" / "Analytics.luau"
    if flags["analytics"]:
        if not analytics_module.exists():
            report.warn("src/server/Analytics.luau", "pendiente: analytics.enabled requiere roblox-analytics-dev")
        else:
            checker = load_sibling(ANALYTICS_CHECKER, "factory_check_analytics")
            if checker is None:
                report.warn(rel(analytics_module), "roblox-analytics-dev no está instalado al lado del builder; no se revisó el esquema de analíticas")
            else:
                result = checker.check_game(game)
                for message in result.errors:
                    report.error("analíticas", message)
                for message in result.warnings:
                    report.warn("analíticas", message)
    elif analytics_module.exists():
        report.warn(rel(analytics_module), "existe pero el GDD no activa analytics.enabled")
    live_module = src / "shared" / "LiveConfig.luau"
    if flags["liveops"]:
        if not live_module.exists():
            report.warn("src/shared/LiveConfig.luau", "pendiente: liveops.enabled requiere roblox-liveops")
        else:
            checker = load_sibling(LIVEOPS_CHECKER, "factory_check_liveops")
            if checker is None:
                report.warn(rel(live_module), "roblox-liveops no está instalado al lado del builder; no se revisó el esquema en vivo")
            else:
                result = checker.check_game(game)
                for message in result.errors:
                    report.error("liveops", message)
                for message in result.warnings:
                    report.warn("liveops", message)
    elif live_module.exists():
        report.warn(rel(live_module), "existe pero el GDD no activa liveops.enabled")

    # Varios places
    try:
        levels_for_places = json.loads(levels_json.read_text(encoding="utf-8")) if levels_json.exists() else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        levels_for_places = None
    check_places(game, src, flags, sources, gdd_text, levels_for_places, report)

    # Telemetría
    telemetry_calls = {}
    for path, code in sources.items():
        if path == telemetry:
            continue
        for name in re.findall(r"\bTelemetry\.(\w+)\s*\(", code):
            telemetry_calls[name] = telemetry_calls.get(name, 0) + 1
    if not telemetry_calls:
        report.warn("src", "el juego no emite eventos con Telemetry")
    else:
        if "onboarding" not in telemetry_calls:
            report.warn("src", "no hay pasos de onboarding (Telemetry.onboarding)")
        if levels_json.exists() and not any(name.startswith("progression") for name in telemetry_calls):
            report.warn("src", "hay niveles pero no eventos de progresión (Telemetry.progression*)")
        unknown = sorted(name for name in telemetry_calls if name not in TELEMETRY_API)
        if unknown:
            report.error("src", f"llamadas a funciones que Telemetry no define: {', '.join(unknown)}")

    # Reglas de código
    receipts = []
    server_scripts = []
    for path, code in sources.items():
        side = side_of(path, src)
        where = rel(path)
        if side == "client":
            for name in CLIENT_FORBIDDEN:
                if re.search(rf"\b{name}\b", code):
                    report.error(where, f"el cliente usa {name}, que solo existe o tiene sentido en el servidor")
            if re.search(r"\bTeleportAsync\b", code):
                report.error(where, "TeleportAsync solo funciona en el servidor; los viajes van por Travel")
        if side == "server" and re.search(r"\.LocalPlayer\b", code):
            report.error(where, "el servidor usa LocalPlayer, que solo existe en el cliente")
        if path.name.endswith((".server.luau", ".server.lua")):
            server_scripts.append(where)
        for match in re.finditer(r"(?<![\w.:])(wait|spawn|delay)\s*\(", code):
            report.warn(where, f"{match.group(1)}() está obsoleto; usa task.{match.group(1)}()")
        if re.search(r"\bInstance\.new\(\s*[\"']\w+[\"']\s*,", code):
            report.warn(where, "Instance.new con padre como segundo argumento; asigna Parent al final")
        for asset_id in re.findall(r"rbxassetid://(\d+)", code):
            if asset_id not in gdd_text:
                report.error(where, f"rbxassetid://{asset_id} no está declarado en el GDD (Assets y servicios); no inventes IDs")
        receipts += [where for _ in re.finditer(r"\.ProcessReceipt\s*=(?!=)", code)]
        for target in require_targets(code):
            if target.startswith("#"):
                report.warn(where, f"require por ID de asset ({target[1:]}); verifica su origen")
            elif target not in modules and target not in {"Packages", "Shared", "Server", "Client"}:
                report.warn(where, f"require de '{target}', que no es un módulo de src/")
        handlers = len(re.findall(r"\.OnServerEvent:Connect\b", code)) + len(re.findall(r"\.OnServerInvoke\s*=", code))
        if handlers:
            report.note(where, f"{handlers} handler(s) de remotes: revisa que validen tipo, rango, contexto y frecuencia")
        touches = len(re.findall(r"\.Touched:Connect\b", code))
        if touches:
            report.note(where, f"{touches} conexión(es) Touched: revisa que identifiquen al jugador y validen el estado")
    if len(receipts) > 1:
        report.error("src", f"hay {len(receipts)} asignaciones a ProcessReceipt ({', '.join(receipts)}); debe haber una sola")
    elif receipts and "developer-products" not in flags["monetization"]:
        report.warn(receipts[0], "asigna ProcessReceipt pero el GDD no activa developer-products")
    if not server_scripts:
        report.warn("src/server", "no hay ningún Script de servidor (*.server.luau)")
    elif len(server_scripts) > 1:
        report.warn("src/server", f"hay {len(server_scripts)} Scripts de servidor; el builder recomienda una sola entrada (Bootstrap)")

    # Arquitectura de módulos (references/module-architecture.md)
    layers = load_sibling(MODULES_CHECKER, "factory_check_modules")
    if layers is not None:
        result = layers.check_game(game)
        for message in result.errors:
            report.error("módulos", message)
        for message in result.warnings:
            report.warn("módulos", message)
        for message in result.info:
            report.note("módulos", message)
    return report


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa un juego de la fábrica contra el contrato del builder.")
    parser.add_argument("game", type=Path, help="carpeta del juego (la que contiene GDD.md)")
    parser.add_argument("--json", action="store_true", help="imprime el resultado como JSON")
    args = parser.parse_args(argv)
    if not args.game.is_dir():
        print(f"ERROR no existe la carpeta {args.game}")
        return 2
    report = check_game(args.game.resolve())
    if args.json:
        print(json.dumps({"errors": report.errors, "warnings": report.warnings, "info": report.info},
                         ensure_ascii=False, indent=2))
    else:
        print(f"Revisión del juego: {args.game}")
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
