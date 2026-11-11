# Rojo: comandos más usados

Proyecto: `TravesurasBrainrot` (archivo `default.project.json`).

## Flujo diario (sincronizar con Studio)

1. En la terminal, dentro de la carpeta del proyecto:
   ```powershell
   rojo serve
   ```
   Queda escuchando en `localhost:34872`.
2. En Roblox Studio: pestaña **Plugins → Rojo → Connect** (host `localhost`, puerto `34872`).
3. Edita los archivos en `src/`; los cambios se reflejan en Studio en vivo.
4. Para parar el servidor: `Ctrl + C` en la terminal.

> Rojo sincroniza **scripts y propiedades declaradas** en el proyecto. Lo que construyes a mano en Studio (mapa, modelos) no se guarda en los archivos; guarda el lugar (`.rbxl`) o súbelo/publícalo desde Studio.

## Comandos principales

| Comando | Para qué sirve |
|---|---|
| `rojo --version` | Ver la versión instalada (también verifica que está en el PATH). |
| `rojo --help` | Lista de comandos. |
| `rojo serve` | Inicia el servidor de sincronización en vivo con `default.project.json`. |
| `rojo serve otro.project.json` | Sirve otro archivo de proyecto (útil con varios places). |
| `rojo serve --port 34873` | Usa otro puerto (si el 34872 está ocupado o corres dos proyectos). |
| `rojo build -o Juego.rbxl` | Genera un place completo (`.rbxl`) desde el proyecto. |
| `rojo build -o Juego.rbxlx` | Igual, pero en formato XML (legible, útil para git/diff). |
| `rojo build -o Modelo.rbxm` | Genera un modelo (`.rbxm`) en vez de un place. |
| `rojo build --watch -o Juego.rbxl` | Reconstruye el archivo cada vez que cambias algo. |
| `rojo init` | Crea un proyecto nuevo con la estructura base. |
| `rojo init --kind place` / `--kind model` | Elige el tipo de proyecto al crearlo. |
| `rojo upload Juego.project.json --asset_id <ID> --cookie "<cookie>"` | Sube el proyecto a Roblox (en versiones nuevas se usa `--api_key`). |
| `rojo fmt-project` | Da formato a un archivo `.project.json`. |
| `rojo sourcemap default.project.json -o sourcemap.json` | Genera el sourcemap (lo usan luau-lsp y otras herramientas). |
| `rojo sourcemap --watch default.project.json -o sourcemap.json` | Regenera el sourcemap automáticamente al cambiar archivos. |
| `rojo plugin install` | Instala el plugin de Rojo en Studio (alternativa a instalarlo desde la Toolbox). |

## Instalación

Con **Rokit** (recomendado) o **Aftman**:

```powershell
rokit add rojo-rbx/rojo
rokit install
```

Alternativas: `cargo install rojo`, o la extensión **Rojo** de VS Code (incluye botones de Start/Stop y el plugin).

## Problemas comunes

- **`rojo` no se reconoce como comando**: reabre la terminal o revisa que el PATH incluya la carpeta de Rokit/Aftman.
- **Studio no conecta**: confirma que `rojo serve` sigue corriendo y que el puerto coincide; en Studio activa *Game Settings → Security → Allow HTTP Requests* si hace falta.
- **Versión del plugin distinta a la del CLI**: actualiza ambos (`rokit update rojo` y `rojo plugin install`).
- **Cambios que no aparecen**: revisa que el archivo esté dentro de una ruta declarada en `$path` (`src/shared`, `src/server`, `src/client`).
- **Place nuevo vacío en Studio**: abre un baseplate vacío antes de conectar; Rojo agrega lo suyo encima.

## Mapa de este proyecto

| Carpeta | Destino en Studio |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |

Además, el proyecto fija `Lighting` (estilo Soft) y `Workspace` (StreamingEnabled activo).

## Convenciones de nombres de archivo

- `Nombre.server.luau` → Script (servidor)
- `Nombre.client.luau` → LocalScript
- `Nombre.luau` → ModuleScript
- `init.luau` dentro de una carpeta → la carpeta se convierte en ese script
- `Nombre.json` → ModuleScript que devuelve la tabla JSON
