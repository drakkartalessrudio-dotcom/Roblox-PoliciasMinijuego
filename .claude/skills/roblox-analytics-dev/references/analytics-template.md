# Plantilla de `design/ANALYTICS.md`

Copia esta estructura en `<Juego>/design/ANALYTICS.md`. Ejemplo completo: [ANALYTICS.md del obby](../assets/example/ANALYTICS.md).

```markdown
# Analíticas de <Juego>

Fuente: `GDD.md` (KPIs objetivo, onboarding, progresión, economía). Esquema: `src/server/AnalyticsSchema.json`. Módulo: `src/server/Analytics.luau` (plantilla sin cambios). Reglas de Roblox verificadas el <fecha>.

## KPIs y eventos

| KPI del GDD | Eventos | Cómo se calcula | Dónde se ve |
| --- | --- | --- | --- |
| <KPI> | <tipo y nombres> | <fórmula con numerador y denominador> | <panel de Creator Analytics> |

## Eventos

| Nombre | Tipo | Cuándo lo emite el servidor | Valor | Campos |
| --- | --- | --- | --- | --- |
| <nombre> | Onboarding / Funnel / Progresión / Economía / Propio | <momento observable> | <qué significa el número> | <dimensiones> |

## Campos propios

| Ranura | Dimensión | Valores posibles |
| --- | --- | --- |
| CustomField01 | <dimensión> | <lista corta o rango agrupado> |

## Presupuesto

<Eventos estimados por jugador y minuto en el momento de más actividad, frente al límite de 20.>

## Verificación

<Studio con Debug, experiencia publicada con View Events, 24 horas para los paneles.>

## Privacidad

<Qué no se registra y por qué.>

## Pendientes

<Pedidos al game designer o al builder con el formato del GDD: origen → destino: pedido (estado).>
```
