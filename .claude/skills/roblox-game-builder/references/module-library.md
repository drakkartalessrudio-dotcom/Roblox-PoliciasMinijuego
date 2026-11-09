# Librería de módulos

Los cores y los puentes que sirven para más de un juego viven en una librería común, [Roblox-Library](https://github.com/drakkartalessrudio-dotcom/Roblox-Library). Cada módulo tiene un manifiesto (`module.json`), un README que explica cómo usarlo, un CHANGELOG, su sección de datos si guarda y pruebas con Lune. Lo que hay está en su `CATALOG.md`.

La librería es opcional: sin ella, el builder escribe los módulos en el juego como siempre y lo anota en Pendientes (`builder → librería: módulos sin publicar (abierto)`).

## Dónde está

`library.py` la busca, en orden, en `--library <ruta>`, en la variable `ROBLOX_LIBRARY` y en `project.library` del frontmatter del GDD (ruta absoluta o relativa a la carpeta del juego). Es la carpeta que tiene `catalog.json`.

## 1. Buscar antes de escribir

Al armar el Mapa de módulos, por cada sistema del juego busca en el catálogo:

```bash
python <skill-dir>/scripts/library.py search misiones
```

- **Hay uno que sirve:** úsalo (paso 2). Lee su README: opciones de `init`, eventos y límites.
- **Sirve casi:** no lo copies y lo cambies en el juego. Mejóralo en la librería (paso 4) y después cópialo.
- **No hay:** escríbelo en el juego con las reglas de [arquitectura de módulos](module-architecture.md) y, al terminar, proponlo para la librería (paso 5).

## 2. Copiar un módulo al juego

```bash
python <skill-dir>/scripts/library.py add <Juego> Quests
```

Copia `src/` a `src/server/Modules/Quests/` (o a `Bridges/` si es un puente) y guarda en `library.lock.json` la versión, el commit de la librería y el hash de cada archivo. Al final lista lo que falta hacer a mano:

- **Config:** los ajustes que el módulo lee con `Tuning.get`, con su valor sugerido.
- **Datos:** si guarda, el data architect agrega su sección (`data/section.json` del módulo) con `library_section.py` y vuelve a generar `DataTypes.luau`. Si la sección cambió en una versión nueva, `library_section.py --since <versión anterior>` agrega sus migraciones como una versión nueva del esquema del juego.
- **Núcleo:** las plantillas de la fábrica que el módulo necesita y el juego todavía no tiene.
- **Un puente** necesita sus dos cores: cópialos primero.
- **Mapa de módulos:** la columna **Origen** dice `librería Quests@1.0.0` (o `propio` para lo que se escribió en el juego, como `Game`).

Después, en `Game`, el contenido del juego entra por `init` y por `connect`, como en cualquier core. La copia **no se edita**: `check_modules.py` (regla M8) avisa si difiere del lock.

## 3. Saber en qué estado está y actualizar

```bash
python <skill-dir>/scripts/library.py status <Juego>
python <skill-dir>/scripts/library.py update <Juego> Quests
```

`status` muestra, por cada módulo copiado, la versión, si la copia sigue igual o tiene cambios locales y si la librería tiene una versión más nueva. `library.py diff <Juego> Quests` muestra los cambios locales contra la versión copiada (la toma de la etiqueta `Quests@<versión>` de la librería).

`update` copia la versión más nueva y muestra las entradas del CHANGELOG desde la que tenía el juego. Si sube la versión mayor, revisa en `Game` las llamadas, eventos y opciones que cambiaron; si además cambia la sección de datos, el data architect agrega sus operaciones de migración como una versión nueva del `DataSchema` del juego. Si un puente del juego deja de aceptar la versión nueva, `update` también lo lista.

## 4. Mejorar un módulo de la librería

Cuando un juego necesita algo que un módulo de la librería no hace, el cambio no se queda escondido en la copia:

```bash
python <skill-dir>/scripts/library.py bump Quests minor --note "Misiones con fecha de fin." --from-game <Juego>
python <skill-dir>/scripts/library.py release Quests
python <skill-dir>/scripts/library.py update <Juego> Quests
```

1. **`bump`** sube la versión con semver (patch para un arreglo, minor para algo nuevo compatible y major si cambia la API, los eventos o la forma de su sección de datos), en una branch `module/<Nombre>-<versión>` de la librería (o en la branch donde ya estás). Agrega la entrada del CHANGELOG con cada `--note`, cambia la versión del README y, con `--from-game`, trae a `src/` los cambios de la copia del juego y anota el juego en `usedIn`. En una versión mayor deja marcadas las notas para actualizar y la migración de datos, y lista los puentes cuyo rango ya no la acepta.
2. Termina el cambio en la librería: el código sin contenido del juego (lo propio sigue entrando por las opciones), el README (API, opciones, límites), las pruebas y, si cambia la sección, las operaciones de migración en `data/section.json`.
3. **`release`** no hace commit si queda algo marcado *(por completar)*, si `check_library.py` da errores o si fallan las pruebas de Lune del módulo y de sus puentes. Si pasa, hace commit solo de esos módulos y del catálogo y crea la etiqueta `<Nombre>@<versión>`. Un core con versión mayor y el puente que tuvo que ampliar su rango salen juntos: `release Quests Quests_Rewards`.
4. Subir la branch y las etiquetas y abrir el pull request lo aprueba el usuario.
5. **`update`** copia la versión nueva al juego. Antes del release, `add` y `update` no copian un módulo con cambios sin commit en la librería (salvo `--force`, para probarlo en el juego).

## 5. Publicar un módulo nuevo

Al cerrar un juego, los cores y puentes propios que no tienen nada del juego (las reglas de capas ya lo exigen) se proponen para la librería:

```bash
python <skill-dir>/scripts/library.py publish <Juego> Rewards --tags recompensas,diaria
```

`publish` copia el módulo a una branch `module/<Nombre>` de la librería y arma el borrador desde el código y el GDD: la API con sus firmas, los eventos con sus argumentos, las opciones de `export type Options`, los ajustes con el valor de `Config.luau` y el uso de Parámetros ajustables, las plantillas del núcleo que requiere, su sección de `DataSchema.json` (sin las migraciones del juego), el resumen de su fila del Mapa de módulos, `usedIn`, el README con todas sus secciones, el CHANGELOG y una prueba mínima. Lo que no puede deducir queda marcado *(por completar)*. Un puente se publica después de sus dos cores.

Completa el README y las pruebas, revisa que no quede contenido del juego y sigue con `release`. Después, `library.py add <Juego> Rewards` adopta la copia (es igual a la librería, no hace falta `--force`) y el Mapa de módulos cambia su Origen a `librería Rewards@1.0.0`.

La etapa **Librería** de `factory_status.py` (roblox-factory) resume todo esto: módulos copiados, copias con cambios, versiones que no existen, versiones nuevas, usos sin anotar y cores propios que se podrían publicar.

## 6. Anotar qué juegos usan cada módulo

```bash
python <skill-dir>/scripts/library.py record <Juego>
```

Anota en `usedIn` y en "Juegos que lo usan" la versión de cada módulo que el juego copió, y hace commit en una branch `usage/<Juego>`. `add` y `update` avisan cuando falta.

## Reglas

- Una copia de la librería no se edita en el juego: los cambios van a la librería con versión nueva (`bump` y `release`).
- La librería no tiene contenido de un juego: misiones, textos, IDs y tablas entran por `init` y `connect`.
- El núcleo (`Signal`, `Tuning`, `Telemetry`, `LevelLoader`, `PlayerData`, `DataTypes`) viene de la fábrica, no de la librería; cada módulo dice en `requires` qué versión necesita.
- La librería se cambia solo en una branch, con commit y etiqueta de `release`; subirla y abrir el PR lo aprueba el usuario.

[Aldea de Gremios](../assets/example-quests/README.md) usa los siete módulos de la librería, con su `library.lock.json`.
