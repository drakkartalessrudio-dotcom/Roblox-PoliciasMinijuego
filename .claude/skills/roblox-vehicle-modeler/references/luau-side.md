# El lado de Luau: ensamblar y manejar los autos

Las plantillas de `assets/luau/` convierten el manifest en un auto de Roblox. No dependen del juego: se copian a `src/shared/` (se analizan con luau-lsp y se prueban con Lune en este repo).

| Archivo | Qué es |
| --- | --- |
| `VehicleModelPlan.luau` | Lógica pura (sin Instances): operaciones por pieza, offsets de sockets, ruedas y asiento, altura de reposo, validación del manifest. Se prueba con Lune |
| `VehicleAssembler.luau` | `build(imported, assetKey)`: aplica tamaño, posición, material y color del manifest, suelda al `Chassis`, crea los `Socket_*`, marca `Paintable`. Además `setBodyColor`, `setWindowTint`, `setRimStyle`, `setKindColor`, `scaleWheels`, `attachModule`, `detachModule` |
| `VehicleBody.luau` | `build(imported, assetKey, options)`: lo anterior más lo que pide el contrato de manejo; `verify(model, assetKey)` para Studio |
| `VehicleModels.json` | **No viene en las plantillas**: lo genera `collect_models.py` en `src/shared/` |

## Instalación en un juego

1. `python <skill>/scripts/collect_models.py <carpeta de autos> --out <juego>/src/shared/VehicleModels.json`
2. Copia los tres `.luau` a `<juego>/src/shared/`.
3. Importa cada FBX y guarda su `.rbxm` en `src/shared/VehicleMeshes/` ([studio-import.md](studio-import.md)).
4. Donde el juego construye un auto (`buildModel`, el auto del cliente, el dyno), llama a `VehicleBody.build(Shared.VehicleMeshes[asset], asset, { suspensionLength, suspensionFrequency })` con los **mismos** valores que el perfil de manejo.

## Por qué hace falta `VehicleBody` además del ensamblador

El core de manejo (`VehicleRig`) pide un modelo con esta forma, y un auto armado solo con el ensamblador no la cumple:

| Pide el manejo | Lo resuelve | Cómo |
| --- | --- | --- |
| `Chassis` con frente = −Z y derecha = +X | El **manifest/FBX** en el marco de Roblox | El `Chassis` llega con orientación identidad; no se gira nada en Luau |
| `Socket_Wheel_FL/FR/RL/RR` **arriba del resorte** (origen del rayo) | `VehicleBody` | Sube cada socket `restSpring` sobre el buje: `restSpring = suspensionLength − g / (2π·f)²`. En reposo el neumático toca el piso |
| `DriverSeat` (`VehicleSeat`) soldado al chasis | `VehicleBody` | Posición y tamaño de `rig.seat` |
| `WheelWeld_*` (Weld Chassis → rueda) para animar giro y dirección | `VehicleBody` | `Weld` con `C0` en el buje; `WheelVisuals` cambia su `C0` y gira sobre X (el eje del auto) |
| Atributo `WheelRadius` en el `Chassis` | `VehicleBody` | `rig.wheelRadius` |
| La llanta gira con el neumático | `VehicleBody` | La llanta se suelda al neumático, no al chasis |
| `Paintable` / `BaseColor` para pintura y llantas premium | `VehicleAssembler` | `Chassis`/`Bed` = `body`, `Rim_*` = `rim` |

`Socket_Wheel_*` en un auto manejable es entonces el origen del rayo (el buje subido unos 0,3–0,6 studs), no el punto donde se atornilla una rueda de tuning. Las ruedas de tuning se escalan (`scaleWheels`) o se reemplazan sobre las piezas `Tire`/`Rim`.

## Pivote del modelo importado

Studio **conserva el origen del FBX como pivote** de cada `MeshPart`: el `PivotOffset` del `Chassis` importado es
`(0, −altura del centro, ~0)`. Como el origen del auto está en el piso bajo su centro, `Model:PivotTo(cframe)` pone el
**piso bajo el centro del auto** en `cframe` (no el centro del chasis, como un auto hecho con cajas). Leído de los 10 `.rbxm`
de Garage Tycoon. Consecuencias: para dejar un auto sobre una superficie, `PivotTo` con la altura de esa superficie (o
`GetBoundingBox` para apoyarlo sin suponer el pivote); un auto que se maneja se suelta unos studs sobre el piso y cae solo.

## Límites conocidos

- **Sin probar en Studio** hasta que alguien lo haga: la orientación y la escala del import, la altura de reposo, el asiento y la colisión están razonadas y comprobadas contra el FBX, pero no ejecutadas dentro de Roblox. `VehicleBody.verify` y [studio-import.md](studio-import.md) son la prueba.
- La física ve el `Chassis` como una caja. Un auto largo con un solo `suspensionLength` para todos puede subvirar: el perfil de manejo por auto (largo y frecuencia del resorte) es del juego.
- No hay animación de suspensión ni puertas: las ruedas giran y viran, y nada más se mueve (decisión de la guía para ahorrar triángulos).
