---
project:
  name: TorreNeon
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

# TorreNeon

## Concepto

Obby vertical en una torre de neón: el jugador sube saltando, trepa una escalera y usa un ascensor para llegar arriba, juntando cristales en el camino. Público general; sesiones de 3 minutos.

Pilares:

1. **Subir se siente bien:** cada tramo termina más alto que el anterior.
2. **Riesgo claro:** el vacío rosa mata y se ve siempre.
3. **Algo para buscar:** un cristal por nivel, en un lugar un poco fuera del camino.

## Loop principal

1. Aparece en la base y ve la meta arriba.
2. Salta, trepa y espera el ascensor eligiendo el momento.
3. Si cae al vacío, reaparece en el último checkpoint; si toca un cristal, lo suma.
4. Al tocar la meta pasa al siguiente nivel; tras el segundo, la torre queda completa.

Cada jugador avanza por su cuenta; entrar con otros ya en curso no cambia nada.

## Onboarding

Mensaje inicial: "Sube a la cima y junta cristales". Primer salto de 2,5 studs y el primer cristal a la vista.

Funnel: `1 joined`, `2 first_checkpoint`, `3 level_1_complete`.

## Progresión

Dos niveles: la base (saltos, escalera) y el ascensor (plataforma vertical con timing). Al terminar, el HUD lo celebra y muestra los cristales juntados.

## Contenido y alcance

MVP: 2 niveles, checkpoints, vacío mortal, ascensor, 2 cristales, leaderstats "Nivel" y "Cristales", HUD. Máximo 8 jugadores por servidor.

Posterior: guardar cristales, tienda de estelas con cristales, más niveles.

## Brief de niveles

| # | Objetivo | Mecánica nueva | Dificultad | Tiempo esperado |
| --- | --- | --- | --- | --- |
| 1 | Base de la torre | Subidas y escalera | 2 | 45 s |
| 2 | Ascensor de neón | Plataforma vertical con timing | 3 | 60 s |

Niveles completos en `design/LEVELS.md` y `src/shared/Levels.json` (validados, 0 errores y 0 advertencias).

## Física y métricas del personaje

walkSpeed 16, jumpHeight 7.2, gravity 196.2. Fuente única: `Levels.json`.

## Plataformas e interacción

PC: WASD y espacio. Móvil: controles táctiles de Roblox. HUD legible en pantallas chicas.

## Estado y economía

Moneda: **Cristales**, solo durante la sesión. Fuente: tocar un cristal (+1, cada cristal una vez por jugador). Sin sumideros en el MVP (la tienda es posterior). Nada se guarda entre sesiones.

## Parámetros ajustables

| Parámetro | Valor inicial | Uso |
| --- | --- | --- |
| `Hazards.Damage` | 100 | Daño del vacío; 100 mata al personaje por defecto |
| `Respawn.Time` | 1.5 | Segundos entre morir y reaparecer |
| `Hud.HintText` | "Sube a la cima y junta cristales" | Mensaje inicial |

## Monetización seleccionada

Ninguna.

## KPIs objetivo

| KPI | Definición | Objetivo inicial | Cómo se mide | Decisión si no se cumple |
| --- | --- | --- | --- | --- |
| Conversión del onboarding | Nuevos que llegan a `level_1_complete` / nuevos que entraron | Medir línea base | Funnel de onboarding | Simplificar la base |
| Progresión | Completan cada nivel / lo empiezan, camino `Torre` | Hipótesis: el ascensor es el pico | Eventos de progresión | Hacer el ascensor más lento |
| Cristales por sesión | Cristales juntados / jugadores | Medir línea base | Eventos de economía, moneda `Cristales` | Mover los cristales |

## Assets y servicios

Sin assets externos.

## Arquitectura

A completar por el builder.

## Suposiciones y criterios de aceptación

- Cada cristal suma una sola vez por jugador, aunque lo toque varias veces.
- El ascensor lleva al jugador hasta `alto` sin que se resbale.
- Al morir, el jugador reaparece en su último checkpoint.

## Pendientes entre skills

Ninguno.
