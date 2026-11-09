# Reglas de vehículos para Roblox

Origen: la guía de arte y modularidad de vehículos de Garage Tycoon (`3d_asset_art_direction_guidelines_vehicle_modular_system_optimization_for_roblox.md`), convertida en reglas que el exportador cumple y que `check_vehicle.py` comprueba. Los números en **negrita** son límites; el resto son decisiones de modelado.

## 1. Estilo y presupuesto

- Semi-cartoon / low-poly: siluetas simples, bordes ligeramente redondeados, colores vivos, legibles en móvil. Los detalles que nadie ve a distancia no se modelan.
- Triángulos del auto completo (sin módulos de tuning):

| `bodyType` | Rango de la guía |
| --- | --- |
| `sedan`, `hatch`, `sports`, `muscle`, `super`, `limo`, `car` | 1.500 – **3.500** |
| `suv`, `pickup` | 2.500 – **4.500** |
| `truck` (pesado) | 4.000 – **6.000** |
| `motorcycle` | 1.000 – **2.200** |

- Cada spec fija su `tri_budget` aprobado. Pasarse del presupuesto del spec es **error**. Pasarse del rango de la guía es **aviso** salvo que `decisions` del spec explique la excepción (por ejemplo, un auto "héroe" de tier alto) con la palabra *triangles* o *tris*.
- Móvil primero: sumar los autos que se ven a la vez (jugadores, clientes y exhibición) antes de subir un presupuesto.

## 2. Materiales y color

- Solo materiales nativos: `SmoothPlastic`, `Metal`, `Glass`, `Neon` (y `Plastic`, `Foil`, `Concrete`, `Wood`, `Fabric` si hace falta). Sin texturas ni `SurfaceAppearance` en la base.
- El FBX trae un material de color plano por pieza para que se vea bien al importar, pero **el color y el material oficiales son los del manifest**: el ensamblador los vuelve a aplicar con `Part.Color`/`Part.Material`. Así la pintura es cambiar un `Color3`.
- Cristales: `Glass` con transparencia 0,35 por defecto (tintable por jugador). Luces: `Neon`.

## 3. Piezas (una MeshPart cada una)

| Pieza | Contenido | Obligatoria |
| --- | --- | --- |
| `Chassis` | Carrocería en **una sola malla**, con los espejos integrados (sin constraints extra) | sí |
| `Windows` | Parabrisas, luneta y ventanas laterales, separadas para tintar | sí |
| `Tire_FL/FR/RL/RR` | Neumático (caucho) | sí |
| `Rim_FL/FR/RL/RR` | Llanta (metal), independiente del neumático para cambiar color/material | sí |
| `Trim`, `Lights`, `Bumpers` | Rejillas y molduras; faros y calaveras; parachoques de fábrica | no |
| `Roof`, `Bed`, `Neon` | Techo de otro color, caja de pick-up intercambiable, tiras de neón | no |

- Cada rueda tiene su **pivote en el buje** (el centro de su malla) y el eje del auto va en X: gira sobre su propio eje sin trucos.
- Los alerones, escapes y kits **no** se modelan en el auto base: son módulos aparte que se cuelgan de un socket.

## 4. Sockets (Attachments dentro de `Chassis`)

`Socket_Spoiler`, `Socket_Wheel_FL/FR/RL/RR`, `Socket_Exhaust`, `Socket_FrontBumper`, `Socket_RearBumper`, `Socket_RoofExtra`. Los nueve son obligatorios y llevan esos nombres exactos.

- Las posiciones salen del manifest (el FBX no trae Attachments); `VehicleAssembler` los crea.
- **Coordenadas universales (guía 5.2):** en autos del mismo `bodyType`, `Socket_Spoiler` debe estar a la misma distancia del parachoques trasero y a la misma altura (±1,5 studs); `collect_models.py` y `check_vehicle.py` avisan si no. Así un alerón sirve para todos los autos de su clase sin offsets a mano.
- En un auto que se maneja, `VehicleBody` sube `Socket_Wheel_*` sobre el buje (origen del rayo de suspensión); ver [luau-side.md](luau-side.md).

## 5. Lo que NO lleva malla (solo estadísticas)

ECU, caja de cambios, turbos, frenos e inyectores mejoran estadísticas, interfaz y audio, no geometría (guía §4). El skill no modela nada de esto.

## 6. Variedad con el mínimo esfuerzo

1. **Llantas y neumáticos compartidos:** una biblioteca de 10 llantas y 5 neumáticos que encaja en cualquier auto reescalando por código (`VehicleAssembler.scaleWheels`). Pendiente de construir; el pivote en el buje ya lo permite.
2. **Un chasis, varias versiones:** activar o desactivar submallas opcionales (la caja `Bed` de una pick-up, un `Roof` aparte).
3. **Color por `Part.Color`**, no por texturas: cero memoria de textura en móvil.
4. **Livery dinámico (guía 2.3)** exige UV unificado entre chasis: *fuera de alcance de la versión 1.0.0* (el spec acepta `auto_unwrap`, pero no se usa). Se documenta como pendiente en el `_PARTS.md` si el juego lo pide.

## 7. Unidades y ejes

- 1 stud = 0,28 m (un auto de 4,4 m mide ~15,9 studs). El spec se escribe en **cm**; el exportador convierte.
- Espacio del spec (biblioteca `veh`): +X adelante, +Y izquierda, +Z arriba, origen donde el spec lo ponga. Espacio del manifest y del FBX (marco de Roblox): +X derecha, +Y arriba, +Z atrás, **la trompa apunta a −Z**, origen en el piso bajo el centro del auto. El exportador recentra y gira; el spec no se escribe en el marco de Roblox. El archivo FBX guarda ese marco girado 180° sobre Y para compensar al importador de Studio; el manifest y el modelo importado quedan en el marco de Roblox.
- Detalle y justificación: [manifest-format.md](manifest-format.md).

## 8. Lista de revisión antes de entregar

- [ ] `check_vehicle.py` sin errores ni avisos sin explicar.
- [ ] Triángulos dentro del `tri_budget`, y excepción de la guía documentada en `decisions`.
- [ ] Renders de revisión aprobados por el usuario (lateral, frente, planta, 3/4).
- [ ] Nombres de pieza y socket intactos (el código de Luau los busca por nombre).
- [ ] `<Asset>_PARTS.md` generado y entregado al usuario.
- [ ] Import en Studio y `VehicleBody.verify` leído (lo hace el usuario; ver [studio-import.md](studio-import.md)).
