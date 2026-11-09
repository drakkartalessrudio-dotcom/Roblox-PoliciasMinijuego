# Formato del tema: `Theme.json` (schemaVersion 1)

`src/shared/Theme.json` guarda las decisiones visuales como datos. Rojo lo convierte en el ModuleScript `ReplicatedStorage.Shared.Theme`; el código lo lee con `Style` (plantilla del builder): `Style.color("hazard")`, `Style.font("heading")`, `Style.material("surface")`, `Style.metric("cornerRadius")` y, en el servidor, `Style.applyLighting("default")`.

Ejemplo completo: [Theme.json del obby](../assets/example/Theme.json). Listas de fuentes, pesos y materiales verificadas el 12 de octubre de 2026 contra las definiciones de tipos de Roblox.

## Raíz

| Campo | Obligatorio | Descripción |
| --- | --- | --- |
| `schemaVersion` | Sí | Siempre `1` |
| `name` | No | Nombre del estilo, por ejemplo "Noche volcánica" |
| `palette` | Sí | Colores con nombre en camelCase → `#RRGGBB` |
| `roles` | Sí | Rol → nombre de un color de la paleta |
| `materials` | No | Rol → valor de `Enum.Material` |
| `fonts` | Sí | Tipo de texto → `{ "font": <Enum.Font>, "weight": <Enum.FontWeight> }` |
| `ui` | No | Métricas de interfaz |
| `lighting` | No | Estilo y presets de iluminación |
| `checks` | No | Pares extra para el validador: `{ "foreground", "background", "kind": "text" o "ui" o "gameplay" }` |
| `validation` | No | Umbrales: `textContrast` (4.5), `uiContrast` (3.0), `minDeltaE` (25) |

## Roles

| Rol | Obligatorio | Qué es |
| --- | --- | --- |
| `background` | Sí | Cielo, vacío, fondo lejano |
| `surface` | Sí | Superficie jugable principal |
| `surfaceAlt` | No | Variación de superficie (bordes, plataformas secundarias) |
| `hazard` | Sí | Lo que daña; color exclusivo |
| `interactive` | Sí | Lo que el jugador toca para avanzar (checkpoints, botones del mundo) |
| `goal` | Sí | Metas y objetivos |
| `reward` | Sí | Recompensas y coleccionables |
| `panel` | Sí | Fondo de paneles de UI |
| `panelAlt` | No | Paneles secundarios |
| `text` | Sí | Texto principal sobre `panel` |
| `textMuted` | Sí | Texto secundario sobre `panel` |
| `textOnAccent` | Sí | Texto sobre botones `accent` |
| `accent` | Sí | Acción principal de la UI |
| `danger` | Sí | Errores y avisos de peligro en la UI |
| `success` | Sí | Confirmaciones |
| `warning` | No | Advertencias que no son errores |

Puedes agregar roles propios del juego (por ejemplo `teamRed`). Si dos roles deben distinguirse, agrégalos en `checks`.

## Fuentes

Valores de `Enum.Font` vigentes: AmaticSC, Antique, Arcade, Arimo, ArimoBold, Bangers, Bodoni, BuilderSans, BuilderSansBold, BuilderSansExtraBold, BuilderSansMedium, Cartoon, Code, Creepster, DenkOne, Fantasy, Fondamento, FredokaOne, Garamond, GrenzeGotisch, Highway, IndieFlower, JosefinSans, Jura, Kalam, LuckiestGuy, Merriweather, Michroma, Nunito, Oswald, PatrickHand, PermanentMarker, Roboto, RobotoCondensed, RobotoMono, Sarpanch, SciFi, SourceSans (y variantes), SpecialElite, TitilliumWeb y Ubuntu. Gotham, Arial y Legacy están obsoletas.

Pesos de `Enum.FontWeight`: Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold y Heavy. Si la familia no tiene ese peso, Roblox usa el más cercano.

Tipos de texto obligatorios: `heading` y `body`. Habituales: `label` (botones y etiquetas) y `number` (marcadores); el kit del UI designer usa los cuatro.

## Métricas de UI (`ui`)

`cornerRadius`, `strokeThickness`, `spacing`, `panelTransparency` (0 a 1), `minTouchTarget` (px, 44 o más), `textSizeMin` y `textSizeMax`. El kit del UI designer usa todas: con `design.ui`, `check_ui.py` las exige junto con las fuentes `label` y `number`.

## Iluminación (`lighting`)

Los presets son los climas del juego. Sin pase de arte, el builder aplica `default`; con él, el environment artist elige en `Environment.json` cuál usa el juego y te pide uno nuevo si un nivel necesita otro clima.

| Campo | Descripción |
| --- | --- |
| `style` | `Soft` o `Realistic` (`Lighting.LightingStyle`). Va en `default.project.json`: no se cambia por script |
| `prioritizeQuality` | `Lighting.PrioritizeLightingQuality`. También va en el proyecto |
| `presets` | Preset con nombre → propiedades. `default` es obligatorio |

Propiedades de un preset (las ausentes no se tocan):

| Propiedad | Rango | En Roblox |
| --- | --- | --- |
| `clockTime` | 0 a 24 | `Lighting.ClockTime` |
| `brightness` | 0 a 10 | `Lighting.Brightness` |
| `exposure` | -3 a 3 | `Lighting.ExposureCompensation` |
| `environmentDiffuseScale`, `environmentSpecularScale` | 0 a 1 | Iguales en `Lighting` |
| `shadowSoftness` | 0 a 1 | `Lighting.ShadowSoftness` |
| `globalShadows` | booleano | `Lighting.GlobalShadows` |
| `ambient`, `outdoorAmbient`, `colorShiftTop`, `colorShiftBottom` | color | `Ambient`, `OutdoorAmbient`, `ColorShift_Top`, `ColorShift_Bottom` |
| `fog` | `color`, `start`, `end` | Niebla de `Lighting` |
| `atmosphere` | `density` y `offset` (0 a 1), `glare` y `haze` (0 a 10), `color` y `decay` | `Atmosphere` |
| `colorCorrection` | `brightness`, `contrast`, `saturation` (-1 a 1), `tint` | `ColorCorrectionEffect` |
| `bloom` | `intensity` (0 a 10), `size` (0 a 56), `threshold` (0 a 4) | `BloomEffect` |
| `sunRays` | `intensity` y `spread` (0 a 1) | `SunRaysEffect` |

Los colores de la iluminación pueden ser nombres de la paleta o hexadecimales: los tonos de ambiente rara vez forman parte de la paleta de juego.
