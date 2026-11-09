#!/usr/bin/env python3
"""Revisa la interfaz de un juego de la fábrica contra las reglas del UI designer.

Uso:
    python check_ui.py <carpeta-del-juego>
    python check_ui.py <carpeta-del-juego> --json

Comprueba:
  - design/UI.md existe y cada pantalla que lista (`Screens/<Nombre>.luau`) existe;
    cada módulo de Screens aparece en UI.md;
  - src/client/UI/init.client.luau (entrada) y el kit en src/client/UI/Kit con su
    API; si este skill está instalado, avisa si el kit difiere de la plantilla y si
    Kit.modal no desplaza su contenido (el botón de cerrar quedaría fuera en celulares);
  - las pantallas colocan sus elementos raíz con el kit (Kit.slot, Kit.modal,
    Kit.toast o Kit.layer) y no crean ScreenGui ni botones sueltos, que quedarían
    fuera de las zonas seguras o sin tamaño táctil;
  - src/shared/Theme.json tiene las fuentes y métricas que usa el kit;
  - los atributos que la UI lee existen en el servidor (SetAttribute) y el GDD
    documenta el "Estado para la UI".

Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

KIT_TEMPLATE = Path(__file__).resolve().parents[1] / "assets" / "templates" / "src" / "client" / "UI" / "Kit"
KIT_API = {
    "init.luau": [],
    "Layout.luau": ["start", "refresh", "slot", "layer", "scale", "chatRect", "touchRects"],
    "Components.luau": ["panel", "label", "button", "modal", "toast", "tabs", "grid", "card", "status", "bindAttribute"],
    "Input.luau": ["preferred", "onChanged", "hint", "bindAction"],
}
# Fuentes y métricas de Theme.json que usa el kit (check_art.py exige solo heading y body).
KIT_FONTS = ["heading", "body", "label", "number"]
KIT_METRICS = ["cornerRadius", "strokeThickness", "spacing", "panelTransparency", "minTouchTarget",
               "textSizeMin", "textSizeMax"]
ROOT_PLACEMENT = re.compile(r"\bKit\.(?:slot|modal|toast|layer)\s*\(")


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def strip_comments(code: str) -> str:
    code = re.sub(r"--\[(=*)\[.*?\]\1\]", "", code, flags=re.DOTALL)
    return re.sub(r"--[^\n]*", "", code)


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n")


def check_game(game: Path) -> Result:
    result = Result()
    ui_dir = game / "src" / "client" / "UI"
    doc = game / "design" / "UI.md"

    listed: set[str] = set()
    if not doc.exists():
        result.error("design/UI.md", "no existe")
    else:
        listed = set(re.findall(r"Screens/(\w+)\.luau", doc.read_text(encoding="utf-8")))
        if not listed:
            result.error("design/UI.md", "no lista pantallas con su módulo (`Screens/<Nombre>.luau`)")

    if not ui_dir.is_dir():
        result.error("src/client/UI", "no existe")
        return result
    if not (ui_dir / "init.client.luau").exists():
        result.error("src/client/UI/init.client.luau", "falta la entrada de la interfaz")

    kit = ui_dir / "Kit"
    if not kit.is_dir():
        result.error("src/client/UI/Kit", "falta el kit; cópialo de assets/templates de roblox-ui-designer")
    else:
        for name, api in KIT_API.items():
            path = kit / name
            if not path.exists():
                result.error(f"src/client/UI/Kit/{name}", "falta")
                continue
            code = strip_comments(path.read_text(encoding="utf-8"))
            module = name.removesuffix(".luau")
            missing = [f for f in api if not re.search(rf"\bfunction\s+{module}\.{f}\s*\(", code)]
            if missing:
                result.error(f"src/client/UI/Kit/{name}", f"faltan funciones del kit: {', '.join(missing)}")
            if name == "Components.luau":
                modal = re.search(r"function\s+Components\.modal\s*\(.*?\nend\n", code, flags=re.DOTALL)
                if modal and "ScrollingFrame" not in modal.group(0):
                    result.warn(
                        f"src/client/UI/Kit/{name}",
                        "Kit.modal no desplaza su contenido: en un celular en horizontal el botón de cerrar queda fuera de la pantalla",
                    )
            template = KIT_TEMPLATE / name
            if template.exists() and normalize(template.read_text(encoding="utf-8")) != normalize(path.read_text(encoding="utf-8")):
                result.warn(f"src/client/UI/Kit/{name}", "difiere de la plantilla del kit; los cambios del juego van en Screens")

    theme_path = game / "src" / "shared" / "Theme.json"
    if not theme_path.exists():
        result.error("src/shared/Theme.json", "el kit necesita el tema; pídelo al art director (roblox-art-director)")
    else:
        try:
            theme = json.loads(theme_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            result.error("src/shared/Theme.json", f"JSON inválido: {exc}")
            theme = {}
        if not isinstance(theme, dict):
            theme = {}
        fonts = theme.get("fonts") if isinstance(theme.get("fonts"), dict) else {}
        metrics = theme.get("ui") if isinstance(theme.get("ui"), dict) else {}
        missing_fonts = [k for k in KIT_FONTS if k not in fonts]
        missing_metrics = [k for k in KIT_METRICS if k not in metrics]
        if missing_fonts:
            result.error("src/shared/Theme.json", f"faltan fuentes que usa el kit: {', '.join(missing_fonts)}")
        if missing_metrics:
            result.error("src/shared/Theme.json", f"faltan métricas de UI que usa el kit: {', '.join(missing_metrics)}")

    screens_dir = ui_dir / "Screens"
    screens = {p.stem: p for p in screens_dir.glob("*.luau")} if screens_dir.is_dir() else {}
    for name in sorted(listed - set(screens)):
        result.error("design/UI.md", f"la pantalla Screens/{name}.luau no existe")
    for name in sorted(set(screens) - listed):
        result.warn(f"src/client/UI/Screens/{name}.luau", "no aparece en design/UI.md")

    client_files = [p for p in (game / "src" / "client").rglob("*.luau") if kit not in p.parents]
    read_attributes: dict[str, str] = {}
    for path in client_files:
        where = path.relative_to(game).as_posix()
        code = strip_comments(path.read_text(encoding="utf-8"))
        if re.search(r"Instance\.new\(\s*[\"']ScreenGui[\"']", code):
            result.warn(where, "crea un ScreenGui propio; usa Kit.layer o Kit.slot para respetar las zonas seguras")
        if re.search(r"Instance\.new\(\s*[\"'](?:TextButton|ImageButton)[\"']", code):
            result.warn(where, "crea botones sueltos; usa Kit.button para el tamaño táctil, el tema y el gamepad")
        if path.parent == screens_dir and not ROOT_PLACEMENT.search(code):
            result.warn(where, "la pantalla no coloca nada con Kit.slot, Kit.modal, Kit.toast ni Kit.layer")
        for attribute in re.findall(r":GetAttribute\(\s*[\"'](\w+)[\"']\s*\)", code):
            read_attributes.setdefault(attribute, where)
        for attribute in re.findall(r"bindAttribute\(\s*[^,]+,\s*[\"'](\w+)[\"']", code):
            read_attributes.setdefault(attribute, where)
        for attribute in re.findall(r"for\s+_,\s*\w+\s+in\s+\{([^}]*)\}\s+do\s+Kit\.bindAttribute", code):
            for name in re.findall(r"[\"'](\w+)[\"']", attribute):
                read_attributes.setdefault(name, where)

    server_code = "\n".join(strip_comments(p.read_text(encoding="utf-8")) for p in (game / "src").rglob("*.luau")
                            if "client" not in p.relative_to(game / "src").parts[:1])
    for attribute, where in sorted(read_attributes.items()):
        if not re.search(rf"SetAttribute\(\s*[\"']{attribute}[\"']", server_code):
            result.warn(where, f"la UI lee el atributo {attribute!r}, pero ningún script del servidor lo escribe")

    gdd = game / "GDD.md"
    if gdd.exists() and "Estado para la UI" not in gdd.read_text(encoding="utf-8"):
        result.warn("GDD.md", "falta la sección \"Estado para la UI\" en la Arquitectura (contrato del builder con la UI)")
    return result


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa la interfaz de un juego de la fábrica.")
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
        print(f"Revisión de UI: {args.game}")
        for line in result.errors:
            print(f"ERROR {line}")
        for line in result.warnings:
            print(f"WARN  {line}")
        print(f"Resultado: {len(result.errors)} errores, {len(result.warnings)} advertencias")
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
