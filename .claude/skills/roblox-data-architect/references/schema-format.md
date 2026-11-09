# Formato de `DataSchema.json`

`src/server/Data/DataSchema.json` describe el documento que se guarda de cada jugador: qué secciones tiene, quién escribe cada una, qué tipo y qué límite tiene cada campo, y cómo pasar un perfil viejo a la versión actual. Rojo lo convierte en un ModuleScript: el servicio de datos lo lee en ejecución y `check_data.py` lo valida sin abrir Studio. Va en `src/server/` porque el cliente no lo necesita: lo que la UI muestra lo publica el servidor.

## Documento

```json
{
  "schemaVersion": 1,
  "document": {
    "store": "PlayerData",
    "key": "player_{UserId}",
    "persistence": "persistent",
    "budget": 1000000
  },
  "version": 2,
  "sections": {},
  "migrations": [],
  "history": {}
}
```

| Campo | Qué es |
| --- | --- |
| `schemaVersion` | Versión de este formato. Siempre `1`. |
| `document.store` | Nombre del DataStore, hasta 50 caracteres. |
| `document.key` | Patrón de la clave. Lleva `{UserId}` escrito exactamente así: es el que aceptan las plantillas de borrado de datos de Roblox. Con un UserId de 19 dígitos no puede pasar de 50 caracteres. |
| `document.persistence` | `persistent` (DataStore) o `memory` (se pierde al salir; prototipos y Studio sin acceso a la API). La API del servicio de datos es la misma en los dos. |
| `document.budget` | Tamaño máximo recomendado del documento, en caracteres de JSON. Por defecto 1.000.000. El límite de Roblox es 4.194.304 por clave. |
| `document.legacy` | `true` para adoptar perfiles guardados antes de `PlayerData` (ver [Adoptar perfiles existentes](#adoptar-perfiles-existentes)). Sin él, un perfil con otro formato no se carga ni se pisa. |
| `version` | Versión de los datos. Sube en 1 cada vez que un campo se mueve, se renombra, se borra o cambia de tipo. Agregar un campo o una sección no la sube: al cargar, el servicio completa lo que falte con los valores por defecto. |
| `sections` | Las secciones actuales. |
| `migrations` | Cómo pasar de cada versión a la siguiente. |
| `history` | La forma de cada versión anterior (`"1": { "sections": … }`), para simular las migraciones. |

## Secciones

Una sección es la parte del perfil que pertenece a un módulo. Solo su dueño la escribe; los demás usan la API de ese módulo.

```json
"quests": {
  "owner": "Quests",
  "description": "Misiones activas y completadas",
  "fields": {
    "active": {
      "type": "map", "key": "questId", "maxEntries": 10,
      "value": {
        "type": "record",
        "fields": {
          "startedAt": { "type": "time" },
          "objectives": { "type": "map", "key": "objectiveId", "maxEntries": 8, "value": { "type": "integer", "min": 0 } }
        }
      }
    },
    "completed": { "type": "map", "key": "questId", "maxEntries": 500, "value": { "type": "time" } }
  }
}
```

| Campo | Qué es |
| --- | --- |
| `owner` | El core dueño, tal como figura en el Mapa de módulos. `PlayerData` (el servicio de datos) solo es dueño de la sección con rol `meta`. |
| `role` | Opcional: `meta` (fechas, sesiones y tiempo de juego que mantiene el servicio de datos), `purchases` (recibos procesados de Developer Products) o `entitlements` (derechos pagados que duran). |
| `description` | Qué guarda, en una línea. |
| `fields` | Los campos, con nombres en camelCase. |

## Tipos

| `type` | Atributos | Por defecto | Notas |
| --- | --- | --- | --- |
| `boolean` | — | `false` | Para un paso de onboarding usa un mapa de banderas, no un booleano por paso |
| `integer` | `min`, `max` | `0`, o `min` si es mayor | Monedas, contadores, niveles |
| `number` | `min`, `max` | `0`, o `min` si es mayor | Solo si hacen falta decimales |
| `string` | `maxLength` (obligatorio) | `""` | Nunca texto escrito por el jugador sin filtrar |
| `enum` | `values` (lista de textos) | el primero | Estados con nombre: `"locked"`, `"open"`, `"done"` |
| `time` | — | `0` (nunca) | Segundos UTC desde 1970, con la hora del servidor |
| `map` | `key` (nombre del ID), `maxEntries` (obligatorio), `value`, `keyMaxLength` (32 por defecto) | `{}` | La forma normal de guardar contenido: por ID estable, nunca por posición |
| `list` | `items`, `maxItems` (obligatorio), `ordered: true` y `why` | `[]` | Solo cuando el orden importa (un historial reciente); si no, usa un mapa |
| `record` | `fields` | sus campos por defecto | Un grupo fijo de campos |

Cualquier campo acepta `default` (validado contra su tipo) y `description`.

Los límites (`maxEntries`, `maxItems`, `maxLength`) no son decoración: con ellos `check_data.py` calcula el tamaño del documento en el peor caso, y el servicio de datos rechaza una escritura que los supere.

## Migraciones

Cuando un campo se mueve, se renombra, se borra o cambia de tipo, la versión sube en 1 y se agrega una migración. Antes de editar, copia las secciones actuales a `history["<versión anterior>"]`.

```json
"migrations": [
  {
    "from": 1, "to": 2,
    "description": "Las monedas pasan a un mapa por moneda; quests.done se llama completed",
    "ops": [
      { "op": "move", "from": "economy.coins", "to": "economy.wallet.coins" },
      { "op": "move", "from": "quests.done", "to": "quests.completed" },
      { "op": "add", "path": "onboarding.flags", "value": {} },
      { "op": "remove", "path": "onboarding.legacyTutorial" }
    ]
  }
]
```

| `op` | Efecto |
| --- | --- |
| `move` | Mueve el valor de `from` a `to` (renombrar es mover) |
| `add` | Pone `value` en `path` si no existe |
| `set` | Pone `value` en `path` aunque exista |
| `remove` | Borra `path` |
| `custom` | Llama a la función `name` de `Migrations.luau`; `sections` dice qué secciones toca. Solo para lo que no se puede declarar, como convertir booleanos en fechas |

Las rutas empiezan por la sección y usan `.` entre campos. `*` recorre todas las claves de un mapa: `quests.active.*.started` → `quests.active.*.startedAt` renombra el campo en cada misión activa. En un `move`, `from` y `to` llevan la misma cantidad de `*`.

Reglas:

- Una migración por versión, de 1 hasta `version`, sin huecos.
- Todo campo que deja de existir se mueve o se borra con una operación. El servicio de datos descarta al guardar lo que el esquema no conoce, así que un campo olvidado es un dato perdido.
- Los campos nuevos no necesitan `add`: al cargar, el servicio completa lo que falte con los valores por defecto. `add` sirve para poner un valor distinto al de defecto a los perfiles viejos.
- Nunca se reutiliza un ID ni un nombre de campo con otro significado.

`check_data.py` toma la forma de cada versión de `history`, arma un perfil de ejemplo (con una entrada en cada mapa), le aplica las migraciones hasta la versión actual y comprueba que el resultado respete el esquema: que no queden campos sin migrar y que cada valor tenga el tipo nuevo. Las operaciones `custom` no se simulan: se prueban con el servicio de datos.

## Adoptar perfiles existentes

Un juego que ya guarda datos con su propio código tiene perfiles con otra forma (por ejemplo `{ "coins": 10, "pickaxe": "iron" }`, sin `version` ni `sections`). `PlayerData` nunca carga ni guarda encima de un valor que no reconoce: lo deja intacto y el perfil queda `unavailable`. Para adoptarlos:

1. Usa el mismo DataStore (`document.store`) y el mismo patrón de clave (`document.key`) que el juego, para encontrar los perfiles guardados. Si el patrón no tiene el UserId en un formato que acepte `{UserId}`, explica en `DATA.md` cómo se migrarían las claves; no lo cambies sin ese plan.
2. Pon `document.legacy: true`. Un perfil viejo entra como versión 0, con todo su contenido en una sección llamada `legacy`.
3. Describe la forma vieja en `history["0"]` con esa sección `legacy` (no necesita dueño).
4. Escribe la migración de 0 a 1 que mueve cada campo de `legacy` a su sección nueva y borra lo que se descarta. `check_data.py` avisa por cada campo que quedaría sin migrar.

```json
"document": { "store": "Minas", "key": "Player_{UserId}", "persistence": "persistent", "legacy": true },
"migrations": [
  { "from": 0, "to": 1, "ops": [
    { "op": "move", "from": "legacy.coins", "to": "economy.wallet.coins" },
    { "op": "move", "from": "legacy.pickaxe", "to": "tools.equipped.pickaxe" }
  ] }
],
"history": { "0": { "sections": { "legacy": { "fields": {
  "coins": { "type": "integer", "min": 0 },
  "pickaxe": { "type": "string", "maxLength": 24 }
} } } } }
```

## Secciones de la librería

Un módulo de la librería guarda su sección en `data/section.json`:

```json
{
  "section": "rewards",
  "definition": { "owner": "Rewards", "description": "…", "fields": { "daily": { "type": "record", "fields": { … } } } },
  "migrations": [
    {
      "version": "2.0.0",
      "description": "streak se llama count",
      "ops": [{ "op": "move", "from": "rewards.daily.streak", "to": "rewards.daily.count" }]
    }
  ]
}
```

- `definition` tiene el formato de una sección de `DataSchema.json`, con el módulo como dueño.
- Cada migración lleva la `version` del **módulo** que cambió la forma, no la del esquema de un juego: cada juego tiene su propia numeración.
- Las rutas empiezan por la sección. Solo `move`, `add`, `set` y `remove`: `custom` necesita `Migrations.luau`, que es del juego.
- `library_section.py` convierte las migraciones posteriores a la versión que tenía el juego en una versión nueva de su esquema.

## Tamaño

`check_data.py` calcula el JSON más grande posible: cada mapa lleno hasta `maxEntries` con claves de `keyMaxLength`, cada texto en su `maxLength` y cada número con su máximo. Da error si pasa de 4.194.304 caracteres (el límite por clave de Roblox, medido con `JSONEncode`) y aviso si pasa de `budget`. El almacenamiento total de la experiencia es 500 MB más 1 MB por usuario histórico, medido comprimido: un perfil típico debería quedar muy por debajo del presupuesto.

Límites verificados el 14 de octubre de 2026 en la [documentación de Roblox](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).
