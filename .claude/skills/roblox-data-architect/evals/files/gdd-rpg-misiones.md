---
project:
  name: CronicasDelPuerto
  mode: release-candidate
  genre: rpg
  places: 1
  platforms: [desktop, mobile]
design:
  levels: false
  art: true
  ui: true
  data: true
monetization:
  enabled: [developer-products]
analytics:
  enabled: true
liveops:
  enabled: false
---

# Crónicas del Puerto

## Concepto

RPG de misiones en una ciudad portuaria. El jugador acepta encargos de dos gremios (Marineros y Mercaderes), consigue materiales, fabrica equipo y sube la reputación con cada gremio para abrir encargos mejores.

## Loop

Aceptar un encargo → ir a la zona → cumplir los objetivos (juntar, entregar, vencer) → volver y cobrar monedas y reputación → fabricar o mejorar equipo → aceptar un encargo más difícil.

## Onboarding

1. Hablar con la capitana (`talked_to_captain`).
2. Aceptar el primer encargo (`first_quest_accepted`).
3. Fabricar el primer objeto (`first_craft`).
4. Abrir el mapa del puerto (`map_opened`).

## Progresión

Unos 60 encargos al lanzar, que se agregarán en cada actualización. Cada gremio tiene 5 rangos de reputación. Los encargos diarios se repiten cada 24 horas.

## Estado y economía

Datos que se conservan entre sesiones:

- Monedas (`doubloons`) y perlas (`pearls`, se compran con Robux).
- Encargos completados, y los activos con el progreso de cada objetivo.
- Cuántas veces se completó cada encargo diario.
- Reputación con cada gremio.
- Materiales (apilables) y equipo fabricado (cada pieza con su nivel de mejora), y qué está equipado.
- Racha de recompensa diaria.
- Lo comprado con Robux.

Datos temporales: la posición, la zona actual, el combate en curso.

Si una carga falla, el jugador no puede cobrar ni comprar hasta que se recupere.

## Monetización seleccionada

| Producto | Beneficio |
| --- | --- |
| Bolsa de perlas (pendiente) | 100 perlas |
| Cofre del capitán (pendiente) | Un equipo raro al azar, con probabilidades publicadas |

## KPIs objetivo

| KPI | Objetivo |
| --- | --- |
| Conversión del onboarding | Medir línea base |
| Retención D1 | Medir línea base |

## Pendientes entre skills

Ninguno.
