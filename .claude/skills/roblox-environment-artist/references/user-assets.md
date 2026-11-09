# Referencias y assets del usuario

El pase de arte se hace con Parts, terreno y luces, y llega mucho más lejos con lo que aporta el usuario: imágenes de referencia para el estilo y assets para usar directamente (modelos 3D, variantes de material, texturas, sonidos y animaciones). Esta guía explica dónde se ponen, cómo se preparan, qué permite Roblox con cada uno y qué hace el skill. Verificado el 13 de octubre de 2026.

## Dónde van

```text
<Juego>/
└── assets/
    ├── reference/   → imágenes de referencia (png, jpg, webp): capturas de juegos o lugares que te gustan
    ├── models/      → modelos 3D listos para usar, uno por archivo (.rbxm o .rbxmx)
    ├── materials/   → variantes de material hechas en Studio, una por archivo (.rbxm)
    └── ASSETS.md    → IDs de texturas, sonidos y animaciones, con su origen y licencia (texto libre)
```

Ninguna carpeta es obligatoria. También se pueden adjuntar imágenes o pasar IDs en el chat.

## Qué hace el skill

1. Al empezar revisa `assets/`. Si no hay nada y el usuario no dijo nada, pregunta una vez si tiene referencias o assets; si no, sigue con Parts.
2. Mira cada imagen de referencia y anota en `ENVIRONMENT.md` qué toma de ella: paleta, densidad, materiales, formas o luz. Toma el estilo, no copia diseños, logos ni personajes de otros juegos.
3. Declara cada asset en `Environment.json`, en `assets`, con `source` (de dónde salió) y `license` (con qué permiso se usa), y agrega su fila en la sección "Assets y servicios" del GDD. La licencia la confirma el usuario: el skill la registra, no la verifica.
4. Pide al builder que mapee las carpetas en `default.project.json`:

   ```json
   "ServerStorage": { "EnvironmentAssets": { "$path": "assets/models" } },
   "MaterialService": { "$path": "assets/materials" }
   ```

5. Nunca inventa un ID, ni busca, baja o inserta assets por su cuenta.

## Cómo se prepara cada tipo

### Modelos 3D

1. En Studio, inserta el modelo: de tu inventario, de la Creator Store (Toolbox) o importado desde un `.fbx`, `.obj` o `.gltf` con el importador 3D.
2. Déjalo como un solo `Model` con un nombre sin espacios. Si es un modelo animado, que tenga `PrimaryPart` y un `AnimationController` o `Humanoid`.
3. Clic derecho → **Save to File…** → guárdalo en `assets/models/<Nombre>.rbxm`. Rojo lo convierte en `ServerStorage.EnvironmentAssets.<Nombre>`.
4. Dile al agente de dónde salió y con qué licencia lo usas, y más o menos qué tamaño debería tener en el juego.

El loader clona el modelo, lo escala para que entre en la caja `size` del prop, lo coloca, le pone la colisión pedida (sin colisión por defecto) y **borra sus scripts**: los modelos de terceros pueden traer código, y un adorno no lo necesita.

### Variantes de material (superficies con textura y relieve)

1. En Studio, en el **Material Manager**, crea una variante sobre un material base y carga sus mapas de color, normal, rugosidad y metalicidad, o usa una de la Creator Store.
2. Guárdala con **Save to File…** en `assets/materials/<Nombre>.rbxm`. El nombre de la variante debe ser el del archivo (o declara `name`).
3. El agente la usa en pisos y muros con `materialVariant`.

Las imágenes de una variante no se pueden asignar desde un script: por eso se preparan en Studio.

### Texturas (imágenes que se repiten sobre una cara)

Sube la imagen en Creator Hub o elige una de la Creator Store, copia su ID (`rbxassetid://…`) y anótalo en `ASSETS.md` con su origen. El agente la aplica a caras de pisos o muros con `texture`, eligiendo cada cuántos studs se repite.

### Sonidos de ambiente

El ID de un audio tuyo o con permiso para tu experiencia. El agente lo pone en todo el nivel o en un punto con alcance (`sounds`).

### Animaciones

El ID de una animación subida por la **misma cuenta o grupo dueño de la experiencia**: según la experiencia de la comunidad de Roblox, una animación de otro dueño no se reproduce en el juego publicado, aunque se vea en Studio. El modelo animado necesita `PrimaryPart` y un `AnimationController` o `Humanoid`.

## Permisos

Un asset restringido solo se ve o se oye en el juego si la experiencia tiene permiso para usarlo; si no, Studio muestra un error en el Output y en el juego no aparece. El dueño del asset lo otorga en Creator Hub, en los permisos del asset o de la experiencia ([privacidad de assets](https://create.roblox.com/docs/projects/assets/privacy)). Un permiso dado a una experiencia no se puede revocar. Es una tarea del usuario: el agente solo la anota como pendiente.

## Qué comprueba `check_environment.py`

- Cada asset tiene `kind`, `source` y `license`; los modelos y variantes, un archivo que existe; las texturas, sonidos y animaciones, un ID con la forma `rbxassetid://123`.
- Cada ID está en la sección "Assets y servicios" del GDD, y ningún ID aparece fuera de `assets`.
- Los modelos se usan con una caja `size` y las carpetas están mapeadas en `default.project.json`.
- Deja una nota sobre permisos cuando hay texturas, sonidos o animaciones, y sobre la propiedad de las animaciones.

No puede comprobar que el modelo se vea bien ni que tenga el tamaño declarado: la vista previa lo dibuja como una caja lila del tamaño declarado, y la prueba es en Studio.
