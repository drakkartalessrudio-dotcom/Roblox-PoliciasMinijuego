# LiveOps de ObbyEjemplo

Fuente: `GDD.md` (Parámetros ajustables). Esquema: `src/server/LiveSchema.json`. Módulo: `src/shared/LiveConfig.luau` (plantilla sin cambios). Reglas de ConfigService verificadas el 2026-10-09.

## Claves en vivo

Se cambian en Creator Hub → Configs, sin publicar una versión nueva. Tienen prioridad sobre los eventos programados.

| Ruta de Config | Config en Creator Hub | Valor por defecto | Rango | Para qué |
| --- | --- | --- | --- | --- |
| `Respawn.Time` | `respawn_time` | 1.5 | 0.5 a 10 | Acortar la espera si los jugadores se frustran |
| `Hazards.Damage` | `hazards_damage` | 100 | 1 a 100 | Bajar la letalidad de la lava en un evento suave |
| `Hud.HintText` | `hud_hint_text` | Mensaje inicial | — | Avisos y anuncios |

## Calendario (UTC)

| Evento | Inicio | Fin | Cambios | Qué medir |
| --- | --- | --- | --- | --- |
| `halloween_2026` | 2026-10-25 00:00 | 2026-11-02 00:00 | Mensaje inicial temático | Conversión del onboarding y progresión durante la ventana, frente a la semana anterior |

Las fechas viven en el esquema del servidor, así que mover un evento requiere publicar una versión. Para cortarlo antes, sobrescribe sus valores con la clave en vivo correspondiente.

## Runbook

**Activar un cambio en vivo**
1. Creator Hub → Configs: edita el valor de la clave y guarda (queda en preparación).
2. Pruébalo en Studio: los valores en preparación solo se ven en sesiones de Studio. Para un servidor en vivo, `ConfigService:SetTestingValue(clave, valor)` desde la consola del desarrollador lo cambia solo en ese servidor.
3. Publica con un mensaje que diga qué cambia y por qué. Llega a los servidores en unos 15 segundos a 1 minuto, y a los clientes en unos minutos.

**Revertir**
- Desde el historial de Configs, restaura la versión anterior y publica; o devuelve la clave a su valor por defecto. Un valor fuera de rango se recorta al rango del esquema, y uno de otro tipo se ignora con un aviso en el Output del servidor.

**Verificar**
- En el Output del servidor, `[LiveConfig]` avisa de valores ignorados o recortados.
- `LiveConfig.active()` en la consola del servidor muestra los overrides vigentes.
- Para los efectos en el juego, compara los KPIs de `ANALYTICS.md` antes y durante el cambio. Los paneles tardan hasta 24 horas.

## Fuera de alcance

Precios en Robux (los define Roblox), experimentos por jugador (`GetConfigForPlayerAsync`, posterior) y recompensas persistentes de eventos (requieren el servicio de datos del builder).
