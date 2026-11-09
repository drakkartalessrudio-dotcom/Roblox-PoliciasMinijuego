# Formato del manifest (schema 2)

`Export/<Asset>.manifest.json` es el contrato entre este skill y el código de Luau (`VehicleAssembler`, `VehicleBody`). Lo escribe `build_vehicle.py`; `collect_models.py` junta los de varios autos en `src/shared/VehicleModels.json` (`{ "schema": 2, "models": { "<Asset>": { … } } }`). Nunca se edita a mano.

## Marco de coordenadas

Todo el manifest y el FBX están en el **marco de Roblox**, en **studs**:

| Eje | Dirección |
| --- | --- |
| +X | derecha del auto |
| +Y | arriba |
| +Z | atrás (la trompa apunta a **−Z**) |
| Origen | en el piso, bajo el centro del auto |

Es el marco que pide `VehicleRig` (frente = −Z del `Chassis`, derecha = +X). Por eso el ensamblador **no gira ni permuta ejes**: un punto del manifest es un punto del modelo. Las ruedas izquierdas tienen x < 0.

Conversión desde el spec (`rbx/frame.py`): `roblox = (−vy, vz, −vx)` con `v` = (adelante, izquierda, arriba) en el spec; los tamaños pasan de (largo, ancho, alto) a (ancho, alto, largo).

### Cómo se garantiza en el FBX

El exportador de Blender (`axis_forward = -Z`, `axis_up = Y`) escribe `(x, z, −y)` de la escena, y el importador de Studio **gira el modelo 180° sobre Y** (medido en los `.rbxm`: `Tire_FL` llega en (+x, +z) cuando el FBX lo trae en (−x, −z); sin corregirlo la malla del `Chassis` queda con la trompa hacia +Z). Por eso el **FBX guarda el marco de Roblox girado 180°** `(x, y, z) → (−x, y, −z)` y la geometría se gira −90° sobre Z antes de exportar (`point_to_blender_export = (vy, −vx, vz)`). El manifest sigue en el marco de Roblox sin girar, que es el que queda tras importar. Se exporta con `bake_space_transform` y escala de unidades FBX con 1 unidad de Blender = 1 stud, y los nodos quedan **sin rotación ni escala** (comprobado: sin eso, Blender escribía una rotación de −90° en X y un escalado de 100 en cada nodo, y Roblox podía importar las piezas giradas o 100 veces más grandes). Después de escribir, el exportador **relee el FBX** (`io_scene_fbx.parse_fbx`) y compara centro y tamaño de cada pieza con el manifest (tolerancia 0,02 studs); cualquier diferencia queda en `verify` y hace fallar el build.

## Campos

```json
{
  "schema": 2,
  "asset": "Sedan01",
  "tier": 1,
  "bodyType": "sedan",
  "class": "land / family sedan (RWD)",
  "frame": "roblox-model",
  "units": "studs (…)",
  "fbx": "Sedan01_Roblox.fbx",
  "tris": { "total": 2808, "budget": 3000 },
  "dimensions": { "length": 15.86, "width": 6.29, "height": 5.21, "wheelbase": 8.93, "wheel_radius": 1.18 },
  "parts": {
    "Chassis": { "kind": "Chassis", "material": "SmoothPlastic", "color": [30,136,214], "transparency": 0,
                 "center": [0, 3.12, -0.02], "size": [7.21, 4.11, 15.96], "tris": 1288 }
  },
  "sockets": { "Socket_FrontBumper": [0, 1.36, -8.11] },
  "rig": { "wheels": { … }, "wheelRadius": 1.18, "trackWidth": 5.07, "wheelbase": 8.93, "axleHeight": 1.18,
           "seat": { … }, "groundClearance": 1.07, "collision": { … }, "massKg": 1100 }
}
```

| Campo | Significado |
| --- | --- |
| `parts.<Pieza>.center` | Centro de la caja envolvente de la pieza. Es el `CFrame.Position` de la MeshPart (el `CFrame` de una MeshPart siempre es el centro de su caja; el pivote no lo cambia). Para las ruedas es el buje |
| `parts.<Pieza>.size` | Tamaño de la caja (ancho X, alto Y, largo Z). El ensamblador lo asigna a `Size`, así que una escala de importación distinta se corrige sola |
| `parts.<Pieza>.material / color / transparency` | Material nativo de Roblox, RGB 0–255 y transparencia 0–1 que el ensamblador aplica |
| `sockets` | Posición de cada `Socket_*` (relativa al origen del modelo; el ensamblador la pasa a relativa al centro del `Chassis`) |
| `rig.wheels.<FL\|FR\|RL\|RR>` | `hub` (centro de la rueda), `radius`, `width` (el eje va en X), `steer` (delanteras), `drive` (tomado del `driven` del spec) |
| `rig.wheelRadius` | Radio medio: el atributo `WheelRadius` que lee el manejo |
| `rig.trackWidth`, `rig.wheelbase`, `rig.axleHeight`, `rig.groundClearance` | Datos de referencia para balance y alturas de reposo |
| `rig.seat` | `position` (centro del asiento), `size`, `side` (`left`: conducción a la izquierda), `source` (`spec` o derivado de `Windows`) |
| `rig.collision` | Caja del `Chassis` y `fidelity: "Box"` (el chasis es una caja para la física, como pide la guía; los espejos integrados ensanchan la caja un poco) |
| `rig.massKg` | Pista de masa del spec; la masa real la decide el perfil de manejo del juego |
| `tris.budget` | `tri_budget` aprobado del spec |
| `verify` | (solo en el manifest del build) problemas al releer el FBX; vacío = coincide |

## Asiento: cómo se deriva

Sin `roblox.seat` en el spec, el asiento queda a −25 % del ancho de la caja de `Windows` (izquierda), a 42 % del largo del cristal contando desde el parabrisas, y su centro a `radio de rueda + 0,4` de altura. Es una primera aproximación **que hay que mirar en Studio con un avatar sentado**: cámbiala con `roblox.seat` en el spec y reconstruye.

## Versionado

`schema` sube cuando un campo cambia de significado o se mueve. `check_vehicle.py` y `VehicleModelPlan.validate` rechazan un schema distinto de 2.
