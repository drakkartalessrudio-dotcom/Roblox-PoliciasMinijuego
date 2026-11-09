---
project:
  name: MonedaMania
  mode: prototype
  genre: rounds
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

# MonedaMania

## Concepto

Rondas de 60 segundos en una arena donde aparecen monedas; gana quien junte más. Pilares: rondas cortas, reglas visibles, divertido desde 2 jugadores.

## Loop principal

Lobby de 15 segundos, ronda de 60 segundos en la arena, 5 segundos de resultados, vuelta al lobby. Quien entra a mitad de ronda espera en el lobby.

## Contenido y alcance

Máximo 8 jugadores por servidor. MVP: un lobby y una arena. Las monedas aparecen al azar dentro del área de monedas de la arena.

## Brief de niveles

| # | Objetivo | Mecánica | Dificultad | Tiempo esperado |
| --- | --- | --- | --- | --- |
| 1 | Lobby | Esperar y ver el marcador | 1 | 15 s |
| 2 | Arena | Correr por monedas con algunos desniveles y dos rampas | 2 | 60 s |

La arena debe poder cruzarse en menos de 8 segundos. Sin peligros que maten: perder tiempo es castigo suficiente.

## Física y métricas del personaje

walkSpeed 16, jumpHeight 7.2, gravity 196.2.
