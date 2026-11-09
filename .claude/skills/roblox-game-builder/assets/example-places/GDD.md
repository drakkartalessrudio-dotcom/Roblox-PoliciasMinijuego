---
project:
  name: PlazaYTorre
  mode: prototype
  genre: obby
  places:
    - id: plaza
      role: start
      maxPlayers: 30
    - id: torre
      role: area
      maxPlayers: 12
  platforms: [desktop, mobile]
design:
  levels: true
monetization:
  enabled: []
analytics:
  enabled: false
liveops:
  enabled: false
---

# PlazaYTorre

Ejemplo de la fábrica para una experiencia con varios places. Es chico a propósito: una plaza de entrada con un portal y una torre de saltos en otro place. Muestra cómo comparten código los places, cómo cada uno construye solo sus niveles y cómo se viaja entre ellos.

## Concepto

El jugador aparece en una plaza tranquila. Un portal lleva a la torre, un obby corto de dos niveles en su propio place; al llegar a la cima vuelve a la plaza. Público general; sesiones de 3 minutos.

## Loop principal

Entrar a la plaza → cruzar el portal → subir la torre → volver a la plaza.

## Onboarding

1. `joined`: aparece en la plaza, de frente al portal.
2. `portal`: cruza el portal hacia la torre.

## Progresión

Dos niveles de la torre, el segundo un poco más exigente. Llegar a la cima devuelve a la plaza.

## Parámetros ajustables

| Parámetro | Valor | Para qué sirve |
| --- | --- | --- |
| `Travel.PortalCooldown` | 3 | Segundos entre dos intentos de viaje del mismo jugador por el portal |
| `Respawn.Time` | 1.5 | Segundos entre morir y reaparecer en la torre |

## Places y viajes

| Place | Rol | Jugadores | Qué tiene |
| --- | --- | --- | --- |
| `plaza` | start | 30 | La plaza y el portal (nivel `plaza`) |
| `torre` | area | 12 | El obby (niveles `torre-1` y `torre-2`) |

| De | A | Cuándo | Servidor | Si falla |
| --- | --- | --- | --- | --- |
| `plaza` | `torre` | Al tocar el portal | Público (Roblox elige uno con lugar) | El jugador se queda en la plaza; puede volver a intentar después de `Travel.PortalCooldown` |
| `torre` | `plaza` | Al tocar la meta del último nivel | Público | El jugador vuelve al comienzo de la torre |

No viaja ningún dato: el juego no guarda progreso. En Studio no hay viajes; cada place se prueba por separado.

## KPIs objetivo

- Porcentaje de jugadores que cruzan el portal en su primera sesión: medir línea base.

## Arquitectura

```text
default.project.json          place plaza (PlaceKey "plaza")
places/torre.project.json     place torre (PlaceKey "torre"), mismas carpetas src/
src/shared/  Config.luau, Tuning.luau, Levels.json, Places.json (registro de places), Place.luau (lectura del registro)
src/server/  Bootstrap.server.luau (entrada de los dos places), LevelLoader.luau, Travel.luau (viajes), Telemetry.luau
src/server/Modules/  Plaza/ (core: portal), Tower/ (core: reglas de la torre)
src/server/Game/     init.luau (composición: arranca Plaza o Tower según el rol del place)
src/client/  TravelNotice.client.luau (avisa en el Output si un viaje falla)
```

Orden de inicio: `LevelLoader.applyPhysics` → `LevelLoader.build` solo con `Place.levels(Levels)` → `Game.start` → `Plaza.init` y `Plaza.start` en el place de inicio, o `Tower.init` y `Tower.start` en la torre.

### Mapa de módulos

| Módulo | Capa | Responsabilidad | API y eventos | Datos que posee | Excepción |
| --- | --- | --- | --- | --- | --- |
| `Plaza` | core | Portales de la plaza hacia otros places | `init({ built })`, `start()` | — | — |
| `Tower` | core | Peligros, metas y vuelta a la plaza | `init({ built, physics })`, `start()` | — | — |
| `Game` | main | Elige qué core arranca según `Place.role()` | `start({ built, physics })` | — | — |

Sin RemoteEvents. Los viajes salen del servidor con `Travel`; el cliente solo lee el atributo `TravelFailed`.

## Assets y servicios

Ninguno. Los PlaceId de `plaza` y `torre` están pendientes: el usuario crea la experiencia con `plaza` como start place, agrega `torre` como place nuevo y carga los dos IDs en `src/shared/Places.json` y aquí.

## Suposiciones y criterios de aceptación

- Cada place, abierto solo en Studio, construye únicamente sus niveles.
- En la experiencia publicada, el portal lleva a la torre y la meta final devuelve a la plaza.

## Pendientes entre skills

Ninguno.
