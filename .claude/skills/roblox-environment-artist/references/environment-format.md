# Formato del pase de arte: `Environment.json` (schemaVersion 1)

`src/shared/Environment.json` describe el pase de arte como datos. Rojo lo convierte en el ModuleScript `ReplicatedStorage.Shared.Environment`; `EnvironmentLoader.apply(built, Environment)` lo aplica en el servidor después de `LevelLoader.build`. Ejemplo completo: [Environment.json del obby](../assets/example/Environment.json).

## Convenciones

- Studs y grados. Las posiciones son relativas al `origin` de cada nivel, como en `Levels.json`, y marcan el **centro**.
- Un color es un rol de `Theme.json` (`surface`, `hazard`…) o un nombre de su paleta (`stone`). Nunca un hexadecimal.
- Un material es un nombre de `Enum.Material` (`Slate`) o un rol de `Theme.materials` (`surface`).
- Un asset del usuario se nombra por su clave en `assets`; los IDs solo aparecen ahí.
- JSON no admite comentarios: la intención va en `ENVIRONMENT.md`.

## Raíz

| Campo | Obligatorio | Descripción |
| --- | --- | --- |
| `schemaVersion` | Sí | Siempre `1` |
| `lighting` | No | `preset`: nombre de `Theme.lighting.presets` (por defecto `default`); `places`: place → preset, en juegos con varios places; `clouds`: `{ cover, density, color }`, cobertura y densidad de 0 a 1 |
| `terrainColors` | No | Material de terreno → color, con `Terrain:SetMaterialColor` (no se aplica al agua) |
| `pieces` | No | Tipo de pieza → estilo, para todos los niveles |
| `prefabs` | No | Nombre → prefab |
| `assets` | No | Nombre → asset del usuario (ver abajo) |
| `levels` | No | Id de nivel de `Levels.json` → pase de arte del nivel |
| `budget` | No | `maxParts` (3000), `maxLights` (24) y `maxShadowLights` (2): presupuesto de la fábrica, no de Roblox |

## Estilo de pieza

Se aplica por tipo (`platform`, `spawn`, `checkpoint`, `goal`, `truss`, `wall`, `hazard`, `collectible`, `zone`, `prop`) y con la clave `moving` a toda pieza con `motion` que no sea un peligro. Orden: tipo global → tipo del nivel → `moving` → pieza (`overrides`). Un tipo sin estilo conserva el aspecto de `Levels.json`.

| Campo | Descripción |
| --- | --- |
| `color` | Color de la pieza. En `hazard`, `checkpoint`, `goal` y `collectible` el loader usa siempre el color de su rol (`hazard`, `interactive`, `goal`, `reward`) |
| `material` | Material. La pieza conserva las propiedades físicas del material que tenía: el juego no cambia |
| `materialVariant` | Nombre de un asset `materialVariant`: usa su material base y su variante, con la misma regla de física |
| `texture` | Nombre de un asset `texture`, o `{ asset, studsPerTile, faces, color, transparency }`. `studsPerTile` es un número o `[u, v]` (por defecto 8); `faces`, una lista de `Top`, `Bottom`, `Front`, `Back`, `Left` y `Right` (por defecto `Top` en pisos, los cuatro lados en muros y todas en el resto) |
| `variation` | 0 a 0,15: variación de brillo estable por pieza. No se aplica a los tipos de color fijo |
| `dressing` | Adorno → color o `{ color, material, ... }` con los campos propios de cada adorno. Nunca en piezas que se mueven |

Adornos, todos sin colisión, sin `Touched` y fuera de los raycasts. Se separan 0,02 studs de los bordes y se apoyan encima de la cara, así nunca comparten plano con otra pieza:

| Adorno | Piezas | Forma | Campos propios |
| --- | --- | --- | --- |
| `trim` | 4 | Borde fino sobre la cara de arriba, dentro de la planta | `width` |
| `border` | 4 | Guarda sobre el piso, metida `inset` studs desde el borde (por defecto 2) | `width`, `inset` |
| `grid` | 1 por junta | Juntas de baldosas cada `spacing` studs (por defecto 8) | `spacing`, `width` |
| `checker` | 1 por baldosa | Baldosas alternadas de `spacing` studs (por defecto 8); máximo 400 por pieza | `spacing` |
| `rock` | 2 | Dos bloques debajo de la pieza (85 % y 55 % de su planta) | — |
| `pillar` | 1 | Pilar vertical desde la pieza hasta el peligro de abajo, o 20 studs | — |
| `base` | 1 | Cimiento debajo de la pieza, de su misma planta y `depth` studs (por defecto 4): tapa el hueco con el terreno | `depth` |
| `baseboard` | 1 por cara | Zócalo al pie del muro | `height` |
| `cornice` | 1 por cara | Cornisa en lo alto del muro, sobresale 0,3 studs | `height` |
| `band` | 1 por cara | Franja horizontal a la altura relativa `at` (por defecto 0,62) | `height`, `at` |
| `pilasters` | Varias por cara | Pilastras cada `spacing` studs (por defecto 12), de pie a cornisa | `width`, `spacing` |

`trim`, `rock`, `pillar` y `base` van en `platform`, `spawn`, `checkpoint`, `goal`, `wall` y `prop`; `border`, `grid` y `checker`, en piezas pisables; los adornos de muro, en `wall` y `prop`. Todos menos `rock` y `pillar` necesitan piezas con forma de bloque. Un muro largo se adorna en sus dos caras largas; uno casi cuadrado, en las cuatro.

## Prefab

```json
"lamp": {
  "size": [2, 10, 2],
  "colors": { "secondary": "dusk", "glow": "mist", "light": "ember" },
  "parts": [
    { "shape": "Cylinder", "axis": "Y", "center": [0, -0.05, 0], "size": [0.2, 0.8, 0.2], "color": "secondary", "material": "Metal" },
    { "shape": "Block", "center": [0, 0.41, 0], "size": [0.5, 0.1, 0.5], "color": "glow", "material": "Neon",
      "light": { "type": "Point", "color": "light", "brightness": 1.2, "range": 14 } }
  ]
}
```

| Campo | Descripción |
| --- | --- |
| `size` | Caja del prop en studs; cada prop puede usar otra |
| `colors` | Ranura → color. Las partes nombran ranuras, así cada juego cambia la paleta sin tocar las partes |
| `parts[].shape` | `Block`, `Ball`, `Cylinder` o `Wedge` |
| `parts[].center`, `parts[].size` | Fracciones de la caja: centro de -0,5 a 0,5 y tamaño de 0 a 1 por eje. Una esfera usa el menor eje; un cilindro usa `axis` (X, Y o Z, por defecto Y) como largo |
| `parts[].rotation` | Grados, después del tamaño. El validador avisa si la parte se sale de la caja |
| `parts[].color`, `material`, `transparency` | Ranura o color, material y transparencia de 0 a 0,9 |
| `parts[].light` | `{ type: Point, Spot o Surface, color, brightness, range, shadows, angle, face }`. `color` puede ser una ranura. Roblox limita `range` a 60 studs |

## Assets del usuario

```json
"assets": {
  "fuente": { "kind": "model", "file": "assets/models/Fuente.rbxm", "size": [12, 9, 12], "source": "Creator Store, «Fuente de plaza» de <autor>", "license": "Uso libre de la Creator Store" },
  "baldosaRosa": { "kind": "texture", "id": "rbxassetid://123456789", "source": "Subida por el usuario", "license": "Propia" },
  "ladrillo": { "kind": "materialVariant", "file": "assets/materials/Ladrillo.rbxm", "base": "Brick", "source": "Hecha por el usuario", "license": "Propia" },
  "pajaros": { "kind": "sound", "id": "rbxassetid://987654321", "source": "Biblioteca de audio de Roblox", "license": "Uso en experiencias de Roblox" },
  "ondear": { "kind": "animation", "id": "rbxassetid://555555555", "source": "Subida por el grupo dueño", "license": "Propia" }
}
```

| `kind` | Campos | Uso |
| --- | --- | --- |
| `model` | `file` (`.rbxm` o `.rbxmx`), `size` opcional | Props con `asset` |
| `materialVariant` | `file`, `base` (Enum.Material), `name` opcional (por defecto, el nombre del archivo) | `materialVariant` en estilos |
| `texture` | `id` | `texture` en estilos |
| `sound` | `id` | `sounds` en niveles |
| `animation` | `id` | `animation` en props con modelo |

Todos llevan `source` y `license`. Los modelos van en `ServerStorage.EnvironmentAssets` y las variantes en `MaterialService`, mapeados por el builder. Guía completa: [assets del usuario](user-assets.md).

## Nivel

| Campo | Descripción |
| --- | --- |
| `pieces` | Estilos por tipo solo para este nivel |
| `overrides` | Id de pieza → estilo |
| `props` | `{ id, prefab, position, size?, yaw?, collide?, colors? }` o, para un modelo del usuario, `{ id, asset, position, size, yaw?, collide?, animation? }`. `position` es el centro de la caja; `yaw`, el giro en grados; `collide` vale `false` por defecto. Un modelo se escala para entrar en `size` |
| `terrain` | `{ shape, material, position, size?, radius?, height?, rotation? }`: `Block` y `Wedge` usan `size`; `Ball`, `radius`; `Cylinder`, `radius` y `height`. `Air` borra terreno. Con sus bordes en múltiplos de 4 y a 4 studs o más de toda pieza |
| `lights` | `{ id, type, position, color, brightness, range, shadows }`: luz en un punto invisible |
| `sounds` | `{ asset, position?, volume?, range? }`: sonido en bucle; sin `position` se oye en todo el mapa |

Materiales de terreno (verificados el 13 de octubre de 2026): Asphalt, Basalt, Brick, Cobblestone, Concrete, CrackedLava, Glacier, Grass, Ground, Ice, LeafyGrass, Limestone, Mud, Pavement, Rock, Salt, Sand, Sandstone, Slate, Snow, Water, WoodPlanks y Air. El terreno se arma con vóxeles de 4 × 4 × 4 studs.

## Qué valida `check_environment.py`

- Formato de todos los campos, niveles que existan en `Levels.json`, piezas de `overrides` que existan en su nivel, prefabs y assets que existan.
- Colores del tema, sin hexadecimales; tipos de color fijo con su rol; plataformas, `spawn`, `truss` y piezas móviles que no se confundan con el peligro (error) y decoración que no use colores de juego ni se confunda con el peligro (aviso).
- Espacio, con la física de `Levels.json`:
  - **aire del salto**: entre dos piezas seguidas del recorrido, del borde de una al de la otra, con 2 studs de margen y hasta la altura de salto más 6 studs. Nada de decoración ahí (error);
  - **alcance**: la planta de cada pieza pisable ampliada en el alcance de un salto, desde el peligro de abajo (o 50 studs en un recorrido lineal sin peligro debajo) hasta la altura de salto más 6 studs. Ahí nada sólido ni agua (error);
  - props sin colisión que tapan más de un cuarto de una superficie, o con forma de escalón al alcance (aviso).
- Aspecto: terreno a menos de 4 studs de una pieza (error); caras de distinto color en el mismo plano, con la escena armada como la arma el loader (aviso); muros y pisos de más de 300 studs² de plástico liso sin material, textura ni adorno de superficie (aviso).
- Presupuesto de piezas (niveles, adornos y props) y de luces, con y sin sombra; juntas y baldosas por pieza.
- Assets del usuario: origen y licencia, archivos que existen, IDs en el GDD y fuera de `assets` ninguno, carpetas mapeadas en `default.project.json`.
- `ENVIRONMENT.md` con cada nivel.
