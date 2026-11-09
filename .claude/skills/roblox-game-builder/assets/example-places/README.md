# PlazaYTorre

Ejemplo de la fábrica para una experiencia con **varios places**: una plaza de entrada (`plaza`, start place) con un portal, y una torre de saltos (`torre`) en otro place. Los dos places comparten el mismo código en `src/`; cada uno construye solo sus niveles y sabe en qué place corre por el `StringValue` `ReplicatedStorage.PlaceKey` que pone su proyecto de Rojo.

## Construir

Desde esta carpeta, con Rojo 7.2 o superior, un archivo por place:

```bash
rojo build default.project.json -o build/Plaza.rbxlx
```

```bash
rojo build places/torre.project.json -o build/Torre.rbxlx
```

Para editar en vivo: `rojo serve default.project.json` (plaza) o `rojo serve places/torre.project.json` (torre).

## Probar en Studio

Abre cada place por separado. En la plaza, tocar el portal no viaja: TeleportService no funciona en Studio y `Travel` lo avisa en el Output. En la torre, la meta final te devuelve al comienzo de la torre por la misma razón. Los viajes se prueban en la experiencia publicada.

## Publicar (lo hace el usuario)

1. Abre `build/Plaza.rbxlx` en Studio y publícalo como una experiencia nueva: será el start place.
2. Abre `build/Torre.rbxlx` → **Archivo → Publicar como** → elige la experiencia → **Agregar como place nuevo**.
3. Copia los dos PlaceId (Creator Hub → la experiencia → Places) en `src/shared/Places.json` y en la sección Assets y servicios del GDD, vuelve a construir y vuelve a publicar cada place sobre el suyo.
4. En Creator Hub, configura el tamaño de servidor de cada place (30 en la plaza, 12 en la torre) y, en el acceso de la torre, que solo se pueda entrar por teleport desde la experiencia.

## Archivos

| Archivo | Qué hace |
| --- | --- |
| `default.project.json` | Proyecto del place `plaza` (start place) |
| `places/torre.project.json` | Proyecto del place `torre`, con las mismas carpetas `src/` |
| `src/shared/Places.json` | Registro de places: start, rol, jugadores y PlaceId (0 = pendiente) |
| `src/shared/Place.luau` | Lectura del registro: place actual, rol, PlaceId y niveles de cada place (plantilla del builder) |
| `src/shared/Levels.json` | Niveles; cada uno declara su `place` (dueño: level designer) |
| `src/server/Bootstrap.server.luau` | Entrada de los dos places: construye los niveles del place y llama a `Game` |
| `src/server/Game/init.luau` | Composición: arranca `Plaza` o `Tower` según el rol del place |
| `src/server/Travel.luau` | Viajes entre places con reintentos (plantilla del builder) |
| `src/server/Modules/Plaza/init.luau` | Core: portal de la plaza |
| `src/server/Modules/Tower/init.luau` | Core: peligros, metas y vuelta a la plaza |
| `src/server/LevelLoader.luau`, `Telemetry.luau`, `src/shared/Tuning.luau`, `Config.luau` | Plantillas y ajustes de la fábrica |
| `src/client/TravelNotice.client.luau` | Avisa en el Output si un viaje falla |

## Estado de verificación

| Nivel | Estado |
| --- | --- |
| Archivos y build | `rojo build` correcto en los dos places con Rojo 7.7.1 |
| Análisis estático | `check_game.py` sin errores (avisa de los PlaceId pendientes); `luau-lsp` sin errores |
| Niveles | `validate_levels.py`: 0 errores, 0 advertencias |
| Studio | **Pendiente.** Cada place por separado: la plaza construye solo la plaza y la torre solo sus dos niveles |
| Servicios publicados | **Pendiente.** Viajes plaza → torre → plaza en la experiencia publicada |
