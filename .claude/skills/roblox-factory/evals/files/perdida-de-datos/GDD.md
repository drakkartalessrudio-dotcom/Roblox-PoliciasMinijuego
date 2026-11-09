---
project:
  name: MinasDelValle
  mode: release-candidate
  genre: simulator
  places: 1
  platforms: [desktop, mobile]
design:
  levels: false
monetization:
  enabled: [developer-products]
analytics:
  enabled: false
liveops:
  enabled: false
---

# Minas del Valle

## Concepto

Simulador de minería: el jugador pica rocas, vende minerales por monedas y compra picos mejores.

## Loop principal

Picar → vender → comprar un pico mejor → picar rocas más duras.

## Onboarding

1. Entrar (`joined`).
2. Picar la primera roca (`first_mine`).
3. Vender por primera vez (`first_sell`).

## Progresión

Cinco picos: madera, piedra, hierro, oro y diamante.

## Estado y economía

- El jugador conserva sus monedas y su pico entre sesiones.
- Las monedas compradas con Robux no se pierden ni se entregan dos veces.

## Parámetros ajustables

| Parámetro | Valor inicial | Uso |
| --- | --- | --- |
| `Shop.CoinPack` | 500 | Monedas de la bolsa que se compra con Robux |

## Monetización seleccionada

| Producto | Beneficio |
| --- | --- |
| Bolsa de monedas (ID pendiente) | 500 monedas |

## KPIs objetivo

| KPI | Objetivo |
| --- | --- |
| Retención D1 | Medir línea base |

## Arquitectura

```text
src/server/  Bootstrap.server.luau, DataService.luau (perfiles), ShopService.luau (compras), Telemetry.luau
src/shared/  Config.luau, Tuning.luau
```

## Suposiciones y criterios de aceptación

- Salir y volver conserva las monedas y el pico.

## Pendientes entre skills

Ninguno.
