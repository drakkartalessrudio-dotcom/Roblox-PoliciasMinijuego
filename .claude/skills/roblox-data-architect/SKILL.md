---
name: roblox-data-architect
description: Diseñar los datos que un juego de Roblox guarda de cada jugador. Decide qué se conserva, cómo se reparte en secciones con un módulo dueño, cómo se registra el progreso (misiones, niveles, inventario, monedas, hitos, recompensas diarias) y cómo crece con versiones y migraciones dentro de los límites de DataStore. Escribe design/DATA.md y src/server/Data/DataSchema.json y los valida con check_data.py. Úsalo cuando el GDD active design.data, cuando el usuario quiera guardar progreso, agregar o cambiar algo que se guarda, migrar datos viejos, diseñar la clase del perfil del jugador o averiguar por qué se pierden datos o se duplican compras. No decide qué promete el juego (roblox-game-designer), no escribe la lógica del juego (roblox-game-builder) ni el flujo de compra (roblox-monetization-developer-products).
metadata:
  version: "1.3.1"
  last_verified: "2026-10-14"
---

# Roblox Data Architect

Diseña el perfil del jugador para que guarde lo que el juego promete, crezca sin romper los perfiles que ya existen y nunca pierda ni duplique lo que el jugador ganó o pagó. El game designer decide **qué** se promete conservar; este skill decide **cómo** se guarda; el builder lo implementa.

Un error de datos es el más caro de la fábrica: un nivel mal hecho se corrige en la versión siguiente, un perfil sobrescrito con valores por defecto no vuelve.

## Qué produces y qué no

- Lees del `GDD.md`: "Estado y economía" (datos que se conservan, monedas, recuperación), progresión, monetización seleccionada, "Places y viajes" y el **Mapa de módulos** de la Arquitectura, si ya existe.
- Escribes, según el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md):
  - `design/DATA.md`, con la [plantilla](references/data-doc-template.md);
  - `src/server/Data/DataSchema.json`, con el [formato del esquema](references/schema-format.md);
  - `src/server/Data/Migrations.luau`, con una función por cada operación `custom` (parte de la [plantilla](assets/templates/src/server/Data/Migrations.luau));
  - `src/shared/DataTypes.luau`, generado con `gen_types.py` (no se edita a mano).
- Mantienes las plantillas del servicio de datos (`PlayerData`, `Session`, `Profile`, `Store`, `DataDebug` en [assets/templates](assets/templates/src/server/Data)): el builder las copia sin cambios, como copia `Analytics.luau` de las analíticas.
- En el frontmatter del GDD, la clave `data.persistence` (`persistent` o `memory`). `design.data: true` la activa el game designer, o tú si el usuario pidió guardar datos, como permite la excepción del contrato.
- No decides qué se promete: si el GDD promete algo imposible de guardar bien, o no dice qué se conserva, pídeselo al game designer con la regla de pendientes. No escribes la lógica del juego: los cores y la fachada de cada dominio los escribe el builder siguiendo `DATA.md` y el esquema, y copia las plantillas del servicio. Las reglas de entrega de una compra son de [Developer Products](../roblox-monetization-developer-products/SKILL.md); tú das la sección donde se registran los recibos.

## Reglas de la plataforma

Verificadas el 14 de octubre de 2026 en la [documentación de Roblox](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits):

- Un valor por clave tiene hasta **4.194.304 caracteres**, medidos con `JSONEncode`. El almacenamiento total es 500 MB más 1 MB por usuario histórico, medido comprimido.
- Por clave, 4 MB por minuto de escritura y 25 MB de lectura entre todos los servidores. Por servidor, 60 + 40 × jugadores pedidos de lectura y otros tantos de escritura por minuto; `UpdateAsync` gasta de los dos.
- El bloqueo de sesión se guarda en los metadatos de la clave y se toma y renueva dentro de `UpdateAsync` ([datos y compras](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing)). `BindToClose` tiene 30 segundos.
- Las versiones anteriores de una clave duran 30 días después de que otra escritura las reemplaza: sirven para recuperar un perfil dañado.
- Roblox reenvía los pedidos de borrado de datos de usuarios. Las plantillas de borrado automático aceptan claves con `{UserId}`, por eso la clave es `player_{UserId}` y ninguna otra clave guarda el UserId.

## 1. Leer lo que se promete

Haz una lista de promesas: cada cosa que el GDD dice que el jugador conserva (monedas, niveles, misiones, items, compras, rachas). Cada promesa es una fila de "Promesas del GDD" en `DATA.md` con el campo donde se guarda.

- Si el juego no promete conservar nada, la persistencia es `memory`: el juego usa la misma API y pasar a publicar es cambiar ese valor.
- `release-candidate` con progreso prometido, LiveOps o compras con beneficio que dura exigen `persistent`.
- Lo que no es promesa no se guarda: el estado de la ronda, el personaje, cooldowns cortos. Anótalo en "Estado de sesión".

## 2. Repartir en secciones

Un documento por jugador, con **una sección por core** que tenga datos propios, como las dos clases persistentes (perfil y misiones) de MyIsekai pero en una sola clave: un bloqueo, compra y beneficio en la misma escritura y un borrado simple.

- Cada sección tiene un único dueño: el core del Mapa de módulos que la escribe ([arquitectura de módulos](../roblox-game-builder/references/module-architecture.md)). Los demás cores la leen por la API de ese core, nunca directo.
- La sección `meta` (fechas, sesiones, tiempo de juego) es del servicio de datos (`PlayerData`).
- Si el juego necesita un core que todavía no está en el Mapa de módulos, nómbralo como dueño y deja el pedido `data-architect → builder: crear el core <Nombre> con la sección <sección> (abierto)`.
- No hagas un "perfil general" con campos de todos: es el antipatrón que más crece.

## 3. Diseñar los campos

Usa los [patrones de progreso](references/progress-patterns.md):

- **IDs estables, nunca posiciones.** Misiones, niveles, items y monedas se guardan en mapas por su ID; el catálogo (nombres, recompensas, facciones) vive en el código, en `Game`. Agregar contenido no cambia el esquema.
- **Banderas con fecha** para hitos y onboarding (`flags: map flagId → time`), no un booleano por paso.
- **Límites en todo lo que crece:** `maxEntries`, `maxItems` y `maxLength`. Sin ellos no se puede estimar el tamaño y el servicio no puede rechazar una escritura desbocada.
- **Hora del servidor** (`time`) para rachas, recompensas diarias y caducidades.
- **Recibos:** con Developer Products, una sección con rol `purchases` que guarda los `PurchaseId` procesados, para que `ProcessReceipt` sea idempotente.
- Nada de datos personales ni texto libre del jugador.

Con varios places, el documento es uno para toda la experiencia. Escribe en `DATA.md` el modelo de clases: qué fachada tiene cada core sobre su sección (por ejemplo `QuestData.isCompleted`, `start`, `complete`) y qué eventos publica el core.

## 4. Cambiar un esquema que ya existe

Si el juego ya se publicó o puede tener perfiles guardados:

1. Copia las secciones actuales a `history["<versión actual>"]` y sube `version` en 1.
2. Cambia las secciones.
3. Agrega la migración con operaciones declarativas (`move`, `add`, `set`, `remove`). Usa `custom` solo para lo que no se puede declarar y descríbelo para el builder.
4. Todo campo que desaparece se mueve o se borra explícitamente: el servicio descarta lo que el esquema no conoce.
5. Nunca reutilices un ID ni un nombre de campo con otro significado.

Si el juego ya guarda datos con su propio código (sin `PlayerData`), sus perfiles tienen otra forma: usa el mismo DataStore y patrón de clave, `document.legacy: true`, la forma vieja en `history["0"]` y una migración de 0 a 1 ([adoptar perfiles existentes](references/schema-format.md#adoptar-perfiles-existentes)). Sin eso, `PlayerData` no carga esos perfiles, y tampoco los pisa.

Agregar un campo o una sección con su valor por defecto no sube la versión ni necesita migración: al cargar, el servicio completa lo que falte. La versión sube cuando un campo se mueve, se renombra, se borra o cambia de tipo.

### Secciones que vienen de la librería

Un core copiado de la [librería de módulos](../roblox-game-builder/references/module-library.md) trae su sección en `data/section.json`, con el core como dueño. No la rediseñes en el juego: un cambio de forma va a la librería con versión nueva, y el juego lo recibe con su migración.

```bash
python <skill-dir>/scripts/library_section.py <Juego> <librería>/modules/Quests/data/section.json
python <skill-dir>/scripts/library_section.py <Juego> <librería>/modules/Quests/data/section.json --since 1.2.0
```

- **Primera vez** (`library.py add` lo pide): agrega la sección tal cual, sin subir la versión del esquema.
- **El módulo se actualizó** (`library.py update` lo pide, con la versión que tenía el juego en `--since`): si el fragmento trae migraciones posteriores, el script copia las secciones a `history`, sube la versión, reemplaza la sección y junta sus operaciones en una migración; sin migraciones, solo reemplaza la sección. Revisa la descripción de la migración en `DATA.md`.

Después corre `gen_types.py`. El formato del fragmento está en el [formato del esquema](references/schema-format.md#secciones-de-la-librería).

## 5. El servicio de datos

El esquema no es solo documentación: `PlayerData` lo lee en ejecución.

- Carga con **bloqueo de sesión** (en los metadatos de la clave, dentro de `UpdateAsync`); otro servidor espera o, si el bloqueo no se renovó en 400 segundos, lo toma, y el servidor viejo deja de guardar.
- **Migra** con las operaciones del esquema y las funciones de `Migrations.luau`, completa los valores por defecto y descarta lo que el esquema no conoce. Un perfil de una versión más nueva no se toca.
- **Valida cada cambio** contra el esquema: un `update` que rompe un tipo o un límite no se aplica.
- Guarda cada 180 segundos si hubo cambios, al salir y al cerrar el servidor; nunca guarda un perfil que no pudo cargar.
- **Compras:** `grantPurchase` registra el `PurchaseId` en la misma escritura que el beneficio.
- En Studio sin acceso a las APIs usa memoria y avisa; `DataDebug` muestra y resetea perfiles.

Cada core accede solo a su sección desde una **fachada** (`Modules/<Core>/<Core>Data.luau`) que escribe el builder; la API está en los [puntos de enganche del builder](../roblox-game-builder/references/hooks.md#playerdata-el-servicio-de-datos). Después de escribir o cambiar el esquema, genera los tipos:

```bash
python <skill-dir>/scripts/gen_types.py <Juego>
```

Las plantillas se prueban con Lune (`tools/tests/luau/data_service.spec.luau` en el repo de la fábrica): perfil nuevo, recarga, bloqueo y bloqueo vencido, carga fallida, migraciones, perfiles más nuevos, validación, compras repetidas y con guardado fallido, y tiempo de juego.

## 6. Verificar

```bash
python <skill-dir>/scripts/check_data.py <Juego>
```

En Windows, usa `python` o `py -3` si `python3` no existe. También acepta un `DataSchema.json` suelto. Con la carpeta del juego revisa además que las plantillas del servicio estén completas y sin cambios, que `Migrations.luau` tenga cada función `custom`, que `DataTypes.luau` esté al día y que cada `PlayerData.section(…, "x")` esté en el core dueño de `x`. Revisa el formato, la clave y el DataStore, los tipos y límites de cada campo, los antipatrones (booleanos por paso, listas por posición, datos personales), las migraciones (las simula con la forma de cada versión de `history`), el tamaño en el peor caso, los dueños contra el Mapa de módulos, la persistencia contra el GDD, la sección de recibos si hay Developer Products y que cada promesa de `DATA.md` apunte a un campo que existe. Corrige todos los ERROR; cada WARN se corrige o se explica en `DATA.md`.

`check_data.py` no prueba que el juego guarde bien. Eso se prueba en Studio con acceso a la API (entrar, salir y volver; carga fallida; cierre del servidor) y en una experiencia publicada (dos servidores). Publicar es una acción del usuario.

## Diagnóstico

- **"Se pierden datos":** ¿hay más de un lugar que escribe el DataStore? ¿Se guarda con `SetAsync` sin leer antes (sin `UpdateAsync`)? ¿Una carga fallida deja jugar con valores por defecto que después se guardan encima? ¿Un campo que cambió de nombre no tiene migración? ¿Se guarda al salir y al cerrar el servidor? ¿Dos servidores cargan el mismo perfil sin bloqueo?
- **"Se duplican compras":** ¿se registra el `PurchaseId` en la misma escritura que el beneficio? ¿Se devuelve `PurchaseGranted` antes de que el guardado termine? ¿Hay más de un `ProcessReceipt`?
- **"El perfil crece sin parar":** ¿algún mapa o lista no tiene límite? ¿Se guarda un historial que nadie lee?

Escribe lo que encuentres en `DATA.md` y deja los arreglos de código como pedidos al builder.

## Entrega

Resume: persistencia, secciones con su dueño, promesas cubiertas, versión y migraciones, tamaño estimado, resultado de `check_data.py`, pedidos abiertos (al designer, al builder) y qué falta probar en Studio y en una experiencia publicada.

Ejemplo completo, un RPG de misiones con facciones: [DataSchema.json](assets/example/DataSchema.json) y [DATA.md](assets/example/DATA.md).
