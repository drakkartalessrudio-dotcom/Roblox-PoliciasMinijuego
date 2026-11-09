---
project:
  name: TejadoRush
  mode: release-candidate
  places: 1
  platforms: [desktop, mobile]
monetization:
  enabled: [game-passes, developer-products]
---

# TejadoRush

## Concepto

Carrera infinita por los tejados de una ciudad: el jugador corre solo hacia adelante, salta entre edificios y junta monedas. Público de 9 a 14 años; sesiones de 5 a 10 minutos.

## Loop principal

1. El jugador aparece en la azotea inicial y ve el récord del servidor.
2. Corre (avance automático) y decide cuándo saltar y hacia qué carril moverse (3 carriles).
3. Junta monedas; si cae entre edificios termina la carrera.
4. Ve sus monedas y su distancia, y decide gastar monedas en la tienda o correr otra vez.

## Contenido y alcance

MVP: corredor con 3 carriles, generación procedural de tramos de tejados, monedas, tienda de 3 skins de estela pagadas con monedas, récord personal guardado, tabla de récords del servidor.
Posterior: misiones diarias, mascotas, eventos de temporada.

## Plataformas e interacción

PC: A/D o flechas para cambiar de carril, espacio para saltar. Móvil: deslizar a los lados y tocar para saltar. Botones de tienda grandes.

## Estado y economía

Se guardan: monedas, skins compradas, récord de distancia. Fuente: monedas en la carrera (1 por moneda). Sumidero: skins de 150, 400 y 1000 monedas.

## Monetización seleccionada

- **game-passes**: pase "VIP" con monedas x2 en la carrera. ID: pendiente (todavía no creado en Creator Hub).
- **developer-products**: "Revivir" (continuar una carrera una vez después de caer). ID: pendiente.

## Assets y servicios

Sin assets externos; todo con Parts. La experiencia no está publicada todavía.

## Arquitectura

A definir por el builder.

## Suposiciones y criterios de aceptación

- Un jugador nuevo entiende el control en los primeros 10 segundos.
- El récord y las monedas se conservan al salir y volver.
- Comprar VIP duplica las monedas de la carrera y lo indica en el HUD.
- Revivir continúa la misma carrera desde un tejado seguro.
