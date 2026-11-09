#!/usr/bin/env python3
"""Estado de un juego de la fábrica: qué etapas están completas, qué falta y qué sigue.

Uso:
    python factory_status.py <carpeta-del-juego>
    python factory_status.py <carpeta-del-juego> --json
    python factory_status.py <carpeta-del-juego> --library <ruta-de-Roblox-Library>

La librería de módulos se busca como en library.py: --library, ROBLOX_LIBRARY o
project.library del GDD. Sin ella, la etapa Librería revisa solo las copias del juego.

Recorre las etapas en el orden del contrato (diseño, datos, arte, niveles, entorno,
monetización, código, módulos, librería, places, UI, analíticas, LiveOps y build), usa check_game.py del builder
(que a su vez corre los validadores de los skills instalados al lado) y lista los pedidos
abiertos de "Pendientes entre skills". Termina con el siguiente paso sugerido.

No ejecuta el juego: lo que solo se comprueba en Studio o en una experiencia
publicada aparece siempre como pendiente de verificar.
Sale con código 1 si alguna etapa tiene errores.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

SKILLS_DIR = Path(__file__).resolve().parents[2]
BUILDER_CHECK = SKILLS_DIR / "roblox-game-builder" / "scripts" / "check_game.py"
BUILDER_LIBRARY = SKILLS_DIR / "roblox-game-builder" / "scripts" / "library.py"
DESIGN_SECTIONS = ["Concepto", "Loop principal", "Onboarding", "Progresión", "Parámetros ajustables",
                   "KPIs objetivo", "Suposiciones y criterios de aceptación"]
OK, PENDING, ERROR, NOT_APPLICABLE = "ok", "pendiente", "error", "no aplica"


@dataclass
class Stage:
    name: str
    state: str
    detail: str
    next_skill: str = ""


@dataclass
class Status:
    game: str
    stages: list[Stage] = field(default_factory=list)
    open_requests: list[str] = field(default_factory=list)
    next_step: str = ""

    @property
    def has_errors(self) -> bool:
        return any(stage.state == ERROR for stage in self.stages)


def load_script(name: str, path: Path):
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


def load_builder():
    return load_script("factory_check_game", BUILDER_CHECK)


def sections(text: str) -> dict[str, str]:
    """Secciones de nivel 2 del GDD: título → contenido."""
    result: dict[str, str] = {}
    parts = re.split(r"^## +(.+?)\s*$", text, flags=re.MULTILINE)
    for title, body in zip(parts[1::2], parts[2::2]):
        result[title.strip()] = body
    return result


def summarize(messages: list[str], limit: int = 2) -> str:
    shown = "; ".join(messages[:limit])
    return shown + (f" (y {len(messages) - limit} más)" if len(messages) > limit else "")


def warning_note(warnings: list[str]) -> str:
    if not warnings:
        return ""
    return f"; {len(warnings)} advertencia" + ("s" if len(warnings) != 1 else "")


def newest_mtime(paths) -> float:
    return max((p.stat().st_mtime for p in paths), default=0.0)


DATA_DESIGN_FILES = ("src/server/Data/DataSchema.json", "src/server/Data/Migrations.luau", "src/shared/DataTypes.luau",
                     "design/DATA.md", "document", "sections", "migraciones", "migrations", "history", "tamaño", "GDD.md", "persistencia",
                     "compras", "dueños", "version", "schemaVersion", "DataSchema.json")


def data_stage(game: Path, flags: dict, report, release: bool, status: Status) -> None:
    """Etapa Datos: el diseño del data architect y su servicio, con check_data.py (vía check_game)."""
    schema_path = game / "src" / "server" / "Data" / "DataSchema.json"
    if not flags.get("data"):
        detail = "design.data no está activado" + (" (necesario si el juego promete guardar progreso)" if release else "")
        status.stages.append(Stage("Datos", NOT_APPLICABLE, detail))
        return
    if not schema_path.exists():
        status.stages.append(Stage("Datos", PENDING, "falta src/server/Data/DataSchema.json", "roblox-data-architect"))
        return
    errors = [e.removeprefix("datos: ") for e in report.errors if e.startswith("datos:")]
    warnings = [w for w in report.warnings if w.startswith(("datos:", "src/server/Data/"))]
    if errors:
        # Los errores en el código del juego (plantillas sin copiar, una sección usada fuera de su core) son del builder.
        design = [e for e in errors if e.startswith(DATA_DESIGN_FILES)]
        skill = "roblox-data-architect" if design else "roblox-game-builder"
        status.stages.append(Stage("Datos", ERROR, summarize(errors), skill))
        return
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        document = schema.get("document") or {}
        detail = f"esquema v{schema.get('version')}, {document.get('persistence')}, {len(schema.get('sections') or {})} secciones"
    except (json.JSONDecodeError, UnicodeDecodeError, AttributeError):
        detail = "esquema validado"
    if not (game / "src" / "server" / "Data" / "PlayerData.luau").exists():
        detail += "; el builder copia el servicio de datos"
    status.stages.append(Stage("Datos", OK, detail + warning_note(warnings)))


def modules_stage(game: Path, report, status: Status) -> None:
    """Etapa Módulos: las capas del código (cores, puentes y Game) con check_modules.py (vía check_game)."""
    src = game / "src"
    if not src.is_dir():
        status.stages.append(Stage("Módulos", NOT_APPLICABLE, "todavía no hay código"))
        return
    errors = [e.removeprefix("módulos: ") for e in report.errors if e.startswith("módulos:")]
    warnings = [w for w in report.warnings if w.startswith("módulos:")]
    if errors:
        status.stages.append(Stage("Módulos", ERROR, summarize(errors), "roblox-game-builder"))
        return
    if any(note.startswith("módulos:") and "M7" in note for note in report.info):
        status.stages.append(Stage("Módulos", OK, "proyecto plano, sin capas (los juegos nuevos usan cores, puentes y Game)"
                                   + warning_note(warnings)))
        return
    cores = {path.name.removesuffix(".luau") for path in src.glob("*/Modules/*")}
    bridges = {path.name.removesuffix(".luau") for path in src.glob("*/Bridges/*")}
    detail = f"{len(cores)} core" + ("s" if len(cores) != 1 else "") + f", {len(bridges)} puente" + ("s" if len(bridges) != 1 else "")
    status.stages.append(Stage("Módulos", OK, detail + warning_note(warnings)))


def library_stage(game: Path, library_path: str | None, status: Status) -> None:
    """Etapa Librería: módulos copiados de Roblox-Library, sus versiones y los propios que se podrían publicar."""
    lib = load_script("factory_library", BUILDER_LIBRARY)
    src = game / "src" / "server"
    if lib is None or not src.is_dir():
        status.stages.append(Stage("Librería", NOT_APPLICABLE, "todavía no hay código" if lib else "falta library.py del builder"))
        return
    try:
        library = lib.find_library(library_path, game)
    except lib.LibraryError:
        library = None
    catalog = {entry["name"]: entry for entry in lib.catalog(library)} if library else {}
    lock = lib.read_lock(game)
    own = sorted(path.name for folder in ("Modules", "Bridges") for path in (src / folder).glob("*")
                 if path.is_dir() and path.name not in lock["modules"] and path.name != "__pycache__")
    candidates = [name for name in own if name not in catalog]
    if not lock["modules"]:
        detail = "no usa la librería"
        if library and candidates:
            detail += f"; propios que se podrían publicar: {', '.join(candidates)} (library.py publish)"
        elif not library:
            detail += " (no se encontró la librería en la máquina)"
        status.stages.append(Stage("Librería", NOT_APPLICABLE, detail))
        return
    rows = lib.status(library, game)
    problems = [f"falta la carpeta de {row['name']}" for row in rows if row["state"] == "falta la carpeta"]
    if library:
        problems += [f"{row['name']}@{row['version']} no existe en la librería" for row in rows
                     if row["latest"] is None or lib.version_tuple(row["version"]) > lib.version_tuple(row["latest"])]
    if problems:
        status.stages.append(Stage("Librería", ERROR, summarize(problems), "roblox-game-builder"))
        return
    changed = [row["name"] for row in rows if row["state"] == "con cambios locales"]
    if changed:
        status.stages.append(Stage("Librería", PENDING, f"{', '.join(changed)} difiere de su versión de la librería: llévalo con "
                                   "library.py bump --from-game y release, o vuelve a copiarlo", "roblox-game-builder"))
        return
    notes = [f"{len(rows)} módulo" + ("s" if len(rows) != 1 else "") + " de la librería"]
    updates = [f"{row['name']} {row['latest']}" for row in rows if row["update"]]
    if updates:
        notes.append(f"versiones nuevas: {', '.join(updates)} (library.py update)")
    if library:
        label = lib.game_name(game)
        unrecorded = [row["name"] for row in rows if not any(
            used.get("game") == label and used.get("version") == row["version"]
            for used in lib.manifest_for(library, catalog[row["name"]]).get("usedIn", []))]
        if unrecorded:
            notes.append(f"usedIn no anota {', '.join(unrecorded)} (library.py record)")
        if candidates:
            notes.append(f"propios que se podrían publicar: {', '.join(candidates)}")
    else:
        notes.append("sin la librería en la máquina no se buscaron versiones nuevas")
    status.stages.append(Stage("Librería", OK, "; ".join(notes)))


def factory_status(game: Path, library: str | None = None) -> Status:
    status = Status(game=str(game))
    builder = load_builder()
    if builder is None:
        status.stages.append(Stage("Fábrica", ERROR, "falta roblox-game-builder al lado de este skill", "roblox-game-builder"))
        return status

    gdd_path = game / "GDD.md"
    gdd_text = gdd_path.read_text(encoding="utf-8") if gdd_path.exists() else ""
    gdd_sections = sections(gdd_text)
    report = builder.check_game(game)
    flags = {"levels": False, "art": False, "environment": False, "ui": False, "data": False, "analytics": False,
             "liveops": False, "monetization": [], "places": []}
    try:
        frontmatter = builder.read_frontmatter(gdd_text) if gdd_text else {}
        flags = builder.check_frontmatter(frontmatter, builder.Report())
    except Exception:
        frontmatter = {}

    def messages(prefix: str) -> tuple[list[str], list[str]]:
        return ([e for e in report.errors if e.startswith(prefix)], [w for w in report.warnings if w.startswith(prefix)])

    # Diseño
    if not gdd_text:
        status.stages.append(Stage("Diseño", PENDING, "no hay GDD.md", "roblox-game-designer"))
    else:
        missing = [name for name in DESIGN_SECTIONS if name not in gdd_sections]
        gdd_errors = [e for e in report.errors if e.startswith("GDD.md")]
        if gdd_errors:
            status.stages.append(Stage("Diseño", ERROR, summarize(gdd_errors), "roblox-game-designer"))
        elif missing:
            status.stages.append(Stage("Diseño", PENDING, f"faltan secciones: {', '.join(missing)}", "roblox-game-designer"))
        else:
            status.stages.append(Stage("Diseño", OK, f"modo {flags.get('mode') or frontmatter.get('project', {}).get('mode', '?')}"))

    release = flags.get("mode") == "release-candidate"

    # Datos del jugador (después del diseño: usa lo que el GDD promete conservar)
    data_stage(game, flags, report, release, status)

    def visual_stage(name: str, flag: str, artifact: Path, prefix: str, skill: str, ok_detail: str) -> None:
        """Etapa de un skill visual: arte, entorno o UI."""
        if not flags.get(flag):
            detail = f"design.{flag} no está activado" + (" (recomendado para publicar)" if release else "")
            status.stages.append(Stage(name, NOT_APPLICABLE, detail))
            return
        if not artifact.exists():
            status.stages.append(Stage(name, PENDING, f"falta {artifact.relative_to(game).as_posix()}", skill))
            return
        errors, warnings = messages(prefix)
        if errors:
            status.stages.append(Stage(name, ERROR, summarize(errors), skill))
        else:
            status.stages.append(Stage(name, OK, ok_detail + warning_note(warnings)))

    # Arte
    visual_stage("Arte", "art", game / "src" / "shared" / "Theme.json", "arte:", "roblox-art-director", "tema validado")

    # Niveles
    if not flags["levels"]:
        status.stages.append(Stage("Niveles", NOT_APPLICABLE, "design.levels no está activado"))
    else:
        errors = [e for e in report.errors if e.startswith(("src/shared/Levels.json", "design/LEVELS.md"))]
        warnings = [w for w in report.warnings if w.startswith("src/shared/Levels.json")]
        if errors:
            status.stages.append(Stage("Niveles", ERROR, summarize(errors), "roblox-level-designer"))
        else:
            detail = "Levels.json validado" + warning_note(warnings)
            status.stages.append(Stage("Niveles", OK, detail))

    # Entorno (pase de arte)
    visual_stage("Entorno", "environment", game / "src" / "shared" / "Environment.json", "entorno:", "roblox-environment-artist",
                 "pase de arte validado")

    # Monetización
    enabled = flags.get("monetization") or []
    if not enabled:
        status.stages.append(Stage("Monetización", NOT_APPLICABLE, "monetization.enabled está vacío"))
    else:
        section = gdd_sections.get("Monetización seleccionada", "")
        pending_ids = len(re.findall(r"pendiente", section, flags=re.IGNORECASE))
        if not section.strip():
            status.stages.append(Stage("Monetización", PENDING, "falta la sección Monetización seleccionada", f"roblox-monetization-{enabled[0]}"))
        elif pending_ids:
            status.stages.append(Stage("Monetización", PENDING,
                                       f"{', '.join(enabled)}: {pending_ids} datos pendientes (IDs o configuración en Creator Hub); las compras siguen desactivadas",
                                       "usuario (Creator Hub)"))
        else:
            status.stages.append(Stage("Monetización", OK, ", ".join(enabled)))

    # Código
    other_prefixes = ("GDD.md", "src/shared/Levels.json", "design/LEVELS.md", "arte:", "src/shared/Theme.json",
                      "entorno:", "src/shared/Environment.json", "ui:", "src/client/UI:", "places:", "analíticas", "liveops",
                      "datos:", "src/server/Data/DataSchema.json", "módulos:")
    code_errors = [e for e in report.errors if not e.startswith(other_prefixes)]
    code_warnings = [w for w in report.warnings if not w.startswith(other_prefixes)]
    if not (game / "src").is_dir():
        status.stages.append(Stage("Código", PENDING, "no hay carpeta src/", "roblox-game-builder"))
    elif code_errors:
        status.stages.append(Stage("Código", ERROR, summarize(code_errors), "roblox-game-builder"))
    else:
        detail = "check_game sin errores" + warning_note(code_warnings)
        status.stages.append(Stage("Código", OK, detail))

    # Módulos (capas del código)
    modules_stage(game, report, status)

    # Librería (módulos copiados de Roblox-Library)
    library_stage(game, library, status)

    # Places (experiencias con varios places)
    places = flags.get("places") or []
    if len(places) <= 1:
        status.stages.append(Stage("Places", NOT_APPLICABLE, "un solo place"))
    else:
        errors, warnings = messages("places:")
        pending = [w for w in warnings if "PlaceId pendiente" in w]
        names = ", ".join(str(place.get("id")) for place in places)
        if errors:
            status.stages.append(Stage("Places", ERROR, summarize(errors), "roblox-game-builder"))
        elif pending:
            status.stages.append(Stage("Places", PENDING, f"{len(places)} places ({names}); faltan PlaceId: crearlos en la experiencia y cargarlos",
                                       "usuario (Creator Hub)"))
        else:
            status.stages.append(Stage("Places", OK, f"{len(places)} places ({names})" + warning_note(warnings)))

    # UI (después del builder: se apoya en el estado que publica)
    visual_stage("UI", "ui", game / "src" / "client" / "UI", "ui:", "roblox-ui-designer", "interfaz validada")

    # Analíticas y LiveOps
    for name, flag, prefix, module, skill in (
        ("Analíticas", "analytics", "analíticas", game / "src" / "server" / "Analytics.luau", "roblox-analytics-dev"),
        ("LiveOps", "liveops", "liveops", game / "src" / "shared" / "LiveConfig.luau", "roblox-liveops"),
    ):
        if not flags[flag]:
            status.stages.append(Stage(name, NOT_APPLICABLE, f"{flag}.enabled no está activado"))
            continue
        errors, warnings = messages(prefix)
        if not module.exists():
            status.stages.append(Stage(name, PENDING, f"falta {module.name}", skill))
        elif errors:
            status.stages.append(Stage(name, ERROR, summarize(errors), skill))
        else:
            status.stages.append(Stage(name, OK, "validado" + warning_note(warnings)))

    # Build
    builds = list((game / "build").glob("*.rbxlx")) + list((game / "build").glob("*.rbxl"))
    sources = [p for p in (game / "src").rglob("*") if p.is_file()] if (game / "src").is_dir() else []
    expected = max(len(places), 1)
    if not builds:
        status.stages.append(Stage("Build", PENDING, "no hay place generado", "rojo build -o build/<Juego>.rbxlx"))
    elif len(builds) < expected:
        status.stages.append(Stage("Build", PENDING, f"hay {len(builds)} de {expected} places construidos",
                                   "rojo build de default.project.json y de cada places/<place>.project.json"))
    elif newest_mtime(builds) < newest_mtime(sources):
        status.stages.append(Stage("Build", PENDING, "el place es anterior a los últimos cambios de src/", "rojo build -o build/<Juego>.rbxlx"))
    else:
        status.stages.append(Stage("Build", OK, ", ".join(p.name for p in builds)))

    # Siempre pendiente: lo que no se puede comprobar desde los archivos.
    checks = ["recorrer el loop completo"]
    if flags.get("ui"):
        checks.append("la UI en PC, celular y consola emulados")
    if flags.get("environment"):
        checks.append("la decoración de cada nivel")
    if flags.get("data"):
        checks.append("salir y volver para comprobar el guardado (con acceso a las APIs)")
    if len(places) > 1:
        checks.append("cada place por separado (los viajes entre places solo funcionan en la experiencia publicada)")
    detail = ", ".join(checks[:-1]) + (" y " if len(checks) > 1 else "") + checks[-1]
    status.stages.append(Stage("Studio", PENDING, f"{detail}; no se puede comprobar desde los archivos", "usuario (Roblox Studio)"))

    requests = gdd_sections.get("Pendientes entre skills", "")
    status.open_requests = [line.strip("-* \t") for line in requests.splitlines() if "(abierto)" in line.lower()]

    for stage in status.stages:
        if stage.state in {ERROR, PENDING}:
            status.next_step = f"{stage.name}: {stage.detail} → {stage.next_skill}"
            break
    return status


def format_status(status: Status) -> str:
    lines = [f"Estado de {status.game}", "", "| Etapa | Estado | Detalle | Siguiente |", "| --- | --- | --- | --- |"]
    for stage in status.stages:
        lines.append(f"| {stage.name} | {stage.state} | {stage.detail} | {stage.next_skill} |")
    lines.append("")
    if status.open_requests:
        lines.append("Pendientes abiertos entre skills:")
        lines.extend(f"- {request}" for request in status.open_requests)
        lines.append("")
    lines.append(f"Siguiente paso: {status.next_step or 'nada pendiente'}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Estado de un juego de la fábrica.")
    parser.add_argument("game", type=Path, help="carpeta del juego (la que contiene GDD.md)")
    parser.add_argument("--json", action="store_true", help="imprime el resultado como JSON")
    parser.add_argument("--library", help="carpeta de Roblox-Library (si no, ROBLOX_LIBRARY o project.library del GDD)")
    args = parser.parse_args(argv)
    if not args.game.is_dir():
        print(f"ERROR no existe la carpeta {args.game}")
        return 2
    status = factory_status(args.game.resolve(), args.library)
    if args.json:
        data = asdict(status)
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(format_status(status))
    return 1 if status.has_errors else 0


if __name__ == "__main__":
    sys.exit(main())
