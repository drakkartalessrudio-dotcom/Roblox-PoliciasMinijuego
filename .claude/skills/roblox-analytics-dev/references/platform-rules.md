# Reglas de AnalyticsService

Verificado el 9 de octubre de 2026 en la documentación oficial: [AnalyticsService](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService), [tipos y límites de eventos](https://create.roblox.com/docs/production/analytics/event-types), [economía](https://create.roblox.com/docs/production/analytics/economy-events), [funnels](https://create.roblox.com/docs/production/analytics/funnel-events) y [campos propios](https://create.roblox.com/docs/production/analytics/custom-fields). Vuelve a revisarlo si pasaron meses.

## Funciones que usa la plantilla

| Función de `Telemetry` | Método de AnalyticsService |
| --- | --- |
| `onboarding(player, paso, nombre)` | `LogOnboardingFunnelStepEvent(player, step, stepName)` |
| `funnel(player, funnel, paso, nombre, sesión?)` | `LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName)` |
| `progressionStart / Complete / Fail(player, camino, nivel, nombre?)` | `LogProgressionStartEvent` / `LogProgressionCompleteEvent` / `LogProgressionFailEvent(player, path, level, levelName)` |
| `economy(player, "source" o "sink", moneda, cantidad, saldo, tipo, sku?)` | `LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source o Sink, currency, amount, endingBalance, transactionType, itemSku)` |
| `custom(player, nombre, valor?, campos?)` | `LogCustomEvent(player, eventName, value, customFields)` |

Los métodos `Fire*` (`FireEvent`, `FireCustomEvent`, `FireInGameEconomyEvent`, `FirePlayerProgressionEvent`, `FireLogEvent`) están obsoletos; no los uses.

## Dónde funcionan

Solo desde el servidor y en experiencias publicadas. En Studio no se registra nada: usa el atributo `Debug` para ver en el Output lo que se enviaría.

## Límites

| Límite | Máximo |
| --- | --- |
| Solicitudes a AnalyticsService | 120 + 20 × CCU por minuto, entre todos los servidores |
| Monedas (economía) | 10 |
| Tipos de transacción | Sin límite; después de 20, el resto se agrupa como "Other" |
| SKUs | Sin límite; después de 100, el resto se agrupa como "Other" |
| Funnels | 10, con hasta 100 pasos cada uno |
| Nombres de eventos propios | 100 |
| Campos propios por evento | 3 (`CustomField01` a `CustomField03`); después de 8.000 combinaciones de valores, el resto se agrupa como "Other" |

Los límites se calculan por día: dejar de enviar un evento libera su cupo al día siguiente. Cada evento deja de verse 90 días después del último dato recibido.

## Detalles que cambian resultados

- **Onboarding:** ocurre una vez por usuario; Roblox maneja desconexiones y reconexiones. Un paso repetido se registra, pero solo cuenta el primero, y sí consume el límite de frecuencia. Si se salta un paso, los anteriores se dan por completados.
- **Funnels con sesión:** se siguen las 10 sesiones más recientes por usuario y funnel. Para una tienda, usa un identificador nuevo por visita (por ejemplo `HttpService:GenerateGUID(false)`).
- **Economía:** la cantidad es siempre positiva; los sumideros se muestran negativos en los gráficos. Regístrala después de aplicar el cambio, no al intentarlo. Tipos recomendados: `IAP`, `TimedReward`, `Onboarding`, `Shop`, `Gameplay` y `ContextualPurchase`.
- **Campos propios:** las claves son `Enum.AnalyticsCustomFieldKeys.CustomField01.Name` (`"CustomField01"`) a `CustomField03`; cualquier otra se ignora. Los valores son texto: convierte números y booleanos.
- **Demora:** los gráficos tardan hasta 24 horas; View Events muestra los eventos recientes casi en tiempo real.
