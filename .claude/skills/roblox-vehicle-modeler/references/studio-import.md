# Importar un auto a Roblox Studio y comprobarlo

Claude no puede abrir Studio. Esta es la lista que hace el usuario, y **lo que no se haya pasado por aquí es "sin probar en Studio"**, nunca "probado".

## 1. Importar

1. Abre el proyecto con Rojo (`rojo serve`) para que existan `VehicleAssembler`, `VehicleBody`, `VehicleModelPlan` y `VehicleModels` en `ReplicatedStorage.Shared` (ver [luau-side.md](luau-side.md)).
2. Avatar → **Import 3D** → `Export/<Asset>_Roblox.fbx`. Deja la escala en 1 y no marques opciones que muevan el origen de las piezas.
3. Studio crea un Model con las mallas (`Chassis`, `Windows`, `Tire_FL`, …). Renómbralo `<Asset>` (sin sufijos como `.001`).
4. Clic derecho en el Model → **Save to File** → `src/shared/VehicleMeshes/<Asset>.rbxm`. Rojo lo sincroniza como `ReplicatedStorage.Shared.VehicleMeshes.<Asset>` en **todos los places** del proyecto (ciudad y pista) sin tocar los `*.project.json`. Las mallas se suben a Roblox al importar; el `.rbxm` solo guarda sus `MeshId`.

## 2. Verificar (barra de comandos de Studio)

Selecciona el Model importado y ejecuta:

```lua
local sel = game.Selection:Get()[1]
print(table.concat(require(game.ReplicatedStorage.Shared.VehicleBody).verify(sel, sel.Name), "\n"))
```

Lee el informe: `ERROR` = no sirve, `AVISO` = el ensamblador lo corrige pero conviene saberlo, `INFO` = dato. Comprueba como mínimo:

| Prueba | Esperado |
| --- | --- |
| Tamaño del `Chassis` importado | Igual al del manifest (ratio 1,000). Otro ratio = otra escala de importación; el ensamblador la corrige con `Size`, pero anótalo |
| Longitud del `Chassis` | Corre por Z (más largo en Z que en X) |
| Rotación del `Chassis` | Sin rotación (LookVector = −Z) |
| Piezas | Están las 10 obligatorias (`Chassis`, `Windows`, `Tire_xx`, `Rim_xx`) |

El importador de Studio gira el modelo 180° sobre Y, y el FBX ya viene pre-girado 180° para cancelarlo (`rbx/frame.py`): importa con los valores por defecto y no corrijas ejes en la ventana. Tras importar, `Tire_FL` debe tener x < 0 y z < 0 (como el manifest). Si el modelo llega **al revés, de lado o con piezas giradas**, la conversión de ejes del importador cambió o no es la esperada: no lo arregles con giros en Luau. Cuéntalo (versión de Studio y lo que ves) y se ajusta el exportador (`rbx/frame.py` y `rbx/export.py`), porque el resto del sistema asume el marco de Roblox.

## 3. Armar y mirar

```lua
local Shared = game.ReplicatedStorage.Shared
local VehicleBody = require(Shared.VehicleBody)
local car = VehicleBody.build(Shared.VehicleMeshes.Sedan01, "Sedan01", { suspensionLength = 1.2, suspensionFrequency = 3 })
car:PivotTo(CFrame.new(0, 8, 0))
car.Parent = workspace
```

- **Se ve bien:** colores y materiales del manifest, ventanas translúcidas, faros brillantes, neumáticos negros y llantas metálicas.
- **Se maneja:** con el core de manejo del juego registrado (`VehicleDriving.register`), el auto avanza hacia donde apunta la trompa, las ruedas giran en su eje y las delanteras viran.
- **Altura:** en reposo los neumáticos tocan el piso y el auto no flota ni se hunde.
- **Conductor:** sentado, con la cabeza dentro o a la altura de las ventanas. Si atraviesa el techo o queda fuera de la cabina, ajusta `roblox.seat` en el spec (el marco es el de Roblox) y reconstruye.
- **Colisión:** el `Chassis` es una caja (`CollisionFidelity = Box`); con los espejos integrados es unos 0,9 studs más ancho que el auto. Si roza las puertas de un garaje, dilo y se ajusta.

## 4. Si algo falla

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| `falta la malla 'Tire_FL'` | El Model importado trae nombres con sufijo (`Tire_FL.001`) o anidados distinto | Renombra en Studio; los nombres deben ser exactos |
| Auto de lado / al revés | Conversión de ejes del importador | Ver arriba: se corrige en el exportador, no en Luau |
| Piezas en otro tamaño | Escala de importación | `Size` lo corrige; revisa el ratio del informe |
| Las ruedas giran "de lado" | Se usó otro ensamblador que no usa `VehicleBody` | `WheelVisuals` gira el `Weld.C0` sobre X; `VehicleBody` crea los `WheelWeld_*` con esa convención |
| El auto vuela o se hunde al arrancar | `suspensionLength` / `suspensionFrequency` de `build` distintos de los del perfil de manejo | Usa los mismos valores (`Config.Driving.DefaultProfile`) |
| `Sin socket` al colgar un módulo | El auto no pasó por el ensamblador | Los `Socket_*` los crea `VehicleAssembler.build` |
