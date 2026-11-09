---
name: roblox-analytics-dev
description: Instrumentar y medir juegos de Roblox con AnalyticsService. Convierte los KPIs, el funnel de onboarding, la progresión y la economía del GDD en una taxonomía de eventos (design/ANALYTICS.md), un esquema validado (AnalyticsSchema.json) y el módulo Analytics que recibe los eventos de Telemetry, dentro de los límites de Roblox. Úsalo cuando el GDD active analytics.enabled, cuando el usuario quiera medir retención, funnels, economía o eventos propios de su juego, o cuando no aparezcan datos en Creator Analytics. No define los KPIs (eso es de roblox-game-designer) ni escribe la lógica del juego (roblox-game-builder).
metadata:
  version: "1.0.1"
  last_verified: "2026-10-09"
---

# Roblox Analytics Dev

Hace que el juego mida lo que el GDD dice que importa. Los KPIs los decide el game designer y los momentos del juego los emite el builder con `Telemetry`; este skill define qué se registra, con qué nombres y dentro de qué límites, y conecta esos eventos con `AnalyticsService`.

Medir mal es peor que no medir: nombres que cambian entre versiones, eventos que superan los límites o datos enviados desde el cliente producen gráficos que parecen ciertos y llevan a decisiones equivocadas.

## Qué produces y qué no

- Lees del `GDD.md`: KPIs objetivo, funnel de onboarding, caminos de progresión, monedas y monetización seleccionada. Del código, las llamadas a `Telemetry` que ya emite el juego.
- Escribes, según el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md):
  - `design/ANALYTICS.md`, con la [plantilla](references/analytics-template.md);
  - `src/server/AnalyticsSchema.json`, el esquema de nombres (Rojo lo convierte en ModuleScript);
  - `src/server/Analytics.luau`, copiado sin cambios de la [plantilla](assets/templates/src/server/Analytics.luau).
- No defines KPIs: si falta uno o no se puede medir, propón el cambio al game designer con la regla de pendientes del contrato. No escribes lógica del juego: si falta una llamada a `Telemetry`, es un pedido al builder.
- Activa `analytics.enabled: true` en el frontmatter si el usuario pidió medir y no estaba, como permite la excepción del contrato.

## Reglas de la plataforma

Verificadas el 9 de octubre de 2026 en la [documentación de Roblox](https://create.roblox.com/docs/production/analytics/event-types). Los detalles están en [reglas de AnalyticsService](references/platform-rules.md).

- Los eventos solo se registran **desde el servidor** y **en experiencias publicadas**. En Studio no se envía nada.
- Límite global: **120 + 20 × CCU** solicitudes por minuto entre todos los servidores. La plantilla limita cada servidor a 20 por jugador y minuto, así la suma no lo supera.
- Hasta 10 monedas, 10 funnels, 100 nombres de eventos propios y 3 campos propios (8.000 combinaciones de valores; el resto se agrupa como "Other").
- Los gráficos tardan hasta 24 horas; la herramienta View Events muestra los eventos casi en tiempo real.

**Varios places.** Todos los places de la experiencia envían a las mismas analíticas. `Travel` emite `travel` y `travel_failed` (con el destino en el campo `to`): declara esos eventos en el esquema si el juego tiene varios places, y nombra los pasos de un funnel que cruza places igual en todos.

## 1. Mapear KPIs a eventos

Para cada KPI del GDD, decide qué eventos lo alimentan. Prefiere los tipos nativos antes que eventos propios, porque Creator Analytics ya sabe mostrarlos:

| Qué mides | Función de `Telemetry` | Evento de Roblox |
| --- | --- | --- |
| Primeros pasos de un jugador nuevo | `onboarding` | Funnel de onboarding (una vez por usuario) |
| Embudos que se repiten (tienda, tutorial opcional) | `funnel` | Funnel con sesión |
| Niveles, oleadas, rondas | `progressionStart` / `Complete` / `Fail` | Progresión |
| Moneda ganada o gastada | `economy` | Economía (fuente o sumidero) |
| Lo que no encaja en lo anterior | `custom` | Evento propio con valor numérico |

- Los nombres salen del GDD y no cambian entre versiones. Si un nombre no está en el GDD, agrégalo al pedido de pendientes para el game designer.
- Eventos propios en `snake_case`, pocos y estables. Para comparar segmentos, usa **campos propios** en lugar de multiplicar nombres de eventos: hay 100 nombres, pero 8.000 combinaciones de campos.
- Los valores de los campos son categorías de baja cardinalidad (nivel, mapa, skin). Nunca identificadores de jugador, nombres de usuario, texto libre ni marcas de tiempo.

## 2. Escribir el esquema y el documento

- `AnalyticsSchema.json` declara `progressionPaths`, `funnels`, `currencies`, `customEvents` y `customFields` (ranura `CustomField01` a `CustomField03` → dimensión). El módulo `Analytics` descarta, con un aviso, cualquier nombre que no esté declarado: así un error de tipeo no crea un evento nuevo ni consume un cupo.
- `budgetPerPlayerPerMinute` queda en 20 salvo que el juego necesite reservar margen.
- `ANALYTICS.md` explica cada KPI (eventos, fórmula y panel), cada evento (cuándo lo emite el servidor, valor y campos), el presupuesto estimado por jugador y minuto, cómo verificar y qué no se mide por privacidad.

Ejemplo aplicado al obby de ejemplo del builder: [esquema](assets/example/AnalyticsSchema.json) y [documento](assets/example/ANALYTICS.md).

## 3. Conectar

1. Copia `Analytics.luau` sin cambios a `src/server/`. `Telemetry` lo detecta solo y le reenvía cada evento válido.
2. Compara las llamadas a `Telemetry` del código con la taxonomía. Si faltan momentos (un paso de onboarding, el final de una oleada, un gasto de moneda), pídeselos al builder con la regla de pendientes; si el builder está instalado y el usuario pidió instrumentar el juego, agrégalos con sus reglas.
3. Los eventos de compras los emite el servicio de recibos del módulo de monetización (`economy` de tipo `IAP`), después de una entrega durable.

## 4. Verificar

```bash
python <skill-dir>/scripts/check_analytics.py <Juego>
```

En Windows, usa `python` o `py -3` si `python3` no existe. Revisa el esquema contra los límites de Roblox, la API de `Analytics.luau`, que cada nombre literal usado con `Telemetry` esté declarado y que `ANALYTICS.md` documente cada nombre. `check_game.py` del builder lo ejecuta también cuando el GDD activa `analytics.enabled`. Corrige todos los ERROR.

Después:

- **Studio:** con el atributo booleano `Debug` en `true` en los ModuleScripts `Telemetry` y `Analytics`, el Output muestra cada evento que se enviaría. Recorre el loop y comprueba que aparecen en el orden esperado y sin duplicados.
- **Experiencia publicada de prueba:** la herramienta View Events de Creator Analytics confirma que llegan. Publicar es una acción del usuario: pídele que lo haga y no publiques por tu cuenta.
- No afirmes que los datos "ya se ven" en los paneles: tardan hasta 24 horas.

## Diagnóstico: "no aparecen datos"

Revisa en orden: ¿la experiencia está publicada y se probó fuera de Studio? ¿Los eventos se envían desde el servidor? ¿Pasaron 24 horas? ¿El nombre está en el esquema o el Output muestra "se descarta"? ¿Se superó el límite de nombres o de frecuencia? ¿Hay errores de `pcall` en el Output del servidor?

## Frontera con Creator Rewards

Si el juego tiene `creator-rewards`, ese módulo define qué métricas del programa conviene seguir y las pide como pendientes; este skill las convierte en eventos. Las recompensas reales se consultan en el panel de Creator Rewards, nunca se calculan con eventos del juego.

## Entrega

Resume en pocas líneas: KPIs cubiertos, eventos nuevos, pedidos abiertos al builder o al designer, resultado de `check_analytics.py` y qué falta verificar (Studio con `Debug`, experiencia publicada y 24 horas para los paneles).
