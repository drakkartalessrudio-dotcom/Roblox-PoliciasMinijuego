# Plantilla de `design/LIVEOPS.md`

Copia esta estructura en `<Juego>/design/LIVEOPS.md`. Ejemplo completo: [LIVEOPS.md del obby](../assets/example/LIVEOPS.md). Escríbelo para alguien que opera el juego sin leer código.

```markdown
# LiveOps de <Juego>

Fuente: `GDD.md` (Parámetros ajustables). Esquema: `src/server/LiveSchema.json`. Módulo: `src/shared/LiveConfig.luau` (plantilla sin cambios). Reglas de ConfigService verificadas el <fecha>.

## Claves en vivo

| Ruta de Config | Config en Creator Hub | Valor por defecto | Rango | Para qué |
| --- | --- | --- | --- | --- |

## Feature flags

| Flag (`Features.…`) | Config | Qué enciende | Riesgo si se enciende antes de tiempo |
| --- | --- | --- | --- |

## Calendario (UTC)

| Evento | Inicio | Fin | Cambios | Qué medir |
| --- | --- | --- | --- | --- |

## Runbook

**Activar un cambio en vivo**
<pasos en Creator Hub, prueba en Studio o con SetTestingValue, publicación y demora>

**Revertir**
<historial de Configs o valor por defecto; qué pasa con un valor inválido>

**Verificar**
<Output del servidor, LiveConfig.active(), KPIs de ANALYTICS.md>

**Si algo se rompe**
<a quién avisar y qué flag apaga la función afectada>

## Configs que hay que crear en Creator Hub

<lista de claves con tipo y valor por defecto>

## Pendientes

<pedidos al game designer, al builder o a analíticas con el formato del GDD>
```
