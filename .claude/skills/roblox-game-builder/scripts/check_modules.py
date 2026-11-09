#!/usr/bin/env python3
"""Revisa la arquitectura de módulos de un juego de la fábrica.

Uso:
    python check_modules.py <carpeta-del-juego>
    python check_modules.py <carpeta-del-juego> --json

Capas (references/module-architecture.md): núcleo, cores (src/<lado>/Modules/<Nombre>),
puentes (src/<lado>/Bridges/<Origen>_<Destino>), Game (src/<lado>/Game), UI
(src/client/UI) y entrada (Script y LocalScript de la raíz de cada lado). Resuelve
cada require con el árbol de default.project.json, por ruta de instancia
(script.Parent.X, ReplicatedStorage.Shared.X, :WaitForChild("X")) o por texto
("./X", "../X", "@self/X", "@game/..."), y comprueba:

  M1  un core no requiere otro core (salvo excepción declarada), un puente, Game ni la UI;
  M2  un puente se llama <Origen>_<Destino>, con dos cores que existen, y requiere
      solo esos dos y el núcleo;
  M3  solo la entrada requiere Game; el núcleo no requiere las capas del juego;
  M4  sin require circulares;
  M5  DataStoreService en una sola capa o módulo (un único servicio de datos); con el
      servicio de roblox-data-architect (src/server/Data/Store.luau), solo dentro de Data/;
  M6  el Mapa de módulos del GDD coincide con las carpetas;
  M7  un proyecto sin capas (plano) se informa y no se revisan sus capas;
  M8  los módulos copiados de la librería siguen iguales a library.lock.json.

Es un análisis estático: un require calculado en ejecución dentro de un core, un
puente o Game queda como nota. Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_game as rules  # noqa: E402

SIDES = ("server", "client", "shared")
LUAU_SUFFIXES = (".luau", ".lua")
SCRIPT_SUFFIXES = (".server.luau", ".client.luau", ".server.lua", ".client.lua")
INIT_NAMES = {"init.luau", "init.lua", "init.server.luau", "init.client.luau", "init.server.lua", "init.client.lua"}
SKILLS_DIR = Path(__file__).resolve().parents[2]
# Núcleo que no viene de una plantilla: los ajustes del juego y los tipos generados del perfil.
KERNEL_NAMES = {"Config", "ServerConfig", "DataTypes"}
NAME_RE = re.compile(r"[A-Z][A-Za-z0-9]*")
BRIDGE_RE = re.compile(r"([A-Za-z][A-Za-z0-9]*)_([A-Za-z][A-Za-z0-9]*)")
LAYERED = {"module", "bridge", "game"}
LAYER_OF_KIND = {"module": "core", "bridge": "puente", "game": "main"}


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


@dataclass(frozen=True)
class Unit:
    kind: str  # kernel, module, bridge, game, ui o entry
    name: str = ""

    def label(self) -> str:
        return {
            "kernel": "el núcleo",
            "module": f"el core {self.name}",
            "bridge": f"el puente {self.name}",
            "game": "Game",
            "ui": "la UI",
            "entry": "la entrada",
        }[self.kind]


# --- Archivos e instancias ---------------------------------------------------

def instance_name(filename: str) -> str:
    for suffix in (*SCRIPT_SUFFIXES, *LUAU_SUFFIXES, ".json"):
        if filename.endswith(suffix):
            return filename[: -len(suffix)]
    return filename


def is_source(path: Path) -> bool:
    name = path.name
    if path.suffix in LUAU_SUFFIXES:
        return True
    return path.suffix == ".json" and not name.endswith((".meta.json", ".model.json", ".project.json"))


def unit_of(parts: tuple[str, ...]) -> Unit:
    """Capa de un archivo según su ruta relativa a src/."""
    if len(parts) >= 3 and parts[0] in SIDES and parts[1] in {"Modules", "Bridges"}:
        name = parts[2] if len(parts) > 3 else instance_name(parts[2])
        return Unit("module" if parts[1] == "Modules" else "bridge", name)
    if len(parts) >= 2 and parts[0] in SIDES and (parts[1] == "Game" if len(parts) > 2 else instance_name(parts[1]) == "Game"):
        return Unit("game")
    if len(parts) >= 3 and parts[0] == "client" and parts[1] == "UI":
        return Unit("ui")
    if len(parts) == 2 and parts[1].endswith(SCRIPT_SUFFIXES):
        return Unit("entry")
    return Unit("kernel")


def project_mounts(game: Path) -> list[tuple[tuple[str, ...], Path]]:
    """Cada $path de default.project.json con la ruta de instancia donde se monta."""
    tree = rules.project_tree(game / "default.project.json")
    mounts: list[tuple[tuple[str, ...], Path]] = []

    def walk(node: dict, names: tuple[str, ...]) -> None:
        if isinstance(node.get("$path"), str):
            mounts.append((names, (game / node["$path"]).resolve()))
        for key, child in node.items():
            if not key.startswith("$") and isinstance(child, dict):
                walk(child, names + (key,))

    if tree is not None:
        walk(tree, ())
    # La montura más específica primero.
    return sorted(mounts, key=lambda mount: len(mount[1].parts), reverse=True)


def instance_path(path: Path, mounts) -> tuple[str, ...] | None:
    resolved = path.resolve()
    for names, base in mounts:
        if resolved == base:
            return names
        try:
            relative = resolved.relative_to(base).parts
        except ValueError:
            continue
        if relative[-1] in INIT_NAMES:
            return names + relative[:-1]
        return names + relative[:-1] + (instance_name(relative[-1]),)
    return None


def kernel_names() -> set[str]:
    """Nombres de las plantillas de todos los skills instalados, más Config y ServerConfig."""
    names = set(KERNEL_NAMES)
    for template in SKILLS_DIR.glob("*/assets/templates/src/**/*"):
        if template.is_file() and is_source(template):
            names.add(template.parent.name if template.name in INIT_NAMES else instance_name(template.name))
    return names


# --- require -----------------------------------------------------------------

ALIAS_RE = re.compile(r"^[ \t]*local[ \t]+([A-Za-z_]\w*)[ \t]*(?::[^=\n]*)?=[ \t]*([^\n]+?)[ \t;]*$", re.M)
ACCESS_RE = re.compile(r"""\s*(?:
      \.\s*(?P<field>[A-Za-z_]\w*)
    | :\s*(?P<method>WaitForChild|FindFirstChild|GetService)\s*\(\s*(?P<q1>["'])(?P<arg>[^"'\n]*)(?P=q1)\s*(?:,[^()]*)?\)
    | \[\s*(?P<q2>["'])(?P<key>[^"'\n]*)(?P=q2)\s*\]
)""", re.X)
STRING_RE = re.compile(r"""^(["'`])(.*)\1$""", re.S)


def require_expressions(code: str) -> list[tuple[int, str]]:
    """(línea, expresión) de cada require(...) del código sin comentarios."""
    found = []
    for match in rules.REQUIRE_RE.finditer(code):
        start = match.end()
        depth, index = 1, start
        while index < len(code) and depth:
            if code[index] in "\"'`":
                index = rules._string_end(code, index)
                continue
            depth += {"(": 1, ")": -1}.get(code[index], 0)
            index += 1
        found.append((code.count("\n", 0, match.start()) + 1, code[start:index - 1].strip()))
    return found


def aliases_of(code: str) -> dict[str, list[str]]:
    aliases: dict[str, list[str]] = {}
    for match in ALIAS_RE.finditer(code):
        aliases.setdefault(match.group(1), []).append(match.group(2))
    return aliases


def resolve_string(text: str, script: tuple[str, ...]) -> tuple[str, ...] | None:
    if text.startswith("@game/"):
        base, rest = [], text[len("@game/"):]
    elif text.startswith("@self/"):
        base, rest = list(script), text[len("@self/"):]
    elif text.startswith("./"):
        base, rest = list(script[:-1]), text[2:]
    elif text.startswith("../"):
        if len(script) < 2:
            return None
        base, rest = list(script[:-2]), text[3:]
    else:
        return None  # alias o ruta no relativa: no se puede resolver
    for part in rest.split("/"):
        if part in {"", "."}:
            continue
        if part == "..":
            if not base:
                return None
            base.pop()
        else:
            base.append(part)
    return tuple(base)


def resolve(expression: str, script: tuple[str, ...], aliases: dict[str, list[str]], depth: int = 0) -> tuple[str, ...] | None:
    """Ruta de instancia de una expresión de require, o None si se calcula en ejecución."""
    expression = re.split(r"\s*::", expression.strip(), maxsplit=1)[0].strip()
    while expression.startswith("(") and expression.endswith(")"):
        expression = expression[1:-1].strip()
    string = STRING_RE.match(expression)
    if string:
        return resolve_string(string.group(2), script)
    head = re.match(r"[A-Za-z_]\w*", expression)
    if not head:
        return None
    name, index = head.group(0), head.end()
    path: list[str] | None
    if name == "script":
        path = list(script)
    elif name == "game":
        path = []
    elif name == "workspace":
        path = ["Workspace"]
    elif name in aliases and depth < 8:
        path = None
        for candidate in aliases[name]:
            resolved = resolve(candidate, script, aliases, depth + 1)
            if resolved is not None:
                path = list(resolved)
                break
        if path is None:
            return None
    else:
        return None
    while index < len(expression):
        access = ACCESS_RE.match(expression, index)
        if not access:
            return None
        index = access.end()
        if access.group("field"):
            if access.group("field") == "Parent":
                if not path:
                    return None
                path.pop()
            else:
                path.append(access.group("field"))
        elif access.group("method"):
            if access.group("method") == "GetService" and path:
                return None
            path.append(access.group("arg"))
        else:
            path.append(access.group("key"))
    return tuple(path)


# --- Mapa de módulos ---------------------------------------------------------

def module_map(gdd_text: str) -> dict[str, dict] | None:
    """Filas del Mapa de módulos del GDD: {nombre: {"layer", "exceptions", "data"?}}. None si no está.
    "data" (las secciones de la columna "Datos que posee") solo está si la tabla tiene esa columna."""
    heading = re.search(r"^#{2,4}[ \t]+Mapa de módulos[ \t]*$", gdd_text, re.M)
    if not heading:
        return None
    header: list[str] | None = None
    rows: dict[str, dict] = {}
    for line in gdd_text[heading.end():].split("\n"):
        stripped = line.strip()
        if stripped.startswith("#"):
            break
        if not stripped.startswith("|"):
            if header is not None and not stripped:
                break
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if header is None:
            header = [cell.lower() for cell in cells]
            continue
        if all(set(cell) <= set("-: ") for cell in cells):
            continue

        def column(*keys: str) -> str:
            for index, title in enumerate(header):
                if any(key in title for key in keys) and index < len(cells):
                    return cells[index]
            return ""

        raw_name = column("módulo", "modulo")
        quoted = re.findall(r"`([^`]+)`", raw_name)
        name = (quoted[0] if quoted else raw_name).strip()
        if not name:
            continue
        rows[name] = {
            "layer": column("capa").strip("` ").lower(),
            "exceptions": set(re.findall(r"`([^`]+)`", column("excepci"))),
        }
        if any("datos" in title for title in header):
            rows[name]["data"] = set(re.findall(r"`([^`]+)`", column("datos")))
        if any("origen" in title for title in header):
            rows[name]["origin"] = column("origen").strip("` ")
    return rows


# --- Comprobaciones ----------------------------------------------------------

def find_cycles(graph: dict[Path, set[Path]]) -> list[list[Path]]:
    cycles: list[list[Path]] = []
    seen: set[frozenset] = set()
    state: dict[Path, int] = {}
    stack: list[Path] = []

    def visit(node: Path) -> None:
        state[node] = 1
        stack.append(node)
        for target in sorted(graph.get(node, ())):
            if state.get(target) == 1:
                cycle = stack[stack.index(target):] + [target]
                key = frozenset(cycle)
                if key not in seen:
                    seen.add(key)
                    cycles.append(cycle)
            elif target not in state:
                visit(target)
        stack.pop()
        state[node] = 2

    for node in sorted(graph):
        if node not in state:
            visit(node)
    return cycles


def edge_problem(source: Unit, target: Unit, exceptions: dict[str, set[str]]) -> tuple[str, str] | None:
    """("error" | "warn", mensaje) si la dependencia rompe una regla de capas."""
    if source == target:
        return None
    if target.kind == "entry":
        return "error", f"{source.label()} requiere la entrada; un Script no se requiere"
    if target.kind == "game" and source.kind != "entry":
        return "error", f"M3: {source.label()} requiere Game; solo la entrada (Bootstrap) requiere Game"
    if target.kind == "ui" and source.kind not in {"ui", "entry"}:
        return "error", f"{source.label()} requiere la UI; la UI solo la usa su propia entrada"
    if source.kind == "kernel":
        if target.kind != "kernel":
            return "error", f"M3: el núcleo no conoce los módulos del juego y requiere {target.label()}"
        return None
    if source.kind == "module":
        if target.kind == "kernel":
            return None
        if target.kind == "module":
            if target.name in exceptions.get(source.name, set()):
                return "warn", f"M1: excepción declarada en el Mapa de módulos: el core {source.name} depende del core {target.name}"
            return "error", (f"M1: el core {source.name} requiere el core {target.name}; conéctalos con un puente "
                             f"({source.name}_{target.name} o {target.name}_{source.name}), pásale una función en init "
                             "o declara la excepción en el Mapa de módulos")
        return "error", f"M1: el core {source.name} requiere {target.label()}; un core solo requiere su módulo y el núcleo"
    if source.kind == "bridge":
        parts = BRIDGE_RE.fullmatch(source.name)
        if target.kind == "kernel" or (target.kind == "module" and parts and target.name in parts.groups()):
            return None
        if target.kind == "module":
            return "error", f"M2: el puente {source.name} requiere el core {target.name}, que no es ninguno de sus dos cores"
        return "error", f"M2: el puente {source.name} requiere {target.label()}; un puente requiere solo sus dos cores y el núcleo"
    if source.kind == "ui":
        if target.kind in {"kernel", "module"}:
            return None
        return "error", f"la UI requiere {target.label()}; usa el núcleo, los cores de cliente y el estado que publica el servidor"
    if source.kind == "entry" and target.kind in {"module", "bridge"}:
        return "warn", f"la entrada requiere {target.label()}; la composición va en Game (src/<lado>/Game)"
    return None


def check_game(game: Path) -> Report:
    report = Report()
    src = game / "src"
    if not src.is_dir():
        report.error("src", "no existe la carpeta src/")
        return report

    def rel(path: Path) -> str:
        return path.relative_to(game).as_posix()

    files = sorted(p for p in src.rglob("*") if p.is_file() and is_source(p))
    units = {path: unit_of(path.relative_to(src).parts) for path in files}
    luau = [path for path in files if path.suffix in LUAU_SUFFIXES]
    sources = {path: rules.strip_comments(path.read_text(encoding="utf-8")) for path in luau}
    mounts = project_mounts(game)
    by_instance: dict[tuple[str, ...], Path] = {}
    for path in files:
        names = instance_path(path, mounts)
        if names is not None:
            by_instance.setdefault(names, path)

    layered = any(unit.kind in LAYERED for unit in units.values())
    module_names = {unit.name for unit in units.values() if unit.kind == "module"}
    bridge_names = {unit.name for unit in units.values() if unit.kind == "bridge"}

    # Mapa de módulos (M6) y excepciones declaradas
    gdd_path = game / "GDD.md"
    rows = module_map(gdd_path.read_text(encoding="utf-8")) if gdd_path.exists() else None
    exceptions: dict[str, set[str]] = {}
    for name, row in (rows or {}).items():
        if row["layer"] == "core" and row["exceptions"]:
            exceptions[name] = {target for target in row["exceptions"] if target != name}

    # Dependencias entre archivos
    graph: dict[Path, set[Path]] = {}
    unit_graph: dict[str, set[str]] = {}
    for path, code in sources.items():
        script = instance_path(path, mounts)
        aliases = aliases_of(code)
        source = units[path]
        for line, expression in require_expressions(code):
            where = f"{rel(path)}:{line}"
            target_path = None
            names = resolve(expression, script, aliases) if script is not None else None
            if names is None:
                if layered and source.kind in LAYERED and not re.fullmatch(r"\d+", expression):
                    report.note(where, f"require({expression}) se calcula en ejecución; revisa a mano que respete las capas")
                continue
            target_path = by_instance.get(names)
            if target_path is None or target_path == path:
                continue  # fuera de src/ (paquetes, instancias de Studio) o inexistente: lo informa check_game
            graph.setdefault(path, set()).add(target_path)
            target = units[target_path]
            if not layered:
                continue
            problem = edge_problem(source, target, exceptions)
            if problem:
                level, message = problem
                (report.error if level == "error" else report.warn)(where, message)
            if source.kind == "module" and target.kind == "module" and source != target:
                unit_graph.setdefault(source.name, set()).add(target.name)

    # M4: ciclos
    for cycle in find_cycles(graph):
        report.error(rel(cycle[0]), "M4: require circular: " + " → ".join(rel(path) for path in cycle))
    module_cycles = find_cycles({Path(name): {Path(target) for target in targets} for name, targets in unit_graph.items()})
    for cycle in module_cycles:
        report.error("módulos", "M4: dependencia circular entre cores: " + " → ".join(path.name for path in cycle))

    # M5: un único servicio de datos
    stores = sorted({units[path].label() for path, code in sources.items() if re.search(r"\bDataStoreService\b", code)})
    data_dir = src / "server" / "Data"
    if (data_dir / "Store.luau").exists():
        # Con el servicio de datos de roblox-data-architect, el DataStore se usa solo dentro de Data/.
        for path, code in sources.items():
            if re.search(r"\bDataStoreService\b", code) and data_dir not in path.parents:
                report.error(rel(path), "M5: DataStoreService solo se usa dentro de src/server/Data/; el resto del juego usa PlayerData")
    elif len(stores) > 1:
        report.error("src", f"M5: DataStoreService aparece en {', '.join(stores)}; el juego tiene un único servicio de datos")
    elif not layered:
        # En un proyecto plano todo es núcleo: se cuentan los archivos.
        data_files = sorted(rel(path) for path, code in sources.items() if re.search(r"\bDataStoreService\b", code))
        if len(data_files) > 1:
            report.warn("src", f"M5: DataStoreService aparece en {', '.join(data_files)}; un único servicio de datos escribe el perfil")

    if not layered:
        report.note("src", "M7: proyecto plano (sin Modules/, Bridges/ ni Game/); no se revisaron las capas. "
                           "Un juego nuevo usa las capas de references/module-architecture.md")
        return report

    # M2: nombres de los puentes
    for name in sorted(bridge_names):
        parts = BRIDGE_RE.fullmatch(name)
        if not parts:
            report.error(f"Bridges/{name}", "M2: un puente se llama <Origen>_<Destino>, con el nombre de sus dos cores")
            continue
        origin, destination = parts.groups()
        if origin == destination:
            report.error(f"Bridges/{name}", "M2: un puente une dos cores distintos")
        for part in (origin, destination):
            if part not in module_names:
                report.error(f"Bridges/{name}", f"M2: el core {part} no existe en Modules/")
        if f"{destination}_{origin}" in bridge_names and origin < destination:
            report.warn(f"Bridges/{name}", f"existen {name} y {destination}_{origin}: un puente por par conecta los dos sentidos")
    for name in sorted(module_names):
        if not NAME_RE.fullmatch(name):
            report.warn(f"Modules/{name}", "un core se nombra en PascalCase, sin _ (el _ separa los cores en el nombre de un puente)")

    # Archivos fuera de las capas
    known = kernel_names()
    for path in luau:
        unit = units[path]
        if unit.kind == "kernel" and instance_name(path.name if path.name not in INIT_NAMES else path.parent.name) not in known:
            report.warn(rel(path), "está fuera de las capas; muévelo a Modules/ (sistema), Bridges/ (conexión entre dos) o Game/ (este juego)")

    # M6: Mapa de módulos
    if gdd_path.exists():
        expected = {name: "core" for name in module_names} | {name: "puente" for name in bridge_names}
        if any(unit.kind == "game" for unit in units.values()):
            expected["Game"] = "main"
        if rows is None:
            report.warn("GDD.md", "M6: falta el Mapa de módulos en la sección Arquitectura (ver references/module-architecture.md)")
        else:
            for name, layer in sorted(expected.items()):
                if name not in rows:
                    report.warn("GDD.md", f"M6: el Mapa de módulos no tiene la fila de {name} ({layer})")
                elif rows[name]["layer"] != layer:
                    report.warn("GDD.md", f"M6: en el Mapa de módulos, {name} es {layer}, no {rows[name]['layer'] or 'sin capa'}")
            for name in sorted(set(rows) - set(expected)):
                report.warn("GDD.md", f"M6: el Mapa de módulos tiene {name}, pero no hay carpeta para él")
            for name, targets in sorted(exceptions.items()):
                for target in sorted(targets - module_names):
                    report.warn("GDD.md", f"M6: la excepción de {name} nombra a {target}, que no es un core")

    check_lock(game, rows, report)
    return report


def lock_hashes(folder: Path) -> dict[str, str]:
    """Hash de cada archivo de una copia, como lo calcula library.py (fin de línea LF)."""
    return {path.relative_to(folder).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for path in sorted(folder.rglob("*")) if path.is_file() and "__pycache__" not in path.parts}


def check_lock(game: Path, rows: dict | None, report: Report) -> None:
    """M8: los módulos copiados de la librería siguen iguales a la versión de library.lock.json."""
    path = game / "library.lock.json"
    if not path.exists():
        return
    try:
        lock = json.loads(path.read_text(encoding="utf-8"))
        modules = lock["modules"]
    except (json.JSONDecodeError, UnicodeDecodeError, KeyError, TypeError) as exc:
        report.error("library.lock.json", f"no se pudo leer ({exc})")
        return
    for name, entry in sorted(modules.items()):
        where = f"library.lock.json: {name}"
        folder = game / str(entry.get("path", ""))
        if not entry.get("path") or not folder.is_dir():
            report.error(where, f"la carpeta {entry.get('path')} no existe; vuelve a copiarlo con library.py add")
            continue
        locked = entry.get("files") or {}
        current = lock_hashes(folder)
        missing = sorted(set(locked) - set(current))
        changed = sorted(name_ for name_ in set(locked) & set(current) if locked[name_] != current[name_])
        extra = sorted(set(current) - set(locked))
        if missing:
            report.error(where, f"faltan archivos de la librería: {', '.join(missing)}")
        if changed or extra:
            report.warn(where, f"M8: difiere de {name}@{entry.get('version')} de la librería ({', '.join(changed + extra)}); "
                               "lleva el cambio a la librería con una versión nueva, o quítalo de library.lock.json y márcalo como propio")
        if rows is not None:
            row = rows.get(name)
            if row is not None and "origin" in row and "librería" not in row["origin"]:
                report.warn("GDD.md", f"M6: en el Mapa de módulos, {name} viene de la librería ({name}@{entry.get('version')}); "
                                      "pon su Origen")
    if rows is not None:
        for name, row in sorted(rows.items()):
            if "librería" in row.get("origin", "") and name not in modules:
                report.warn("GDD.md", f"M6: el Mapa de módulos dice que {name} viene de la librería, pero no está en library.lock.json")


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa la arquitectura de módulos de un juego de la fábrica.")
    parser.add_argument("game", type=Path, help="carpeta del juego (la que contiene src/ y default.project.json)")
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
        print(f"Módulos del juego: {args.game}")
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
