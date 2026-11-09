# TravesurasBrainrot

Simulador de travesuras con persecución por estrellas al estilo GDA: haces travesuras en una ciudad de dibujos animados, los policías *brainrot* que te ven te persiguen (hasta 6★), subes de nivel para correr más rápido y ascendes (prestigio) para empezar de cero con ventaja. Se puede jugar en bandas de hasta 8.

El diseño completo está en [GDD.md](GDD.md); los documentos de cada etapa, en [design/](design/): `DATA.md`, `ART.md` y `LEVELS.md`.

## Estado

| Etapa | Estado |
| --- | --- |
| Diseño, datos, arte, niveles | Hechos (GDD, `DATA.md`, `ART.md`, `LEVELS.md` y sus validadores) |
| Código del servidor | Hecho: 18 cores (con `Plots` y `Achievements`), 3 puentes y `Game` (con `Transit` y `Hub`) |
| Cliente | `Controls.client.luau` (atajos) y la interfaz en `src/client/UI` (9 pantallas: HUD, avisos, acciones, minijuegos, tienda, carrera, banda, Sala y La Guarida) |
| Pase de arte (`Environment.json`) | Hecho con Parts y prefabs (Times Square en el Centro, muelle con rueda de la fortuna en la Playa, escuela japonesa en el Colegio); sin assets ni imágenes del usuario |
| Analíticas | Hechas: `AnalyticsSchema.json` y `Analytics.luau` (solo envían desde una experiencia publicada) |
| LiveOps | Desactivado |
| Monetización | Código listo; **ofertas desactivadas** hasta cargar los IDs reales |

## Cómo abrirlo

Requiere [Rojo](https://rojo.space) 7.2 o superior (probado con 7.7.1). Desde la raíz del repositorio:

```bash
rojo build -o build/TravesurasBrainrot.rbxlx   # genera el place
rojo serve                                      # o sincroniza con Studio
```

Abre `build/TravesurasBrainrot.rbxlx` en Roblox Studio (o conecta el plugin de Rojo con `rojo serve`). Para probar el guardado real activa *Game Settings → Security → Enable Studio Access to API Services*; sin eso `PlayerData` usa memoria y lo avisa en el Output.

Para analizar el código con luau-lsp:

```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=<ruta>/globalTypes.None.d.luau --sourcemap=sourcemap.json --ignore="**/*.json" src
```

## Cómo se juega

1. Apareces en **La Guarida** (el lobby, zona segura). Reclama una parcela en un pedestal libre (**E**), mira los logros y a los demás jugadores con **H**, y entra al portal amarillo para ir al **Barrio Papa**. Allí camina hasta un punto de travesura (el aviso dice "Hacer travesura") y pulsa **E**.
2. Los policías **no te persiguen mientras no tengas estrellas**: solo si un policía ve (u oye) una travesura tuya aparece la primera estrella. Corre: la Patata es más lenta que tú.
3. Escóndete en un arbusto o contenedor, o sigue corriendo, hasta perder las estrellas.
4. Vuelve a una **Guarida** y mantén el aviso para **depositar** el Botín. Si te arrestan, pierdes parte del Botín (nunca el Dinero ya depositado).
5. Compra mejoras en La Guarida, sube de nivel y desbloquea distritos (cada portal pide su nivel), herramientas y el techo de estrellas.

Controles: **Q** Embestida · **F** Empujón · **1 a 5** herramientas (cuando las compras). En celular aparecen botones en pantalla.

## Qué parámetros editar

Todo número ajustable está en [src/shared/Config.luau](src/shared/Config.luau) con los nombres del GDD ("Parámetros ajustables") y se lee con `Tuning.get("Seccion.Valor")`: velocidad, umbrales de estrellas, policías, travesuras, mejoras, Ascensión, Sala AFK, banda y más. El contenido propio del juego (aspecto de los policías, nombres de banda, ofertas de Robux) está en `src/server/Game/`.

## Estructura

```text
default.project.json   proyecto Rojo (raíz)
GDD.md · design/       diseño y documentos de cada etapa
src/shared/            Config, Catalog, Destinations, Net, Tuning, Style, Signal, Theme.json, Levels.json, DataTypes
src/server/            Bootstrap, Telemetry, LevelLoader, Data/, Modules/ (cores), Bridges/, Game/
src/client/            Controls.client.luau y UI/ (kit y 9 pantallas del UI designer)
```

Las capas siguen la [arquitectura de módulos](.claude/skills/roblox-game-builder/references/module-architecture.md). `Catalog.luau`, `Destinations.luau` y `Net.luau` viven en `src/shared/` aunque el verificador los marque como "fuera de las capas": son datos y canal compartidos por todos los cores, y moverlos a `Modules/` obligaría a que un core requiera a otro.

## IDs y configuración externa pendientes

Hasta que existan en Creator Hub, estas ofertas **no se pueden comprar** (ID 0):

| Oferta | Tipo | Clave | Dónde cargar el ID |
| --- | --- | --- | --- |
| Dinero ×2 | Game Pass | `money2x` | `Game/Content.luau` → `passes` |
| Aura Brainrot VIP | Game Pass | `aura_vip` | `Game/Content.luau` → `passes` |
| Alijo extendido | Game Pass | `stash_extended` | `Game/Content.luau` → `passes` |
| Teléfono de Guarida | Game Pass | `phone` | `Game/Content.luau` → `passes` |
| Paquetes de Dinero (3) | Developer Product | `pack_small`, `pack_medium`, `pack_large` | `Game/init.luau` → `products` |
| Soborno | Developer Product | `soborno` | `Game/init.luau` → `products` |

La Fianza del GDD queda para después. No se hacen compras con Robux sin tu autorización.

## Verificación

| Nivel | Resultado |
| --- | --- |
| Archivo/build | `rojo build` correcto (Rojo 7.7.1) |
| Análisis estático | `luau-lsp analyze` sin errores; `check_game.py` con 0 errores y las advertencias de arriba; `check_data.py` y `validate_levels.py` con 0 errores |
| Niveles | `Levels.json` validado (lobby + 6 distritos aislados, 548 piezas) |
| Studio | **No probado**: hay que recorrer el loop completo (lobby → portal → distrito → portal de regreso), las parcelas, los logros, el guardado (entrar, salir y volver), el orden de `PlayerRemoving` (depósito al salir sin estrellas), los policías sobre el mapa, que la patrulla ignore a quien no tiene estrellas, que el streaming no muestre otro distrito y la arena |
| Datos/monetización | Sin probar; ofertas desactivadas |
| Servicios publicados | Sin probar (DataStore, MarketplaceService y viajes) |

## Limitaciones conocidas

- Los minijuegos y las pantallas se escribieron sin poder probarlos en Studio: pueden necesitar ajustes de tamaño en celulares chicos.
- Los íconos de la interfaz son emojis (pendiente de arte propio).
- Los policías se mueven con `Humanoid:MoveTo` y rutas solo cuando se atascan; la forma de los modelos (Humanoid sin piernas) hay que verla en Studio.
- La iluminación por distrito (presets `playa`, `neon`, `queso`, `puerto`, `sala`) no se puede aplicar desde el servidor (Roblox tiene una sola luz); hoy se aplica `default` en todo el mapa y queda como pedido de interfaz.
- La Sala AFK limita 6 jugadores por orden de llegada; el volumen físico de la sala lo viste el pase de arte.
- La física de los policías y el Dash dependen del motor y hay que ajustarlos jugando.
- Los viajes entre places (`placeId` en `Destinations.luau`) están escritos pero no se probaron: hoy ningún destino los usa y `TeleportService` no funciona en Studio.
- El fundido a negro del viaje usa su propio `ScreenGui` a pantalla completa (a propósito); el verificador de UI lo avisa.
