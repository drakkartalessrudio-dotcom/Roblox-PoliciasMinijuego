# Reglas de ConfigService (experience configs)

Verificado el 9 de octubre de 2026 en la documentación oficial: [Experience configs](https://create.roblox.com/docs/production/configs) y [ConfigService](https://create.roblox.com/docs/reference/engine/classes/ConfigService). Es una función reciente: vuelve a revisarla si pasaron meses.

## API que usa la plantilla

| Llamada | Qué hace |
| --- | --- |
| `ConfigService:GetConfigAsync()` | Devuelve un `ConfigSnapshot` con los valores vigentes. Cede (yield) y falla si los configs nunca se pudieron cargar: va dentro de `pcall`, con Config como respaldo |
| `snapshot:GetValue(clave)` | Valor de un config |
| `snapshot:Refresh()` | Aplica al snapshot los cambios publicados |
| `snapshot.UpdateAvailable` | Avisa que hay cambios publicados para refrescar |
| `snapshot:GetValueChangedSignal(clave)` | Avisa cuando cambia una clave concreta |
| `ConfigService:SetTestingValue(clave, valor)` / `ClearTestingValue(clave)` | Valor de prueba solo en el servidor actual |
| `ConfigService:GetConfigForPlayerAsync(player)` | Snapshot con los valores condicionales del jugador (experimentos y segmentación); fuera del alcance de la plantilla |

Solo los scripts del servidor pueden leer configs. Si la conexión se corta después de cargar, el snapshot conserva los últimos valores y reintenta.

## Publicación y propagación

- Los cambios nuevos quedan **en preparación** y solo se ven en sesiones de Studio.
- **Publicar ahora** llega a todos los servidores en unos 15 segundos a 1 minuto; hay una opción de despliegue gradual de 15 minutos. Los clientes pueden tardar unos minutos más.
- El historial permite ver y restaurar versiones anteriores. Publica con un mensaje que explique el cambio.

## Tipos y límites

- Tipos: texto, número, booleano y objeto JSON. La plantilla usa los tres primeros, porque las rutas de `Tuning` apuntan a valores literales de Config.
- Hasta 1.000 configs activos.
- Textos y JSON de hasta 100.000 caracteres; números de doble precisión (enteros exactos hasta ±2^53).
- Valores condicionales por país, idioma, jugador nuevo o recurrente y si compró antes: hasta 100 condiciones por juego y 20 por clave. Se evalúan de arriba abajo y gana la primera que coincide.

## Lo que ConfigService no hace

- No programa ventanas de tiempo: los eventos con calendario viven en `LiveSchema.json`.
- No entrega valores al cliente: `LiveConfig` publica los overrides activos en un atributo replicado.
- No reemplaza el guardado de datos: el progreso de un evento se guarda con el servicio de datos del juego.
