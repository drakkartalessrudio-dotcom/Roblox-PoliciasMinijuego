#!/usr/bin/env python3
"""Revisa la dirección de arte de un juego de la fábrica: Theme.json y ART.md.

Uso:
    python check_art.py <carpeta-del-juego>
    python check_art.py <carpeta-del-juego> --json
    python check_art.py --theme <ruta/Theme.json>      # solo el tema

Comprueba:
  - formato de src/shared/Theme.json: paleta en hexadecimal, roles que apuntan a
    colores de la paleta, materiales, fuentes y pesos de Roblox, métricas de UI y
    presets de iluminación con propiedades y rangos válidos;
  - contraste de texto (WCAG): 4,5:1 para texto y 3:1 para elementos de UI;
  - legibilidad de juego: los colores que el jugador debe distinguir (peligro,
    interactivo, meta, recompensa y superficie) se separan por al menos minDeltaE
    en visión normal y en protanopia, deuteranopia y tritanopia simuladas;
  - design/ART.md existe y nombra cada color de la paleta.

Las listas de fuentes, pesos y materiales salen de las definiciones de tipos de
Roblox de luau-lsp (2026-10-12). Sale con código 1 si hay errores.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

FONTS = {
    "AmaticSC", "Antique", "Arcade", "Arial", "ArialBold", "Arimo", "ArimoBold", "Bangers", "Bodoni",
    "BuilderSans", "BuilderSansBold", "BuilderSansExtraBold", "BuilderSansMedium", "Cartoon", "Code",
    "Creepster", "DenkOne", "Fantasy", "Fondamento", "FredokaOne", "Garamond", "Gotham", "GothamBlack",
    "GothamBold", "GothamMedium", "GrenzeGotisch", "Highway", "IndieFlower", "JosefinSans", "Jura", "Kalam",
    "Legacy", "LuckiestGuy", "Merriweather", "Michroma", "Nunito", "Oswald", "PatrickHand", "PermanentMarker",
    "Roboto", "RobotoCondensed", "RobotoMono", "Sarpanch", "SciFi", "SourceSans", "SourceSansBold",
    "SourceSansItalic", "SourceSansLight", "SourceSansSemibold", "SpecialElite", "TitilliumWeb", "Ubuntu",
}
DEPRECATED_FONTS = {"Arial", "ArialBold", "Gotham", "GothamBlack", "GothamBold", "GothamMedium", "Legacy"}
WEIGHTS = {"Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy"}
MATERIALS = {
    "Asphalt", "Basalt", "Brick", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles", "Cobblestone",
    "Concrete", "CorrodedMetal", "CrackedLava", "DiamondPlate", "Fabric", "Foil", "ForceField", "Glacier",
    "Glass", "Granite", "Grass", "Ground", "Ice", "LeafyGrass", "Leather", "Limestone", "Marble", "Metal",
    "Mud", "Neon", "Pavement", "Pebble", "Plaster", "Plastic", "Rock", "RoofShingles", "Rubber", "Salt",
    "Sand", "Sandstone", "Slate", "SmoothPlastic", "Snow", "Wood", "WoodPlanks",
}
REQUIRED_ROLES = ["background", "surface", "hazard", "interactive", "goal", "reward", "panel",
                  "text", "textMuted", "textOnAccent", "accent", "danger", "success"]
REQUIRED_FONTS = ["heading", "body"]
HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
NAME_RE = re.compile(r"^[a-z][A-Za-z0-9]*$")
DEFAULT_VALIDATION = {"textContrast": 4.5, "uiContrast": 3.0, "minDeltaE": 25.0}
# (primer plano, fondo, tipo). "text" exige textContrast, "ui" uiContrast y
# "gameplay" una diferencia de color (ΔE) visible también con daltonismo.
DEFAULT_PAIRS = [
    ("text", "panel", "text"), ("textMuted", "panel", "text"), ("textOnAccent", "accent", "text"),
    ("accent", "panel", "ui"), ("danger", "panel", "ui"), ("success", "panel", "ui"),
    ("hazard", "surface", "gameplay"), ("interactive", "surface", "gameplay"), ("goal", "surface", "gameplay"),
    ("reward", "surface", "gameplay"), ("hazard", "interactive", "gameplay"), ("hazard", "goal", "gameplay"),
    ("hazard", "reward", "gameplay"), ("interactive", "goal", "gameplay"),
]
# Rangos de las propiedades que aplica Style.applyLighting (nombre en el tema → (mín, máx)).
LIGHTING_NUMBERS = {"clockTime": (0, 24), "brightness": (0, 10), "exposure": (-3, 3),
                    "environmentDiffuseScale": (0, 1), "environmentSpecularScale": (0, 1), "shadowSoftness": (0, 1)}
LIGHTING_COLORS = {"ambient", "outdoorAmbient", "colorShiftTop", "colorShiftBottom"}
EFFECTS = {
    "fog": {"color": "color", "start": (0, 100000), "end": (0, 100000)},
    "atmosphere": {"density": (0, 1), "offset": (0, 1), "color": "color", "decay": "color", "glare": (0, 10), "haze": (0, 10)},
    "colorCorrection": {"brightness": (-1, 1), "contrast": (-1, 1), "saturation": (-1, 1), "tint": "color"},
    "bloom": {"intensity": (0, 10), "size": (0, 56), "threshold": (0, 4)},
    "sunRays": {"intensity": (0, 1), "spread": (0, 1)},
}
# Simulación de dicromacia (Machado, Oliveira y Fernandes, 2009; severidad 1,0) sobre RGB lineal.
CVD = {
    "protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    "deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    "tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    pairs: list[dict] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def hex_to_rgb(value: str) -> tuple[float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))


def to_linear(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def luminance(rgb) -> float:
    r, g, b = (to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(first, second) -> float:
    high, low = sorted((luminance(first), luminance(second)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def linear_to_lab(linear) -> tuple[float, float, float]:
    r, g, b = linear
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

    def f(t: float) -> float:
        return t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116

    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def simulate(rgb, matrix) -> tuple[float, float, float]:
    linear = [to_linear(c) for c in rgb]
    return tuple(min(1.0, max(0.0, sum(matrix[i][j] * linear[j] for j in range(3)))) for i in range(3))


def delta_e(first, second) -> dict[str, float]:
    """ΔE (CIE76) entre dos colores en visión normal y en cada dicromacia simulada."""
    result = {"normal": math.dist(linear_to_lab([to_linear(c) for c in first]), linear_to_lab([to_linear(c) for c in second]))}
    for name, matrix in CVD.items():
        result[name] = math.dist(linear_to_lab(simulate(first, matrix)), linear_to_lab(simulate(second, matrix)))
    return result


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def check_theme(theme, result: Result, where: str = "src/shared/Theme.json") -> None:
    if not isinstance(theme, dict):
        result.error(where, "debe ser un objeto JSON")
        return
    if theme.get("schemaVersion") != 1:
        result.error(where, "schemaVersion debe ser 1")

    palette = theme.get("palette")
    if not isinstance(palette, dict) or not palette:
        result.error(where, "falta 'palette' con colores con nombre")
        palette = {}
    for name, value in palette.items():
        if not NAME_RE.match(name):
            result.error(where, f"nombre de color inválido {name!r}: usa camelCase")
        if not isinstance(value, str) or not HEX_RE.match(value):
            result.error(where, f"el color {name!r} debe ser hexadecimal #RRGGBB")

    def color_of(reference, context: str):
        """Color por nombre de paleta o hexadecimal; registra error si no es válido."""
        if isinstance(reference, str) and HEX_RE.match(reference):
            return hex_to_rgb(reference)
        if isinstance(reference, str) and isinstance(palette.get(reference), str) and HEX_RE.match(palette[reference]):
            return hex_to_rgb(palette[reference])
        result.error(where, f"{context}: {reference!r} no es un color de la paleta ni un hexadecimal")
        return None

    roles = theme.get("roles")
    if not isinstance(roles, dict):
        result.error(where, "falta 'roles' (rol → nombre de color de la paleta)")
        roles = {}
    role_colors = {}
    for role in REQUIRED_ROLES:
        if role not in roles:
            result.error(where, f"falta el rol {role!r}")
    for role, swatch in roles.items():
        if not isinstance(swatch, str) or swatch not in palette:
            result.error(where, f"el rol {role!r} debe apuntar a un color de la paleta (es {swatch!r})")
        elif isinstance(palette[swatch], str) and HEX_RE.match(palette[swatch]):
            role_colors[role] = hex_to_rgb(palette[swatch])
    materials = theme.get("materials", {})
    if not isinstance(materials, dict):
        result.error(where, "'materials' debe ser un objeto rol → material")
    else:
        for role, material in materials.items():
            if material not in MATERIALS:
                result.error(where, f"material desconocido para {role!r}: {material!r}")
        if materials.get("hazard") and materials.get("hazard") == materials.get("surface"):
            result.warn(where, "el peligro usa el mismo material que la superficie; el color no debería ser la única diferencia")

    fonts = theme.get("fonts")
    if not isinstance(fonts, dict):
        result.error(where, "falta 'fonts' con al menos heading y body")
        fonts = {}
    for kind in REQUIRED_FONTS:
        if kind not in fonts:
            result.error(where, f"falta la fuente {kind!r}")
    for kind, spec in fonts.items():
        if not isinstance(spec, dict) or spec.get("font") not in FONTS:
            result.error(where, f"fuente {kind!r}: 'font' debe ser un valor de Enum.Font (por ejemplo BuilderSans)")
            continue
        if spec["font"] in DEPRECATED_FONTS:
            result.warn(where, f"fuente {kind!r}: {spec['font']} está obsoleta; usa BuilderSans o una familia vigente")
        if spec.get("weight", "Regular") not in WEIGHTS:
            result.error(where, f"fuente {kind!r}: peso inválido {spec.get('weight')!r}")

    ui = theme.get("ui", {})
    if not isinstance(ui, dict):
        result.error(where, "'ui' debe ser un objeto de métricas")
    else:
        for key, value in ui.items():
            if not is_number(value) or value < 0:
                result.error(where, f"ui.{key} debe ser un número positivo")
        if is_number(ui.get("minTouchTarget")) and ui["minTouchTarget"] < 44:
            result.warn(where, "ui.minTouchTarget menor que 44 px dificulta el uso en pantallas táctiles")

    lighting = theme.get("lighting", {})
    if not isinstance(lighting, dict):
        result.error(where, "'lighting' debe ser un objeto")
        lighting = {}
    if lighting.get("style", "Soft") not in {"Soft", "Realistic"}:
        result.error(where, "lighting.style debe ser Soft o Realistic")
    if "prioritizeQuality" in lighting and not isinstance(lighting["prioritizeQuality"], bool):
        result.error(where, "lighting.prioritizeQuality debe ser true o false")
    presets = lighting.get("presets", {})
    if not isinstance(presets, dict) or "default" not in presets:
        result.error(where, "lighting.presets debe incluir un preset 'default'")
        presets = presets if isinstance(presets, dict) else {}
    for name, preset in presets.items():
        context = f"lighting.presets.{name}"
        if not isinstance(preset, dict):
            result.error(where, f"{context} debe ser un objeto")
            continue
        for key, value in preset.items():
            if key in LIGHTING_NUMBERS:
                low, high = LIGHTING_NUMBERS[key]
                if not is_number(value) or not low <= value <= high:
                    result.error(where, f"{context}.{key} debe estar entre {low} y {high}")
            elif key in LIGHTING_COLORS:
                color_of(value, f"{context}.{key}")
            elif key == "globalShadows":
                if not isinstance(value, bool):
                    result.error(where, f"{context}.globalShadows debe ser true o false")
            elif key in EFFECTS:
                if not isinstance(value, dict):
                    result.error(where, f"{context}.{key} debe ser un objeto")
                    continue
                for prop, prop_value in value.items():
                    rule = EFFECTS[key].get(prop)
                    if rule is None:
                        result.error(where, f"{context}.{key}.{prop} no es una propiedad conocida")
                    elif rule == "color":
                        color_of(prop_value, f"{context}.{key}.{prop}")
                    elif not is_number(prop_value) or not rule[0] <= prop_value <= rule[1]:
                        result.error(where, f"{context}.{key}.{prop} debe estar entre {rule[0]} y {rule[1]}")
            else:
                result.error(where, f"{context}.{key} no es una propiedad conocida")
        if "fog" in preset and "atmosphere" in preset:
            result.warn(where, f"{context} define fog y atmosphere; usa uno de los dos para controlar la distancia de visión")
        fog = preset.get("fog")
        if isinstance(fog, dict) and is_number(fog.get("start")) and is_number(fog.get("end")) and fog["start"] >= fog["end"]:
            result.error(where, f"{context}.fog.start debe ser menor que fog.end")

    validation = dict(DEFAULT_VALIDATION)
    custom = theme.get("validation", {})
    if isinstance(custom, dict):
        for key, value in custom.items():
            if key in validation and is_number(value) and value > 0:
                validation[key] = float(value)
            else:
                result.error(where, f"validation.{key} no es una regla conocida o no es un número positivo")

    pairs = list(DEFAULT_PAIRS)
    for extra in theme.get("checks", []) if isinstance(theme.get("checks", []), list) else []:
        if isinstance(extra, dict) and extra.get("kind") in {"text", "ui", "gameplay"}:
            pairs.append((extra.get("foreground"), extra.get("background"), extra["kind"]))
        else:
            result.error(where, "cada entrada de 'checks' necesita foreground, background y kind (text, ui o gameplay)")
    for foreground, background, kind in pairs:
        if foreground not in role_colors or background not in role_colors:
            if foreground in roles and background in roles:
                continue  # el error del rol ya se informó
            result.error(where, f"el par {foreground}/{background} usa roles inexistentes")
            continue
        first, second = role_colors[foreground], role_colors[background]
        ratio = contrast_ratio(first, second)
        entry = {"foreground": foreground, "background": background, "kind": kind, "contrast": round(ratio, 2)}
        if kind == "gameplay":
            distances = delta_e(first, second)
            worst = min(distances, key=distances.get)
            entry.update({"deltaE": round(distances[worst], 1), "worstVision": worst})
            if distances[worst] < validation["minDeltaE"]:
                result.error(where, f"{foreground} y {background} se confunden en {worst} (ΔE {distances[worst]:.1f} < {validation['minDeltaE']:g})")
        else:
            needed = validation["textContrast"] if kind == "text" else validation["uiContrast"]
            if ratio < needed:
                result.error(where, f"contraste de {foreground} sobre {background} es {ratio:.2f}:1; necesita {needed:g}:1")
        result.pairs.append(entry)


def check_game(game: Path) -> Result:
    result = Result()
    theme_path = game / "src" / "shared" / "Theme.json"
    palette: dict = {}
    if not theme_path.exists():
        result.error("src/shared/Theme.json", "no existe")
    else:
        try:
            theme = json.loads(theme_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            result.error("src/shared/Theme.json", f"JSON inválido: {exc}")
        else:
            check_theme(theme, result)
            palette = theme.get("palette", {}) if isinstance(theme, dict) else {}
    doc = game / "design" / "ART.md"
    if not doc.exists():
        result.error("design/ART.md", "no existe")
    else:
        text = doc.read_text(encoding="utf-8")
        for name in palette:
            if name not in text:
                result.warn("design/ART.md", f"no explica el color {name!r}")
    return result


def format_result(title: str, result: Result) -> str:
    lines = [title, "", "| Par | Tipo | Contraste | ΔE mínimo | Peor visión |", "| --- | --- | --- | --- | --- |"]
    for pair in result.pairs:
        lines.append(f"| {pair['foreground']} / {pair['background']} | {pair['kind']} | {pair['contrast']}:1 | "
                     f"{pair.get('deltaE', '-')} | {pair.get('worstVision', '-')} |")
    lines.append("")
    lines.extend(f"ERROR {e}" for e in result.errors)
    lines.extend(f"WARN  {w}" for w in result.warnings)
    lines.append(f"Resultado: {len(result.errors)} errores, {len(result.warnings)} advertencias")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Revisa la dirección de arte de un juego de la fábrica.")
    parser.add_argument("game", type=Path, nargs="?", help="carpeta del juego (la que contiene GDD.md)")
    parser.add_argument("--theme", type=Path, help="revisar solo un Theme.json")
    parser.add_argument("--json", action="store_true", help="imprime el resultado como JSON")
    args = parser.parse_args(argv)
    if args.theme:
        result = Result()
        try:
            check_theme(json.loads(args.theme.read_text(encoding="utf-8")), result, str(args.theme))
        except (OSError, json.JSONDecodeError, UnicodeDecodeError) as exc:
            print(f"ERROR no se pudo leer {args.theme}: {exc}")
            return 2
        title = f"Revisión del tema: {args.theme}"
    elif args.game and args.game.is_dir():
        result = check_game(args.game.resolve())
        title = f"Revisión de arte: {args.game}"
    else:
        print("ERROR indica la carpeta del juego o --theme <archivo>")
        return 2
    if args.json:
        print(json.dumps({"errors": result.errors, "warnings": result.warnings, "pairs": result.pairs}, ensure_ascii=False, indent=2))
    else:
        print(format_result(title, result))
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
