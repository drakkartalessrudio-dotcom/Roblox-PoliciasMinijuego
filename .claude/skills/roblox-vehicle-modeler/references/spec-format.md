# Formato del spec de un auto de Roblox

El spec es el JSON de la biblioteca `veh` ([veh-spec-reference.md](veh-spec-reference.md): casco por intersección de siluetas, paneles, ruedas, primitivas) más un bloque `roblox`. Es la **fuente de verdad** del auto: el FBX, el manifest y el `_PARTS.md` se regeneran desde él. Espacio del spec: cm, +X adelante, +Y izquierda, +Z arriba; se modela el lado izquierdo y `"mirror": true` hace el derecho.

## El bloque `roblox` (obligatorio)

```json
"roblox": {
  "bodyType": "sedan",
  "materials": {
    "Chassis": { "material": "SmoothPlastic", "color": [30, 136, 214] },
    "Windows": { "material": "Glass", "color": [43, 58, 68], "transparency": 0.35 },
    "Trim":    { "material": "SmoothPlastic", "color": [142, 147, 153] },
    "Lights":  { "material": "Neon", "color": [242, 226, 122] },
    "Bumpers": { "material": "SmoothPlastic", "color": [142, 147, 153] },
    "Tire":    { "material": "SmoothPlastic", "color": [28, 28, 32] },
    "Rim":     { "material": "Metal", "color": [154, 160, 166] }
  },
  "seat": { "position": [-1.5, 1.6, 0], "size": [2, 0.6, 2] }
}
```

| Campo | Obligatorio | Detalle |
| --- | --- | --- |
| `bodyType` | sí | `sedan`, `hatch`, `sports`, `muscle`, `super`, `limo`, `suv`, `pickup`, `truck`, `motorcycle` o `car`. Decide el rango de triángulos de la guía y qué autos comparten coordenadas de alerón |
| `materials.<tipo>` | sí | Material nativo y color RGB por **tipo** de pieza: `Chassis`, `Windows`, `Trim`, `Lights`, `Bumpers`, `Roof`, `Bed`, `Neon`, `Tire`, `Rim`. Un tipo que falta usa `SmoothPlastic` gris |
| `seat` | no | Anula el asiento derivado. `position` está en el **marco de Roblox** (x derecha, y arriba, z atrás), en studs |

## Campos del spec que usa el exportador

| Campo | Uso |
| --- | --- |
| `asset` | Nombre de los archivos (`<asset>_Roblox.fbx`, `<asset>.manifest.json`, `<asset>_PARTS.md`) y clave en `VehicleModels.json`. Sin espacios; empieza con letra |
| `tier`, `vehicle_class`, `brief`, `decisions` | Van al manifest y al documento |
| `dimensions_cm` | `length`, `width`, `height`, `wheelbase`, `wheel_radius`; pasan a studs en el manifest |
| `tri_budget` | Presupuesto aprobado (error si se pasa) |
| `mass_kg` | Pista de masa (`rig.massKg`) |
| `parts[].type = "wheel"` | `center_cm`, `radius_cm`, `width_cm`, `rim_ratio`, `driven`; el exportador separa neumático y llanta |
| `parts[].rbx_group` | Fuerza la pieza de Roblox de una parte (`"Roof"`, `"Trim"`…). Sin él se decide por capa y nombre (ver abajo) |
| `sockets[]` | Los nueve `Socket_*`, con `at_3d` en cm. Las ruedas van en el buje |

## Qué pieza de Roblox es cada parte

| Parte del spec | Pieza |
| --- | --- |
| capa `L6_Glass` | `Windows` |
| id `bed` | `Bed` |
| id que empieza con `roof_cap` | `Roof` |
| id que empieza con `neon` | `Neon` |
| id que empieza con `bumper` | `Bumpers` |
| capa `L7_Lights` | `Lights` |
| ruedas (`wheel_FL`…) | `Tire_FL`… y `Rim_FL`… |
| material `MI_Trim` | `Trim` |
| todo lo demás (casco, espejos integrados…) | `Chassis` |

## Cómo empezar

1. **Un auto parecido:** copia `assets/example/Sedan01/Sedan01.spec.json`, cambia `asset`, siluetas, ventanas, ruedas, colores y `tri_budget`.
2. **Varios autos de una familia:** escribe una función por auto con `rbx.specgen.car({...})` (ver su docstring) y genera los JSON con `specgen.write`. Es lo que hace el generador de la serie de 10 tiers de Garage Tycoon.
3. **Con planos:** calibra `views.side/top/front` y usa regiones (`segment_reference.py`, `regions_tool.py`), como en el skill de vehículos genérico. Sin planos se diseña en cm a partir de las dimensiones reales.

## Qué hacer con los campos de animación y rig

`motion`, `animations`, `lod_drop_layers`, `fbx_axis_*`, `export_gltf`, `export_rigid`: el spec los acepta (heredados de `veh`) pero **este skill no los usa**. Roblox maneja las ruedas con `WheelWeld_*` en Luau, no con huesos, y no importa LODs ni glTF desde este pipeline.
