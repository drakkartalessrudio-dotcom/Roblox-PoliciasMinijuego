---
project:
  name: GlaciarObby
  mode: prototype
  genre: obby
  places: 1
  platforms: [desktop, mobile]
design:
  levels: true
monetization:
  enabled: []
analytics:
  enabled: false
liveops:
  enabled: false
---

# GlaciarObby

## Concepto

Obby en un glaciar: el jugador escala de cueva en cueva saltando sobre hielo. Pilares: saltos legibles, hielo que obliga a frenar antes de saltar, progreso visible.

## Loop principal

Saltar entre plataformas, llegar al checkpoint, pasar a la siguiente etapa. Si cae al agua helada, vuelve al último checkpoint.

## Onboarding

Primera etapa sin hielo resbaloso y con saltos cortos. Pasos del funnel: `joined`, `first_checkpoint`, `level_1_complete`.

## Brief de niveles

| # | Objetivo | Mecánica nueva | Dificultad | Tiempo esperado |
| --- | --- | --- | --- | --- |
| 1 | Aprender a saltar | Salto básico | 1 | 40 s |
| 2 | Primer hielo | Plataformas de hielo resbaloso (material Ice) | 2 | 50 s |
| 3 | Subir la grieta | Subidas y escalera (truss) | 3 | 60 s |
| 4 | Témpanos | Plataforma móvil sobre agua | 4 | 70 s |
| 5 | Cumbre | Combina hielo, subidas y plataforma móvil | 5 | 90 s |

Un checkpoint al inicio de cada etapa y otro a mitad de las etapas 4 y 5. Agua helada (peligro) debajo de todo el recorrido.

## Física y métricas del personaje

walkSpeed 18 (un poco más rápido que lo habitual, para compensar el hielo), jumpHeight 7.2, gravity 196.2.

## Contenido y alcance

MVP: 5 etapas, checkpoints, contador de etapa. Posterior: tabla de tiempos, skins.

## Suposiciones y criterios de aceptación

- La etapa 1 se completa sin morir en el primer intento la mayoría de las veces.
- Ningún salto requiere más del 80 % de la capacidad salvo en la etapa 5.
