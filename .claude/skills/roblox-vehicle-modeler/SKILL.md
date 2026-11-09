---
name: roblox-vehicle-modeler
description: Modelar autos para Roblox en Blender (por línea de comandos o con MCP) a partir de planos, conceptos o un prompt, y dejarlos listos para el ensamblador de Luau. Produce el FBX por piezas (Chassis de una malla, Windows, Tire y Rim por rueda, Trim, Lights, Bumpers) en studs y con los ejes de Roblox, un manifest con ruedas, asiento, sockets y colisión, y un validador (check_vehicle.py) del presupuesto de triángulos, los ejes y la guía de arte. Incluye las plantillas VehicleAssembler, VehicleBody y VehicleModelPlan y la lista de importación a Studio. Úsalo cuando el usuario quiera crear, corregir o importar autos 3D para un juego de Roblox, una serie por tiers o piezas modulares (alerones, ruedas) con sockets. Para Unreal, Unity o Godot usa el skill vehicle-rig-builder. No escribe la lógica de manejo ni la economía (roblox-game-builder).
metadata:
  version: "1.0.0"
  last_verified: "2026-10-16"
---

# Roblox Vehicle Modeler

Convierte un concepto, unos planos o un prompt en un auto que el juego puede ensamblar y manejar: siluetas reales en cm → carrocería de una sola malla con paneles, cristales y ruedas → piezas sueltas en **studs** y en **los ejes de Roblox** → FBX + manifest → validación → importación a Studio → `VehicleAssembler` / `VehicleBody`.

Es el skill de vehículos **de Roblox**. El skill `vehicle-rig-builder` (para Unreal, UEFN, Unity y Godot) hace huesos, LODs y exports de motor; aquí nada de eso aplica: Roblox no importa esqueletos de autos, no usa LODs propios y mueve las ruedas con welds en Luau. Este skill lleva su propia copia de la biblioteca de modelado (`scripts/veh/`) y no depende del otro.

Idioma: los archivos del skill y los documentos generados están en inglés (como la biblioteca `veh`); conversa con el usuario en su idioma.

## Qué produces y qué no

- Por auto: `<Asset>.spec.json` (fuente de verdad), `Export/<Asset>_Roblox.fbx`, `Export/<Asset>.manifest.json` ([formato](references/manifest-format.md)), `<Asset>_PARTS.md` (obligatorio), `<Asset>.blend` y `renders/`.
- Por juego: `src/shared/VehicleModels.json` (con `collect_models.py`) y las plantillas de [Luau](references/luau-side.md) copiadas a `src/shared/`.
- **No escribes** la lógica de manejo, las partes de tuning ni los precios: eso es de [roblox-game-builder](../roblox-game-builder/SKILL.md) (y de [roblox-game-designer](../roblox-game-designer/SKILL.md) para la economía). El contrato entre ambos es el manifest.
- **No subes mallas a Roblox**: las sube Studio al importar (el servidor no puede crear `MeshPart` con un `MeshId`). Ese paso lo hace el usuario y tú le das la [lista](references/studio-import.md).
- Los colores del auto salen del concepto o del brief. La paleta de la interfaz y del mundo es del [art director](../roblox-art-director/SKILL.md); no la cambies desde aquí.

## Archivos del skill

```
SKILL_DIR = skills/roblox-vehicle-modeler   (la carpeta donde esté instalado)
  SKILL.md                         este archivo ← léelo primero
  scripts/build_vehicle.py         Blender sin interfaz: review | export | all
  scripts/check_vehicle.py         validador de manifests
  scripts/collect_models.py        manifests → VehicleModels.json del juego
  scripts/rbx/                     frame (ejes), groups, manifest, export (Blender), docs, specgen
  scripts/veh/                     biblioteca de modelado (copia del skill genérico, ver su VENDORED.md)
  scripts/segment_reference.py     segmenta planos o fotos en regiones (numpy + opencv)
  scripts/regions_tool.py          une, refleja y dibuja regiones a mano
  references/roblox-vehicle-rules.md   reglas de la guía de arte: presupuesto, piezas, sockets, materiales
  references/spec-format.md        el bloque roblox del spec y cómo empezar
  references/veh-spec-reference.md todos los campos de modelado del spec (casco, paneles, ruedas…)
  references/manifest-format.md    marco de coordenadas y campos del manifest
  references/studio-import.md      importar a Studio y comprobar (lo hace el usuario)
  references/luau-side.md          instalar las plantillas y qué pide el core de manejo
  assets/example/Sedan01/          auto de referencia: spec, FBX, manifest, PARTS.md y un render
  assets/luau/                     VehicleModelPlan, VehicleAssembler, VehicleBody
```

## Requisitos

- Blender 5.1 o superior. Corre **sin interfaz** (`blender -b --factory-startup -P …`); no hace falta MCP. Variable `BLENDER` o la instalación estándar en `C:\Program Files\Blender Foundation\`.
- Python 3.10+ para `check_vehicle.py`, `collect_models.py` y `rbx/specgen.py` (sin dependencias). Para segmentar planos: `numpy` y `opencv-python-headless`.
- Opcional: Lune, luau-lsp y Rojo (ver `rokit.toml` del repo) para probar y analizar las plantillas.
- Nunca llames a `bpy.ops.wm.open_mainfile` ni `read_homefile` por un MCP: detiene el servidor.

## Flujo

### 1 · Brief ⏸

Haz como máximo una pregunta, solo si falta algo que cambia el modelo. Fija con el usuario y guárdalo en el spec (`brief`, `decisions`):

- `bodyType` y clase de uso (¿base de tuning sin alerón? ¿puertas fijas?), medidas reales y colores.
- **Presupuesto de triángulos** ([reglas](references/roblox-vehicle-rules.md)); si pasa el rango de la guía, la excepción va en `decisions`.
- Plataformas: móvil primero; cuántos autos se verán a la vez.
- Si es una **serie** (tiers): qué cambia de uno a otro y qué comparten (sockets universales por `bodyType`, llantas).

### 2 · Spec

Copia `assets/example/Sedan01/Sedan01.spec.json` o escribe una función por auto con `rbx.specgen.car` ([spec-format.md](references/spec-format.md)). Con planos: calibra las vistas y segmenta (`segment_reference.py`). Sin planos, diseña en cm desde las dimensiones reales. El lado izquierdo se modela y `mirror` hace el derecho; nunca construyas el derecho a mano.

### 3 · Blockout ⏸

```bash
blender -b --factory-startup -P scripts/build_vehicle.py -- <carpeta>/<Asset>.spec.json review
```

Mira `renders/blockout_*.png` (lateral, frente, planta, 3/4) y compáralos con el concepto: silueta, proporciones, ruedas dentro de los arcos. **Espera la aprobación** antes de exportar. Itera sobre el spec, no sobre el FBX.

### 4 · Exportar y validar

```bash
blender -b --factory-startup -P scripts/build_vehicle.py -- <carpeta>/<Asset>.spec.json all
python scripts/check_vehicle.py <carpeta>/Export
```

El build sale con código 1 si falla la construcción o si el FBX releído no coincide con el manifest. `check_vehicle.py` revisa piezas y sockets, materiales nativos, presupuesto, ejes (trompa a −Z), ruedas simétricas y apoyadas en el piso, llanta dentro del neumático, asiento dentro del chasis y origen al centro. **Un error es un auto que no se puede entregar**; un aviso se explica en `decisions` o se corrige.

### 5 · Entregar al juego

```bash
python scripts/collect_models.py <carpeta de autos> --out <juego>/src/shared/VehicleModels.json
```

Copia las plantillas de `assets/luau/` a `src/shared/` y entrega al usuario la lista de [importación a Studio](references/studio-import.md), el `_PARTS.md` de cada auto y el comando de verificación. Declara con claridad qué quedó **sin probar en Studio**.

### 6 · Después de Studio

Si el usuario reporta de lado, escala distinta, ruedas que giran mal, asiento fuera de lugar o colisión que roza, el arreglo va en el spec (`roblox.seat`, siluetas) o en el exportador (`rbx/frame.py`, `rbx/export.py`), no en parches de Luau por auto. Antes de modificar un auto existente, lee su `_PARTS.md`.

## Reglas que no se negocian

1. **Chassis en una sola malla** con los espejos integrados; cristales en `Windows`; `Tire_xx` y `Rim_xx` separados con el pivote en el buje; los nueve `Socket_*` con sus nombres exactos.
2. **Solo materiales nativos y color plano.** El color oficial es el del manifest, aplicado en Luau (`Part.Color`).
3. **Marco de Roblox en todo lo que sale** (manifest y FBX): la trompa apunta a −Z, X a la derecha, Y arriba, origen bajo el centro. El FBX se escribe pre-girado 180° sobre Y porque el importador de Studio lo gira de vuelta (ver `rbx/frame.py`); lo que cuenta es el modelo **ya importado**. Si el FBX no cumple, el build falla; no se corrige girando en Luau (girar el `Chassis` rompe el contrato de `VehicleRig`).
4. **Triángulos dentro del `tri_budget` del spec**; salirse del rango de la guía se justifica por escrito.
5. **El spec es la fuente de verdad.** No edites a mano el FBX, el manifest, `VehicleModels.json` ni `_PARTS.md`: se regeneran.
6. **Nombres estables** (`Chassis`, `Tire_FL`, `Socket_Spoiler`…): el código los busca por nombre.
7. **Lo que no se probó en Studio se dice.** Esa es la parte de este flujo que Claude no puede ejecutar.

## Con el resto de la fábrica

- [roblox-game-builder](../roblox-game-builder/SKILL.md) construye con las plantillas el catálogo de autos del juego (definiciones, stats, `HandlingMap`) y las pone en `src/`; ve sus reglas de módulos (un core no requiere a otro). Los autos son contenido de `Game`, no de un core.
- [roblox-art-director](../roblox-art-director/SKILL.md): si el juego tiene `Theme.json`, los autos conviene que usen su paleta de acento; los colores del concepto mandan si el usuario los aprobó.
- [roblox-environment-artist](../roblox-environment-artist/SKILL.md): los espacios donde se estacionan los autos (bahías, plataformas, boxes) deben medir más que el auto más largo de la serie más una holgura; pásale las dimensiones del manifest.
- [roblox-data-architect](../roblox-data-architect/SKILL.md): si un juego renombra los IDs de sus autos (de un auto de prueba a uno modelado), los perfiles guardados necesitan una migración de datos.

## Probar la instalación

```bash
python -m unittest tools.tests.test_vehicle_modeler -v     # desde la raíz del repositorio
lune run tools/tests/luau/vehicle_model_plan.spec.luau
blender -b --factory-startup -P scripts/build_vehicle.py -- assets/example/Sedan01/Sedan01.spec.json export
```
