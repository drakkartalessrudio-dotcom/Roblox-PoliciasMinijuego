#!/usr/bin/env python3
"""Consulta la librería de módulos (Roblox-Library), copia módulos a un juego y la mejora.

Uso en el juego:
    python library.py search <palabras…>          busca en el catálogo por nombre, resumen, tags y API
    python library.py info <Nombre>               manifiesto y README de un módulo
    python library.py add <Juego> <Nombre>        copia el módulo al juego y lo anota en library.lock.json
    python library.py update <Juego> <Nombre>     copia la versión más nueva y muestra su CHANGELOG
    python library.py status <Juego>              versión copiada, cambios locales y versiones nuevas
    python library.py diff <Juego> <Nombre>       diferencias entre la copia del juego y la versión de la librería

Uso en la librería (siempre en una branch; subirla y abrir el PR lo aprueba el usuario):
    python library.py publish <Juego> <Nombre> [--tags a,b]   borrador de un core o puente propio del juego
    python library.py bump <Nombre> patch|minor|major --note "…" [--from-game <Juego>]
                                                  sube la versión, el CHANGELOG, el README y usedIn
    python library.py release <Nombre…>           revisa, hace commit y etiqueta <Nombre>@<versión>
    python library.py record <Juego>              anota en usedIn los módulos que usa el juego

La librería se busca, en orden, en --library <ruta>, en la variable ROBLOX_LIBRARY y en
project.library del frontmatter del GDD del juego (ruta absoluta o relativa al juego).

add copia src/ del módulo a src/server/Modules/<Nombre>/ (un core) o
src/server/Bridges/<Nombre>/ (un puente), guarda en library.lock.json la versión, el
commit de la librería y el hash de cada archivo, y lista lo que falta hacer a mano:
ajustes de Config, la sección de datos para el data architect, plantillas del núcleo
que el juego no tiene y la fila del Mapa de módulos. No sobrescribe una copia con
cambios locales salvo con --force.

publish y bump dejan lo que no pueden deducir marcado "(por completar)"; release no
hace commit mientras quede alguna marca, si check_library.py da errores o si fallan
las pruebas de Lune del módulo y de sus puentes.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

LOCK_NAME = "library.lock.json"
SCRIPTS = Path(__file__).resolve().parent
PENDING = "(por completar)"
MAIN_BRANCHES = {"main", "master"}
SEMVER_RE = re.compile(r"\d+\.\d+\.\d+")
# Dónde vive cada plantilla del núcleo dentro de un juego.
KERNEL_FILES = {
    "Signal": "src/shared/Signal.luau",
    "Tuning": "src/shared/Tuning.luau",
    "DataTypes": "src/shared/DataTypes.luau",
    "Style": "src/shared/Style.luau",
    "Place": "src/shared/Place.luau",
    "Telemetry": "src/server/Telemetry.luau",
    "LevelLoader": "src/server/LevelLoader.luau",
    "EnvironmentLoader": "src/server/EnvironmentLoader.luau",
    "Travel": "src/server/Travel.luau",
    "PlayerData": "src/server/Data/PlayerData.luau",
}
# Skill y versión desde la que existe cada plantilla, para el requires de un borrador.
KERNEL_SINCE = {
    "Signal": ("roblox-game-builder", "4.0.0"),
    "Tuning": ("roblox-game-builder", "3.0.0"),
    "Telemetry": ("roblox-game-builder", "3.0.0"),
    "LevelLoader": ("roblox-game-builder", "3.0.0"),
    "Style": ("roblox-game-builder", "3.3.0"),
    "EnvironmentLoader": ("roblox-game-builder", "3.5.0"),
    "Place": ("roblox-game-builder", "3.7.0"),
    "Travel": ("roblox-game-builder", "3.7.0"),
    "PlayerData": ("roblox-data-architect", "1.1.0"),
    "DataTypes": ("roblox-data-architect", "1.1.0"),
}


class LibraryError(Exception):
    pass


def file_hash(path: Path) -> str:
    text = path.read_bytes().replace(b"\r\n", b"\n")
    return hashlib.sha256(text).hexdigest()


def tree_hashes(folder: Path) -> dict[str, str]:
    return {path.relative_to(folder).as_posix(): file_hash(path)
            for path in sorted(folder.rglob("*")) if path.is_file() and "__pycache__" not in path.parts}


def frontmatter(game: Path) -> dict:
    gdd = game / "GDD.md"
    if not gdd.exists():
        return {}
    sys.path.insert(0, str(SCRIPTS))
    import check_game  # noqa: E402

    try:
        return check_game.read_frontmatter(gdd.read_text(encoding="utf-8"))
    except Exception:
        return {}


def find_library(explicit: str | None, game: Path | None = None) -> Path:
    candidates = [explicit, os.environ.get("ROBLOX_LIBRARY")]
    if game is not None:
        project = frontmatter(game).get("project") or {}
        if isinstance(project, dict) and isinstance(project.get("library"), str):
            path = Path(project["library"])
            candidates.append(str(path if path.is_absolute() else game / path))
    for candidate in candidates:
        if candidate and (Path(candidate) / "catalog.json").exists():
            return Path(candidate).resolve()
    raise LibraryError("no encuentro la librería: usa --library <ruta>, la variable ROBLOX_LIBRARY "
                       "o project.library en el GDD (la carpeta tiene catalog.json)")


def catalog(library: Path) -> list[dict]:
    return json.loads((library / "catalog.json").read_text(encoding="utf-8")).get("modules", [])


def entry_for(library: Path, name: str) -> dict:
    for entry in catalog(library):
        if entry.get("name") == name:
            return entry
    raise LibraryError(f"{name} no está en el catálogo de la librería")


def manifest_for(library: Path, entry: dict) -> dict:
    return json.loads((library / entry["path"] / "module.json").read_text(encoding="utf-8"))


def library_commit(library: Path) -> str | None:
    try:
        result = subprocess.run(["git", "-C", str(library), "rev-parse", "--short", "HEAD"],
                                capture_output=True, text=True, check=True)
        return result.stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def library_remote(library: Path) -> str | None:
    try:
        result = subprocess.run(["git", "-C", str(library), "remote", "get-url", "origin"],
                                capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    match = re.search(r"github\.com[:/](.+?)(?:\.git)?$", result.stdout.strip())
    return match.group(1) if match else result.stdout.strip() or None


def read_lock(game: Path) -> dict:
    path = game / LOCK_NAME
    if not path.exists():
        return {"schemaVersion": 1, "library": None, "modules": {}}
    return json.loads(path.read_text(encoding="utf-8"))


def write_lock(game: Path, lock: dict) -> None:
    lock["modules"] = dict(sorted(lock["modules"].items()))
    (game / LOCK_NAME).write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def target_folder(game: Path, kind: str, name: str) -> Path:
    return game / "src" / "server" / ("Modules" if kind == "core" else "Bridges") / name


def version_tuple(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", text)[:3])


def next_version(version: str, part: str) -> str:
    major, minor, patch = version_tuple(version)
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_json(path: Path, data) -> None:
    write_text(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def strip_comments(code: str) -> str:
    code = re.sub(r"--\[(=*)\[.*?\]\1\]", "", code, flags=re.S)
    return re.sub(r"--[^\n]*", "", code)


# --- Git y herramientas de la librería ------------------------------------------

def git(folder: Path, *args: str) -> str:
    try:
        result = subprocess.run(["git", "-C", str(folder), *args], capture_output=True, text=True, encoding="utf-8")
    except OSError as exc:
        raise LibraryError(f"no puedo correr git: {exc}") from exc
    if result.returncode != 0:
        raise LibraryError(f"git {' '.join(args)}: {(result.stderr or result.stdout).strip()}")
    return result.stdout.rstrip()  # sin lstrip: git status --porcelain empieza con espacios


def current_branch(library: Path) -> str:
    return git(library, "rev-parse", "--abbrev-ref", "HEAD")


def work_branch(library: Path, wanted: str) -> str:
    """Branch donde se cambia la librería: la actual si no es main; si no, crea (o retoma) wanted."""
    branch = current_branch(library)
    if branch not in MAIN_BRANCHES:
        return branch
    if git(library, "status", "--porcelain"):
        raise LibraryError(f"la librería tiene cambios sin commit en {branch}; guárdalos o descártalos antes")
    exists = git(library, "branch", "--list", wanted)
    git(library, "checkout", *([wanted] if exists else ["-b", wanted]))
    return wanted


def changed_folders(library: Path) -> set[str]:
    """Carpetas de módulos y puentes (modules/<Nombre>, bridges/<Nombre>) con cambios sin commit."""
    folders = set()
    for line in git(library, "status", "--porcelain", "--untracked-files=all", "--", "modules", "bridges").splitlines():
        parts = line[3:].strip().strip('"').split(" -> ")[-1].split("/")
        if len(parts) >= 2:
            folders.add("/".join(parts[:2]))
    return folders


def unreleased(library: Path) -> set[str]:
    """Como changed_folders, pero vacío si la librería no es un repo de git."""
    try:
        return changed_folders(library)
    except LibraryError:
        return set()


def commit(library: Path, paths: list[str], message: str) -> str | None:
    """Hace commit de esas carpetas y del catálogo. Devuelve el commit corto, o None si no había cambios."""
    git(library, "add", "-A", "--", *paths, "catalog.json", "CATALOG.md")
    staged = subprocess.run(["git", "-C", str(library), "diff", "--cached", "--quiet"], capture_output=True)
    if staged.returncode == 0:
        return None
    title, _, body = message.partition("\n\n")
    git(library, "commit", "-m", title, *(["-m", body] if body else []))
    return git(library, "rev-parse", "--short", "HEAD")


def library_tool(library: Path, name: str):
    path = library / "tools" / f"{name}.py"
    if not path.exists():
        raise LibraryError(f"la librería no tiene tools/{name}.py")
    key = f"roblox_library_{name}_{hashlib.sha1(str(path.resolve()).encode()).hexdigest()[:12]}"
    if key in sys.modules:
        return sys.modules[key]
    spec = importlib.util.spec_from_file_location(key, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[key] = module  # dataclasses busca el módulo aquí
    spec.loader.exec_module(module)
    return module


def rebuild_catalog(library: Path) -> None:
    tool = library_tool(library, "build_catalog")
    entries = tool.collect(library)
    write_text(library / "catalog.json", tool.render_json(entries))
    write_text(library / "CATALOG.md", tool.render_markdown(entries))


def check(library: Path) -> tuple[list[str], list[str]]:
    report = library_tool(library, "check_library").check_library(library)
    return report.errors, report.warnings


def module_dir(library: Path, name: str) -> Path | None:
    for directory in ("modules", "bridges"):
        folder = library / directory / name
        if (folder / "module.json").exists():
            return folder
    return None


def read_manifest(folder: Path) -> dict:
    return json.loads((folder / "module.json").read_text(encoding="utf-8"))


def bridges_of(library: Path, core: str) -> list[tuple[str, str, str]]:
    """Puentes de la librería que unen a core: (nombre, rol, rango)."""
    found = []
    for path in sorted((library / "bridges").glob("*/module.json")):
        manifest = json.loads(path.read_text(encoding="utf-8"))
        for role in ("origin", "destination"):
            end = manifest.get(role) or {}
            if end.get("name") == core:
                found.append((manifest["name"], role, str(end.get("versions"))))
    return found


# --- Juegos que usan un módulo ----------------------------------------------------

def game_name(game: Path) -> str:
    project = frontmatter(game).get("project") or {}
    name = project.get("name") if isinstance(project, dict) else None
    return name if isinstance(name, str) and name else game.resolve().name


def game_source(game: Path) -> str:
    """Repositorio y carpeta del juego, sin rutas de la máquina."""
    try:
        top = Path(git(game, "rev-parse", "--show-toplevel")).resolve()
        relative = game.resolve().relative_to(top).as_posix()
    except (LibraryError, ValueError):
        return game.resolve().name
    return top.name if relative == "." else f"{top.name}/{relative}"


def record_use(manifest: dict, game: str, version: str, source: str) -> bool:
    """Anota en usedIn que game usa version. Devuelve True si cambió algo."""
    used = manifest.setdefault("usedIn", [])
    today = date.today().isoformat()
    for entry in used:
        if entry.get("game") == game:
            if entry.get("version") == version:
                return False
            entry.update(version=version, date=today, source=source)
            return True
    used.append({"game": game, "version": version, "date": today, "source": source})
    return True


def used_in_table(used: list[dict]) -> str:
    if not used:
        return "Todavía ningún juego."
    lines = ["| Juego | Versión | Fecha |", "| --- | --- | --- |"]
    lines += [f"| {entry['game']} | {entry['version']} | {entry['date']} |" for entry in used]
    return "\n".join(lines)


def set_readme_section(text: str, heading: str, body: str) -> str:
    pattern = re.compile(rf"(^## {re.escape(heading)}[ \t]*\n)(.*?)(?=^## |\Z)", re.M | re.S)
    if not pattern.search(text):
        return text.rstrip("\n") + f"\n\n## {heading}\n\n{body.strip()}\n"
    return pattern.sub(lambda match: f"{match.group(1)}\n{body.strip()}\n\n", text, count=1).rstrip("\n") + "\n"


def sync_readme(folder: Path, manifest: dict) -> None:
    path = folder / "README.md"
    if not path.exists():
        return
    text = re.sub(r"Versión \d+\.\d+\.\d+", f"Versión {manifest['version']}", path.read_text(encoding="utf-8"), count=1)
    write_text(path, set_readme_section(text, "Juegos que lo usan", used_in_table(manifest.get("usedIn") or [])))


def add_changelog_entry(path: Path, version: str, notes: list[str]) -> None:
    text = path.read_text(encoding="utf-8") if path.exists() else f"# Historial de {path.parent.name}\n\n"
    entry = f"## {version} — {date.today().isoformat()}\n\n" + "".join(f"- {note}\n" for note in notes) + "\n"
    match = re.search(r"^## ", text, re.M)
    text = text[:match.start()] + entry + text[match.start():] if match else text.rstrip("\n") + "\n\n" + entry
    write_text(path, text.rstrip("\n") + "\n")


def changelog_since(path: Path, version: str) -> list[str]:
    """Entradas del CHANGELOG más nuevas que version, de la más nueva a la más vieja."""
    if not path.exists():
        return []
    entries = []
    for part in re.split(r"^(?=## )", path.read_text(encoding="utf-8"), flags=re.M):
        match = re.match(r"## +(\d+\.\d+\.\d+)", part)
        if match and version_tuple(match.group(1)) > version_tuple(version):
            entries.append(part.strip())
    return entries


def changelog_notes(path: Path, version: str) -> list[str]:
    if not path.exists():
        return []
    for part in re.split(r"^(?=## )", path.read_text(encoding="utf-8"), flags=re.M):
        if re.match(rf"## +{re.escape(version)}\b", part):
            return [line[2:].strip() for line in part.splitlines() if line.startswith("- ")]
    return []


# --- Comandos en el juego -------------------------------------------------------

def search(library: Path, words: list[str]) -> list[dict]:
    words = [word.lower() for word in words]
    found = []
    for entry in catalog(library):
        haystack = " ".join([entry.get("name", ""), entry.get("summary", ""), " ".join(entry.get("tags", [])),
                             " ".join(entry.get("api", [])), " ".join(entry.get("events", []))]).lower()
        if all(word in haystack for word in words):
            found.append(entry)
    return found


def add(library: Path, game: Path, name: str, force: bool = False) -> list[str]:
    """Copia el módulo al juego. Devuelve la lista de pasos pendientes."""
    entry = entry_for(library, name)
    manifest = manifest_for(library, entry)
    kind = manifest["kind"]
    source = library / entry["path"] / "src"
    target = target_folder(game, kind, name)
    lock = read_lock(game)
    current = lock["modules"].get(name)
    if not force and entry["path"] in unreleased(library):
        raise LibraryError(f"{name} tiene cambios sin release en la librería: corre library.py release {name} primero "
                           "(o --force para probarlo en el juego antes)")
    # Una copia igual a la librería se puede adoptar sin --force (por ejemplo, después de publish).
    if target.exists() and not force and tree_hashes(target) != tree_hashes(source):
        if current is None:
            raise LibraryError(f"{target.relative_to(game).as_posix()} ya existe y no viene de la librería; "
                               "compáralo a mano o usa --force para reemplazarlo")
        if tree_hashes(target) != current.get("files"):
            raise LibraryError(f"la copia de {name} tiene cambios locales; llévalos a la librería o usa --force")
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__"))
    lock["library"] = lock.get("library") or library_remote(library)
    lock["modules"][name] = {
        "kind": kind,
        "version": manifest["version"],
        "commit": library_commit(library),
        "path": target.relative_to(game).as_posix(),
        "files": tree_hashes(target),
    }
    write_lock(game, lock)

    pending = []
    if kind == "bridge":
        for role in ("origin", "destination"):
            core = (manifest.get(role) or {}).get("name")
            if core and not target_folder(game, "core", core).exists():
                pending.append(f"el puente necesita el core {core}: library.py add {game.resolve().name} {core}")
    for template in manifest.get("requires", []):
        relative = KERNEL_FILES.get(template.get("template"))
        if relative and not (game / relative).exists():
            pending.append(f"falta la plantilla {template['template']} ({template.get('from')} >= {template.get('minVersion')}) en {relative}")
    config = game / "src" / "shared" / "Config.luau"
    config_text = config.read_text(encoding="utf-8") if config.exists() else ""
    for setting in manifest.get("config", []):
        last = setting["path"].split(".")[-1]
        if not re.search(rf"\b{re.escape(last)}\s*=", config_text):
            pending.append(f"Config: agrega {setting['path']} = {json.dumps(setting['default'])} ({setting['use']})")
    data = manifest.get("data")
    if data:
        schema = game / "src" / "server" / "Data" / "DataSchema.json"
        sections = json.loads(schema.read_text(encoding="utf-8")).get("sections", {}) if schema.exists() else {}
        fragment = library / entry["path"] / "data" / "section.json"
        merge = f"python roblox-data-architect/scripts/library_section.py {game.resolve().name} {fragment.as_posix()}"
        if data["section"] not in sections:
            pending.append(f"data architect: agrega la sección {data['section']} con {merge} y vuelve a correr gen_types.py")
        elif fragment.exists() and sections[data["section"]] != json.loads(fragment.read_text(encoding="utf-8")).get("definition"):
            since = current["version"] if current else "<versión que tenía el juego>"
            pending.append(f"data architect: la sección {data['section']} cambió en la librería; {merge} --since {since} "
                           "(agrega sus migraciones como versión nueva del esquema) y gen_types.py")
    pending.append(f"Mapa de módulos: fila de {name} con Origen `librería {name}@{manifest['version']}`")
    label = game_name(game)
    if not any(used.get("game") == label and used.get("version") == manifest["version"] for used in manifest.get("usedIn", [])):
        pending.append(f"librería: anota que {label} usa {name}@{manifest['version']} con library.py record {game.resolve().name}")
    return pending


def update(library: Path, game: Path, name: str, force: bool = False) -> tuple[list[str], list[str]]:
    """Copia la versión más nueva de un módulo ya copiado. Devuelve (CHANGELOG nuevo, pendientes)."""
    locked = read_lock(game)["modules"].get(name)
    if locked is None:
        raise LibraryError(f"{name} no está en {LOCK_NAME}: cópialo con library.py add")
    entry = entry_for(library, name)
    manifest = manifest_for(library, entry)
    old, new = locked["version"], manifest["version"]
    if version_tuple(new) <= version_tuple(old) and not force:
        return [], [f"{name}@{old} ya es la versión más nueva de la librería"]
    changes = changelog_since(library / entry["path"] / "CHANGELOG.md", old)
    pending = add(library, game, name, force)
    if version_tuple(new)[0] > version_tuple(old)[0]:
        pending.insert(0, f"versión mayor ({old} → {new}): revisa en Game las llamadas, los eventos y las opciones que cambiaron")
    for bridge, role, versions in bridges_of(library, name):
        bridge_lock = read_lock(game)["modules"].get(bridge)
        if bridge_lock and not _in_range(new, versions):
            pending.append(f"el puente {bridge} del juego pide {name} {versions}: actualízalo con library.py update {game.resolve().name} {bridge}")
    return changes, pending


def _in_range(version: str, spec: str) -> bool:
    match = re.fullmatch(r"\^(\d+)\.(\d+)\.(\d+)", spec or "")
    if not match:
        return False
    wanted = tuple(int(part) for part in match.groups())
    current = version_tuple(version)
    return current[0] == wanted[0] and current >= wanted


def status(library: Path | None, game: Path) -> list[dict]:
    lock = read_lock(game)
    versions = {entry["name"]: entry["version"] for entry in catalog(library)} if library else {}
    rows = []
    for name, locked in lock["modules"].items():
        folder = game / locked["path"]
        if not folder.exists():
            state = "falta la carpeta"
        elif tree_hashes(folder) != locked.get("files"):
            state = "con cambios locales"
        else:
            state = "igual a la librería"
        latest = versions.get(name)
        rows.append({
            "name": name,
            "version": locked["version"],
            "state": state,
            "latest": latest,
            "update": bool(latest and version_tuple(latest) > version_tuple(locked["version"])),
        })
    return rows


def locked_source(library: Path, entry: dict, version: str) -> dict[str, str]:
    """Archivos de src/ de una versión del módulo: de su etiqueta <Nombre>@<versión> si existe, si no los actuales."""
    files: dict[str, str] = {}
    tag = f"{entry['name']}@{version}"
    prefix = f"{entry['path']}/src/"
    try:
        listing = subprocess.run(["git", "-C", str(library), "ls-tree", "-r", "--name-only", tag, prefix],
                                 capture_output=True, text=True, check=True).stdout.split()
        for path in listing:
            content = subprocess.run(["git", "-C", str(library), "show", f"{tag}:{path}"],
                                     capture_output=True, text=True, encoding="utf-8", check=True).stdout
            files[path[len(prefix):]] = content
        if files:
            return files
    except (OSError, subprocess.CalledProcessError):
        pass
    source = library / entry["path"] / "src"
    return {path.relative_to(source).as_posix(): path.read_text(encoding="utf-8") for path in sorted(source.rglob("*.luau"))}


def diff(library: Path, game: Path, name: str) -> str:
    lock = read_lock(game)
    locked = lock["modules"].get(name)
    if locked is None:
        raise LibraryError(f"{name} no está en {LOCK_NAME}")
    entry = entry_for(library, name)
    original = locked_source(library, entry, locked["version"])
    folder = game / locked["path"]
    current = {path.relative_to(folder).as_posix(): path.read_text(encoding="utf-8")
               for path in sorted(folder.rglob("*.luau"))} if folder.exists() else {}
    chunks = []
    for path in sorted(set(original) | set(current)):
        before = original.get(path, "").replace("\r\n", "\n").splitlines(keepends=True)
        after = current.get(path, "").replace("\r\n", "\n").splitlines(keepends=True)
        chunks += difflib.unified_diff(before, after, f"librería/{name}@{locked['version']}/{path}", f"juego/{path}")
    return "".join(chunks)


# --- Borrador de un módulo nuevo (publish) ------------------------------------------

def find_game_module(game: Path, name: str) -> tuple[Path, str]:
    for kind, directory in (("core", "Modules"), ("bridge", "Bridges")):
        for side in ("server", "shared", "client"):
            folder = game / "src" / side / directory / name
            if (folder / "init.luau").exists():
                if side != "server":
                    raise LibraryError(f"la librería guarda módulos de servidor y {name} está en src/{side}")
                return folder, kind
    raise LibraryError(f"no encuentro {name} en src/server/Modules ni en src/server/Bridges de {game.resolve().name}")


def luau_value(text: str):
    text = text.strip().rstrip(",").strip()
    if text in ("true", "false"):
        return text == "true"
    for cast in (int, float):
        try:
            return cast(text)
        except ValueError:
            pass
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    return text


def config_values(game: Path) -> dict:
    """Valores de src/shared/Config.luau por ruta (Seccion.Valor)."""
    path = game / "src" / "shared" / "Config.luau"
    if not path.exists():
        return {}
    values: dict = {}
    stack: list[str] = []
    started = False
    for line in strip_comments(path.read_text(encoding="utf-8")).splitlines():
        line = line.strip()
        if not started:
            started = bool(re.match(r"local\s+Config\s*=\s*\{", line))
            continue
        if line.startswith("}"):
            if not stack:
                break
            stack.pop()
            continue
        match = re.match(r"(\w+)\s*=\s*\{\s*$", line)
        if match:
            stack.append(match.group(1))
            continue
        match = re.match(r"(\w+)\s*=\s*(.+?)\s*$", line)
        if match:
            values[".".join(stack + [match.group(1)])] = luau_value(match.group(2))
    return values


def gdd_rows(game: Path) -> dict[str, list[str]]:
    """Filas del GDD cuya primera columna es `algo`: Parámetros ajustables y Mapa de módulos."""
    gdd = game / "GDD.md"
    rows: dict[str, list[str]] = {}
    if gdd.exists():
        for match in re.finditer(r"^\|\s*`([\w.]+)`\s*\|(.*)\|\s*$", gdd.read_text(encoding="utf-8"), re.M):
            rows.setdefault(match.group(1), [cell.strip() for cell in match.group(2).split("|")])
    return rows


def draft_manifest(library: Path, game: Path, folder: Path, name: str, kind: str, tags: list[str], version: str) -> tuple[dict, dict | None]:
    raw = {path: path.read_text(encoding="utf-8") for path in sorted(folder.rglob("*.luau"))}
    main_raw = raw[folder / "init.luau"]
    main = strip_comments(main_raw)
    code = "\n".join(strip_comments(text) for text in raw.values())
    rows = gdd_rows(game)

    api = []
    for match in re.finditer(rf"^function\s+{re.escape(name)}\.(\w+)\s*\(([^)]*)\)\s*(:\s*[^\n]+?)?\s*$", main, re.M):
        api.append({"name": match.group(1), "signature": f"{match.group(1)}({' '.join(match.group(2).split())}){match.group(3) or ''}"})

    events = []
    for match in re.finditer(rf"\b{re.escape(name)}\.(\w+)\s*=\s*Signal\.new\(\)\s*(?:::\s*Signal\.Signal<([^>\n]*)>)?", main):
        event, types = match.group(1), [part.strip() for part in (match.group(2) or "").split(",") if part.strip()]
        fire = re.search(rf"\b{re.escape(name)}\.{event}:Fire\(([^)\n]*)\)", code)
        names = [part.strip() for part in fire.group(1).split(",") if part.strip()] if fire else []
        if names and len(names) == len(types):
            args = "(" + ", ".join(f"{arg}: {kind_}" for arg, kind_ in zip(names, types)) + ")"
        elif names or types:
            args = "(" + ", ".join(names or types) + ")"
        else:
            args = PENDING
        events.append({"name": event, "args": args})

    options: dict[str, str] = {}
    block = re.search(r"export type Options\s*=\s*\{(.*?)\n\}", main_raw, re.S)
    if block:
        for line in block.group(1).splitlines():
            match = re.match(r"\s*(\w+)\s*:.*?(?:--\s*(.*))?$", line)
            if match:
                options[match.group(1)] = (match.group(2) or PENDING).strip()
    for key in re.findall(r"\boptions\.(\w+)", code):
        options.setdefault(key, PENDING)

    values = config_values(game)
    config = []
    for path in sorted(set(re.findall(r"\bTuning\.get\(\s*[\"']([^\"']+)[\"']", code))):
        value = values.get(path)
        kind_ = ("boolean" if isinstance(value, bool) else "number" if isinstance(value, (int, float))
                 else "string" if isinstance(value, str) else PENDING)
        row = rows.get(path)
        config.append({"path": path, "type": kind_, "default": PENDING if value is None else value,
                       "use": row[1] if row and len(row) > 1 and row[1] else PENDING})

    checker = library_tool(library, "check_library")
    templates = []
    for expression in (part for text in raw.values() for part in checker.requires_of(strip_comments(text))):
        for template, pattern in checker.KERNEL.items():
            if re.search(pattern, expression) and template not in templates:
                templates.append(template)
    requires = [{"template": template, "from": KERNEL_SINCE[template][0], "minVersion": KERNEL_SINCE[template][1]}
                for template in sorted(templates, key=list(KERNEL_SINCE).index)]

    fragment = None
    sections = sorted(set(re.findall(r"\bPlayerData\.section\s*\([^,]+,\s*[\"'](\w+)[\"']", code)))
    if len(sections) > 1:
        raise LibraryError(f"{name} usa las secciones {', '.join(sections)}; un módulo de la librería usa solo la suya")
    if sections:
        schema_path = game / "src" / "server" / "Data" / "DataSchema.json"
        schema = json.loads(schema_path.read_text(encoding="utf-8")) if schema_path.exists() else {}
        definition = (schema.get("sections") or {}).get(sections[0])
        if not isinstance(definition, dict):
            raise LibraryError(f"{name} usa la sección {sections[0]} y no está en DataSchema.json del juego")
        fragment = {"section": sections[0], "definition": definition, "migrations": []}

    row = rows.get(name)
    manifest: dict = {
        "name": name,
        "kind": kind,
        "version": version,
        "status": "experimental",
        "summary": row[1] if row and len(row) > 1 and row[1] else PENDING,
        "tags": tags or [PENDING],
    }
    if kind == "bridge":
        for role, core in zip(("origin", "destination"), name.split("_", 1)):
            core_folder = module_dir(library, core)
            if core_folder is None:
                raise LibraryError(f"el puente une a {core}, que no está en la librería: publícalo primero "
                                   f"(library.py publish {game.resolve().name} {core})")
            manifest[role] = {"name": core, "versions": "^" + read_manifest(core_folder)["version"]}
    manifest.update({
        "api": api,
        "events": events,
        "options": options,
        "config": config,
        "data": {"section": fragment["section"]} if fragment else None,
        "requires": requires,
        "usedIn": [],
    })
    record_use(manifest, game_name(game), version, game_source(game))
    return manifest, fragment


def draft_readme(manifest: dict, game: str) -> str:
    name, kind = manifest["name"], manifest["kind"]
    layer = "Modules" if kind == "core" else "Bridges"
    calls = {entry["name"] for entry in manifest["api"]}
    usage = [f"local {name} = require(script.Parent.{layer}.{name})", ""]
    if "init" in calls:
        usage.append(f"{name}.init({{ {PENDING} }})")
    if "connect" in calls:
        usage.append(f"{name}.connect({{ {PENDING} }})" if manifest["options"] else f"{name}.connect()")
    if "start" in calls:
        usage.append(f"{name}.start()")
    api = ["| Función | Qué hace |", "| --- | --- |"] + [f"| `{entry['signature']}` | {PENDING} |" for entry in manifest["api"]]
    events = (["| Evento | Argumentos |", "| --- | --- |"] + [f"| `{entry['name']}` | `{entry['args']}` |" for entry in manifest["events"]]
              if manifest["events"] else ["No tiene eventos."])
    options = [f"- `{key}`: {text}" for key, text in manifest["options"].items()] or ["No recibe opciones."]
    config = (["| Ruta | Valor sugerido | Uso |", "| --- | --- | --- |"]
              + [f"| `{entry['path']}` | {json.dumps(entry['default'], ensure_ascii=False)} | {entry['use']} |" for entry in manifest["config"]]
              if manifest["config"] else ["No lee ajustes de Config."])
    data = (f"Sección `{manifest['data']['section']}` (ver `data/section.json`). {PENDING}: qué guarda y qué fachada la usa."
            if manifest["data"] else "No guarda datos.")
    where = "src/server/Modules" if kind == "core" else "src/server/Bridges"
    parts = [
        f"# {name}",
        f"Versión {manifest['version']} · {'core' if kind == 'core' else 'puente'} · {manifest['status']}",
        f"## Para qué sirve\n\n{manifest['summary']} {PENDING}: qué resuelve, qué no sabe y qué recibe de Game.",
        f"## Cómo se usa\n\nCopia `src/` a `{where}/{name}/` (o `library.py add <Juego> {name}`). En `Game`:\n\n```lua\n" + "\n".join(usage) + "\n```",
        "## API\n\n" + "\n".join(api),
        "## Eventos\n\n" + "\n".join(events),
        "## Opciones\n\n" + "\n".join(options),
        "## Ajustes de Config\n\n" + "\n".join(config),
        f"## Datos que guarda\n\n{data}",
        f"## Límites\n\n- {PENDING}: casos que no cubre.",
        "## Juegos que lo usan\n\n" + used_in_table(manifest["usedIn"]),
        "## Historial\n\nVer `CHANGELOG.md`.",
    ]
    return "\n\n".join(parts) + "\n"


def draft_spec(manifest: dict) -> str:
    name = manifest["name"]
    loader = "t.module" if manifest["kind"] == "core" else "t.bridge"
    checks = "\n".join(f'\ttruthy(type({name}.{entry["name"]}) == "function", "{entry["name"]}")' for entry in manifest["api"])
    return (
        'local Harness = require("../../../tools/harness")\n'
        'local Test = require("../../../tools/module_test")\n\n'
        "local test, truthy = Harness.test, Harness.truthy\n\n"
        "local t = Test.new()\n"
        f'local {name} = {loader}("{name}")\n\n'
        'test("expone su API", function()\n'
        f"{checks}\n"
        "end)\n\n"
        f"-- {PENDING}: pruebas de su comportamiento, como las de los otros módulos de la librería.\n\n"
        "Harness.run()\n"
    )


def pending_files(folder: Path) -> list[str]:
    return sorted(path.relative_to(folder).as_posix() for path in folder.rglob("*")
                  if path.is_file() and "src" not in path.relative_to(folder).parts[:1]
                  and PENDING in path.read_text(encoding="utf-8", errors="replace"))


def publish(library: Path, game: Path, name: str, tags: list[str] | None = None, version: str = "1.0.0") -> list[str]:
    """Copia un core o puente propio del juego a una branch de la librería, con el borrador de su documentación."""
    if module_dir(library, name):
        raise LibraryError(f"{name} ya está en la librería: para cambiarlo usa library.py bump")
    if name in read_lock(game)["modules"]:
        raise LibraryError(f"{name} ya viene de la librería según {LOCK_NAME}")
    if not SEMVER_RE.fullmatch(version):
        raise LibraryError("la versión debe ser semver (x.y.z)")
    folder, kind = find_game_module(game, name)
    manifest, fragment = draft_manifest(library, game, folder, name, kind, tags or [], version)
    branch = work_branch(library, f"module/{name}")
    target = library / ("modules" if kind == "core" else "bridges") / name
    shutil.copytree(folder, target / "src", ignore=shutil.ignore_patterns("__pycache__"))
    write_json(target / "module.json", manifest)
    if fragment:
        write_json(target / "data" / "section.json", fragment)
    label = game_name(game)
    write_text(target / "README.md", draft_readme(manifest, label))
    write_text(target / "CHANGELOG.md", f"# Historial de {name}\n\n## {version} — {date.today().isoformat()}\n\n"
                                         f"- Primera versión, sacada de {label} ({manifest['usedIn'][0]['source']}).\n")
    write_text(target / "tests" / f"{name.lower()}.spec.luau", draft_spec(manifest))
    rebuild_catalog(library)
    errors, _ = check(library)
    pending = [f"borrador en {target.relative_to(library).as_posix()} (branch {branch} de la librería)"]
    files = pending_files(target)
    if files:
        pending.append(f"completa lo marcado {PENDING} en: {', '.join(files)}")
    pending.append(f"revisa que el código no traiga contenido de {label} (nombres, textos, IDs): entra por las opciones")
    if fragment:
        pending.append(f"la sección {fragment['section']} empieza en su forma actual: las migraciones del juego no se copian")
    pending += [f"check_library: {error}" for error in errors]
    pending.append(f"cuando esté completo: library.py release {name}; después library.py add {game.resolve().name} {name} "
                   f"y Origen `librería {name}@{version}` en el Mapa de módulos")
    return pending


# --- Mejorar, publicar y registrar en la librería -------------------------------------

def bump(library: Path, name: str, part: str, notes: list[str], from_game: Path | None = None) -> list[str]:
    """Sube la versión de un módulo de la librería en una branch. Con from_game, trae los cambios de su copia."""
    folder = module_dir(library, name)
    if folder is None:
        raise LibraryError(f"{name} no está en la librería: para agregarlo usa library.py publish")
    manifest = read_manifest(folder)
    old = manifest["version"]
    new = next_version(old, part)
    if folder.relative_to(library).as_posix() in unreleased(library) and not git(library, "tag", "--list", f"{name}@{old}"):
        raise LibraryError(f"{name}@{old} todavía no tiene release: sigue con esa versión y corre library.py release {name}")
    locked = None
    if from_game is not None:
        locked = read_lock(from_game)["modules"].get(name)
        if locked is None:
            raise LibraryError(f"{from_game.resolve().name} no copió {name} de la librería")
        if locked["version"] != old:
            raise LibraryError(f"{from_game.resolve().name} tiene {name}@{locked['version']} y la librería {old}: actualiza el juego primero")
    branch = work_branch(library, f"module/{name}-{new}")
    pending = [f"{name} {old} → {new} en la branch {branch} de la librería"]
    if from_game is not None and locked is not None:
        copy = from_game / locked["path"]
        if tree_hashes(copy) == locked.get("files"):
            pending.append(f"la copia de {from_game.resolve().name} no tiene cambios: haz el cambio en src/ de la librería")
        else:
            shutil.rmtree(folder / "src")
            shutil.copytree(copy, folder / "src", ignore=shutil.ignore_patterns("__pycache__"))
            pending.append(f"src/ trae los cambios de {from_game.resolve().name}; revisa que no tengan contenido del juego")
        record_use(manifest, game_name(from_game), new, game_source(from_game))
    manifest["version"] = new
    write_json(folder / "module.json", manifest)
    sync_readme(folder, manifest)
    entry = list(notes) or [f"{PENDING}: qué cambia"]
    if part == "major":
        entry.append(f"Para actualizar: {PENDING} qué cambia para quien lo usa (API, eventos u opciones)")
        if manifest.get("data"):
            entry.append(f"Datos: {PENDING} si cambia la forma de la sección, sus operaciones de migración en data/section.json")
        for bridge, role, versions in bridges_of(library, name):
            pending.append(f"el puente {bridge} pide {name} {versions}: si sigue sirviendo, súbele el rango a ^{new} "
                           f"y su versión con library.py bump {bridge} patch")
    add_changelog_entry(folder / "CHANGELOG.md", new, entry)
    rebuild_catalog(library)
    pending.append("ajusta el código, el README (API, opciones, límites) y las pruebas")
    pending.append(f"cuando esté listo: library.py release {name}")
    return pending


def release(library: Path, names: list[str], run_tests: bool = True, force: bool = False) -> list[str]:
    """Revisa uno o más módulos, hace commit en la branch de la librería y etiqueta cada uno <Nombre>@<versión>.

    Varios a la vez cuando dependen entre sí: por ejemplo, un core con versión mayor y el puente
    que tuvo que subir su rango."""
    branch = current_branch(library)
    if branch in MAIN_BRANCHES:
        raise LibraryError(f"release se hace en una branch de la librería, no en {branch}: empieza con publish o bump")
    folders: dict[str, Path] = {}
    tags = []
    for name in names:
        folder = module_dir(library, name)
        if folder is None:
            raise LibraryError(f"{name} no está en la librería")
        files = pending_files(folder)
        if files:
            raise LibraryError(f"quedan partes {PENDING} en {name}: {', '.join(files)}")
        tag = f"{name}@{read_manifest(folder)['version']}"
        if git(library, "tag", "--list", tag) and not force:
            raise LibraryError(f"la etiqueta {tag} ya existe: sube la versión con library.py bump (o usa --force para moverla)")
        folders[name] = folder
        tags.append(tag)
    paths = [folder.relative_to(library).as_posix() for folder in folders.values()]
    others = sorted(changed_folders(library) - set(paths))
    if others:
        raise LibraryError(f"hay otros módulos con cambios sin commit: {', '.join(others)}; "
                           "inclúyelos en el mismo release o termínalos antes")
    rebuild_catalog(library)
    errors, warnings = check(library)
    if errors:
        raise LibraryError("check_library.py tiene errores:\n  " + "\n  ".join(errors))
    notes = []
    if run_tests:
        tested = list(names)
        for name, folder in folders.items():
            if read_manifest(folder)["kind"] == "core":
                tested += [bridge for bridge, _, _ in bridges_of(library, name) if bridge not in tested]
        result = subprocess.run([sys.executable, "tools/run_tests.py", *tested], cwd=library,
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        lines = result.stdout.strip().splitlines()
        if result.returncode == 2:
            notes.append("sin Lune: no se corrieron las pruebas de Luau (rokit install en la librería)")
        elif result.returncode != 0:
            raise LibraryError("fallan las pruebas de Luau:\n" + result.stdout[-3000:])
        else:
            notes.append(f"pruebas: {lines[-1] if lines else 'sin salida'}")
    body = []
    for name, folder in folders.items():
        version = read_manifest(folder)["version"]
        body += [f"- {note}" for note in changelog_notes(folder / "CHANGELOG.md", version)]
    short = commit(library, paths, ", ".join(tag.replace("@", " ") for tag in tags) + ("\n\n" + "\n".join(body) if body else ""))
    for tag in tags:
        git(library, "tag", *(["-f"] if force else []), tag)
    notes.insert(0, f"commit {short or 'sin cambios nuevos'} en {branch} y etiquetas {', '.join(tags)}")
    notes += [f"aviso de check_library: {warning}" for warning in warnings]
    notes.append(f"subir la branch y las etiquetas y abrir el PR lo aprueba el usuario: "
                 f"git push -u origin {branch} y git push origin {' '.join(tags)}")
    return notes


def record(library: Path, game: Path) -> list[str]:
    """Anota en usedIn de la librería la versión de cada módulo que copió el juego, y hace commit."""
    lock = read_lock(game)
    label, source = game_name(game), game_source(game)
    changes: dict[Path, dict] = {}
    missing = []
    for name, locked in lock["modules"].items():
        folder = module_dir(library, name)
        if folder is None:
            missing.append(name)
            continue
        manifest = read_manifest(folder)
        if record_use(manifest, label, locked["version"], source):
            changes[folder] = manifest
    notes = [f"{name} no está en la librería" for name in missing]
    if not changes:
        return notes + [f"usedIn ya dice qué versión usa {label} de cada módulo"]
    branch = work_branch(library, f"usage/{label}")
    for folder, manifest in changes.items():
        write_json(folder / "module.json", manifest)
        sync_readme(folder, manifest)
    rebuild_catalog(library)
    names = ", ".join(folder.name for folder in changes)
    short = commit(library, [folder.relative_to(library).as_posix() for folder in changes], f"usedIn: {label} usa {names}")
    notes.append(f"usedIn de {names}: commit {short} en {branch}")
    notes.append(f"subir la branch y abrir el PR lo aprueba el usuario: git push -u origin {branch}")
    return notes


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Consulta la librería de módulos, copia módulos a un juego y la mejora.")
    parser.add_argument("--library", help="carpeta de la librería (la que tiene catalog.json)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("search").add_argument("words", nargs="*")
    sub.add_parser("info").add_argument("name")
    for command in ("add", "update"):
        command_parser = sub.add_parser(command)
        command_parser.add_argument("game", type=Path)
        command_parser.add_argument("name")
        command_parser.add_argument("--force", action="store_true", help="reemplaza una copia con cambios locales")
    sub.add_parser("status").add_argument("game", type=Path)
    diff_parser = sub.add_parser("diff")
    diff_parser.add_argument("game", type=Path)
    diff_parser.add_argument("name")
    publish_parser = sub.add_parser("publish")
    publish_parser.add_argument("game", type=Path)
    publish_parser.add_argument("name")
    publish_parser.add_argument("--tags", default="", help="temas separados por comas, para buscarlo")
    publish_parser.add_argument("--version", default="1.0.0")
    bump_parser = sub.add_parser("bump")
    bump_parser.add_argument("name")
    bump_parser.add_argument("part", choices=["patch", "minor", "major"])
    bump_parser.add_argument("--note", action="append", default=[], help="una línea del CHANGELOG (se puede repetir)")
    bump_parser.add_argument("--from-game", type=Path, help="juego cuya copia trae el cambio")
    release_parser = sub.add_parser("release")
    release_parser.add_argument("names", nargs="+", metavar="name")
    release_parser.add_argument("--no-tests", action="store_true", help="no corre las pruebas de Luau")
    release_parser.add_argument("--force", action="store_true", help="mueve la etiqueta si ya existe")
    sub.add_parser("record").add_argument("game", type=Path)
    args = parser.parse_args(argv)
    game = getattr(args, "game", None) or getattr(args, "from_game", None)
    try:
        if args.command == "status":
            try:
                library = find_library(args.library, game)
            except LibraryError:
                library = None
            rows = status(library, game)
            if not rows:
                print(f"{game.resolve().name} no usa módulos de la librería ({LOCK_NAME} vacío o ausente)")
            for row in rows:
                latest = f"; hay {row['latest']}" if row["update"] else ""
                print(f"{row['name']}@{row['version']}: {row['state']}{latest}")
            if library is None:
                print("(sin la librería no se buscaron versiones nuevas)")
            return 1 if any(row["state"] != "igual a la librería" for row in rows) else 0
        library = find_library(args.library, game)
        if args.command == "search":
            found = search(library, args.words)
            for entry in found:
                print(f"{entry['name']}@{entry['version']} ({entry['kind']}, {entry['status']}): {entry['summary']}")
            if not found:
                print("Nada en la librería con esas palabras: escribe el módulo en el juego y propónlo al terminar.")
            return 0
        if args.command == "info":
            entry = entry_for(library, args.name)
            print(json.dumps(manifest_for(library, entry), ensure_ascii=False, indent=2))
            print(f"\nREADME: {(library / entry['path'] / 'README.md').as_posix()}")
            return 0
        if args.command == "diff":
            text = diff(library, game, args.name)
            print(text or f"{args.name}: la copia es igual a la librería")
            return 0
        if args.command == "add":
            steps = add(library, game, args.name, args.force)
            locked = read_lock(game)["modules"][args.name]
            print(f"Copiado {args.name}@{locked['version']} a {locked['path']} (commit {locked['commit'] or 'sin git'})")
        elif args.command == "update":
            changes, steps = update(library, game, args.name, args.force)
            for block in changes:
                print(block + "\n")
        elif args.command == "publish":
            tags = [tag.strip() for tag in args.tags.split(",") if tag.strip()]
            steps = publish(library, game, args.name, tags, args.version)
        elif args.command == "bump":
            steps = bump(library, args.name, args.part, args.note, args.from_game)
        elif args.command == "release":
            steps = release(library, args.names, not args.no_tests, args.force)
        else:
            steps = record(library, game)
        for step in steps:
            print(f"- {step}")
    except LibraryError as exc:
        print(f"ERROR {exc}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
