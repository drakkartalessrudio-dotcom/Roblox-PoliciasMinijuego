---
name: roblox-liveops
description: Operar juegos de Roblox en vivo. Define qué valores de Config se pueden cambiar sin publicar (experience configs de ConfigService), feature flags, eventos con calendario en UTC y su runbook, y lo conecta con Tuning mediante el módulo LiveConfig y un esquema validado. Úsalo cuando el GDD active liveops.enabled o el usuario quiera eventos de temporada, ajustar el balance en vivo, apagar una función sin publicar o planificar un calendario de contenido. No diseña la economía (roblox-game-designer), no fija precios en Robux ni procesa compras (módulos de monetización) y no escribe la lógica del juego (roblox-game-builder).
metadata:
  version: "1.0.2"
  last_verified: "2026-10-09"
---

# Roblox LiveOps

Permite cambiar el juego mientras está publicado, sin que un cambio de balance o un evento de temporada obligue a publicar una versión nueva, y sin que el equipo improvise cuando algo sale mal. El juego ya lee sus ajustes con `Tuning.get`; este skill decide cuáles pueden cambiar en vivo, dentro de qué límites, cuándo y cómo se revierten.

Operar en vivo sin reglas es riesgoso: un valor mal escrito puede romper la economía de todos los servidores a la vez. Por eso cada clave tiene tipo y rango, cada cambio tiene un camino de vuelta y cada evento dice qué se mide.

## Qué produces y qué no

- Lees del `GDD.md`: "Parámetros ajustables", economía y monetización; de `design/ANALYTICS.md`, los eventos con que medir cada cambio.
- Escribes, según el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md):
  - `design/LIVEOPS.md`, con la [plantilla](references/liveops-template.md);
  - `src/server/LiveSchema.json`, claves en vivo y calendario (en el servidor, para no revelar eventos futuros);
  - `src/shared/LiveConfig.luau`, copiado sin cambios de la [plantilla](assets/templates/src/shared/LiveConfig.luau).
- No cambias la economía ni agregas parámetros: si un evento necesita uno nuevo en Config, pídeselo al game designer y al builder con la regla de pendientes.
- No tocas precios en Robux ni flujos de compra: una oferta temporal se habilita con un flag, pero cobro, precio vigente y entrega siguen el módulo de monetización.

## Requisitos

LiveOps tiene sentido si alguien va a operar el juego y el progreso que dan los eventos se puede guardar. `liveops.enabled: true` va con `project.mode: release-candidate` o con persistencia declarada en el GDD. Si no se cumple, dilo antes de seguir.

## Reglas de la plataforma

Verificadas el 9 de octubre de 2026 en la documentación de Roblox. Detalles en [reglas de ConfigService](references/platform-rules.md).

- Los experience configs se editan en Creator Hub → Configs (o en Studio, File → Open Configs) y **solo el servidor** los lee, con `ConfigService:GetConfigAsync()` y `snapshot:GetValue(clave)`.
- El snapshot no se actualiza solo: se refresca con `Refresh()`, por ejemplo al recibir `UpdateAvailable`. Al publicar, el cambio llega a los servidores en unos 15 segundos a 1 minuto, y a los clientes en unos minutos.
- Los valores en preparación solo se ven en sesiones de Studio; `SetTestingValue` cambia un valor en un solo servidor.
- No hay calendario: las ventanas de los eventos las pone este skill en `LiveSchema.json`.

**Varios places.** Las configs son de la experiencia: la documentación de Roblox las describe así y no aclara si un place puede tener valores propios. Si un ajuste debe ser distinto por place, usa claves separadas (por ejemplo `Arena.RoundTime` y `Vestibulo.EventBanner`).

## 1. Elegir las claves en vivo

Recorre "Parámetros ajustables" y elige solo los valores que tiene sentido cambiar sin publicar: multiplicadores, tiempos de ronda, dificultad, textos de anuncios, flags de funciones. Para cada uno define el nombre del config en Creator Hub, el rango seguro (si es numérico) y para qué se usaría.

- Las rutas apuntan a valores literales de `Config` (número, texto o booleano). `LiveConfig` ignora un valor de otro tipo y recorta los números al rango del esquema, con un aviso en el Output del servidor.
- **Feature flags:** booleanos en `Config.Features` (por ejemplo `Features.HalloweenShop = false`). El código los lee con `Tuning.get` y la función queda apagada por defecto. Si el flag no existe en Config, es un pedido al builder.
- Valores que el cliente no debe conocer no van acá: `LiveConfig` publica los overrides activos al cliente para que la UI coincida con el servidor.

## 2. Planificar eventos

Cada evento tiene id en `snake_case`, ventana `start` y `end` en UTC (`2026-10-25T00:00:00Z`) y los overrides que aplica.

- El contenido de un evento (zona, tienda, misión) se programa apagado detrás de un flag y el evento solo cambia el flag: así el código se publica antes y el evento no depende de una publicación el mismo día.
- Prioridad: un valor de Creator Hub gana sobre el evento, y el evento sobre `Config`. Eso permite cortar o corregir un evento en vivo.
- Recompensas que duran más que el evento se guardan con el servicio de datos del juego, en la sección del core que las da (con [roblox-data-architect](../roblox-data-architect/SKILL.md), una sección de `DataSchema.json`); LiveOps no crea DataStores propios.
- Sin urgencia engañosa: no anuncies como "última oportunidad" algo que vuelve, ni presiones con cuentas regresivas falsas.
- Define qué medir antes de empezar (eventos de `ANALYTICS.md` y la comparación con un periodo previo). Si falta un evento, pídeselo a roblox-analytics-dev.

## 3. Conectar

1. Copia `LiveConfig.luau` sin cambios a `src/shared/`. `Tuning` lo detecta solo y usa `getOverride` en cada lectura.
2. Escribe `LiveSchema.json` con `keys`, `events` y `refresh`. Con `"refresh": "immediate"` los cambios de Creator Hub se aplican al llegar; con `"manual"`, el juego llama a `LiveConfig.refresh()` en un momento seguro (por ejemplo entre rondas) para que nada cambie a mitad de partida.
3. El código del juego debe leer los ajustes al usarlos, no al iniciar. Si guarda un valor en una variable al arrancar, el cambio en vivo no se verá: pídele al builder que lo corrija.
4. Crea los configs en Creator Hub con los nombres del esquema y los valores por defecto de Config. Es una acción del usuario: indícale qué crear y no publiques por tu cuenta.

## 4. Verificar

```bash
python <skill-dir>/scripts/check_liveops.py <Juego>
```

En Windows, usa `python` o `py -3` si `python3` no existe. Comprueba que cada clave y override apunte a una ruta de Config con el tipo correcto y dentro del rango, las fechas UTC, los eventos superpuestos, el módulo y el runbook. `check_game.py` del builder lo ejecuta también cuando el GDD activa `liveops.enabled`. Corrige todos los ERROR.

Después, en Studio: valores en preparación de Creator Hub, o `ConfigService:SetTestingValue` desde la consola del servidor. Para probar un evento, una copia temporal del esquema con una ventana que incluya la hora actual. `LiveConfig.active()` en la consola del servidor muestra los overrides vigentes.

## 5. Runbook

`LIVEOPS.md` explica, para quien opere el juego sin leer código: cómo activar un cambio, cómo revertirlo (historial de Configs o volver al valor por defecto), cómo verificarlo (Output del servidor, `LiveConfig.active()`, KPIs) y a quién avisar si algo se rompe.

## Entrega

Resume en pocas líneas: claves en vivo con sus rangos, calendario, configs que el usuario debe crear en Creator Hub, pedidos abiertos al builder, al designer o a analíticas, resultado de `check_liveops.py` y qué falta probar en Studio y en la experiencia publicada.
