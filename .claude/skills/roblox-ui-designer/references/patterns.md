# Patrones de interfaz

Puntos de partida para las pantallas más comunes. Adáptalos al loop del GDD.

## HUD

- Muestra solo lo que cambia una decisión en los próximos segundos: tiempo de ronda, vidas, objetivo actual, moneda si se gasta seguido.
- Una línea principal en `top` (por ejemplo "Ronda 3 · 0:42") con fuente `heading` o `number`; lo secundario en `right` y más chico.
- Cambios importantes con `Kit.toast`, no con texto que aparece y desaparece en el HUD.
- Nada en el centro: es donde el jugador mira el juego.

## Tienda

- Botón en `left` con atajo (B en teclado, Y en gamepad).
- Ventana con `Kit.modal`: categorías con `Kit.tabs`, artículos en `Kit.grid` con una `Kit.card` por artículo, y en cada una el beneficio exacto, el precio y el botón de compra.
- Estados de cada artículo: disponible, ya comprado ("Lo tienes"), sin saldo (con lo que falta), no disponible (ID pendiente o error del servicio), comprando.
- Una categoría sin artículos muestra `Kit.status(..., "empty", ...)` con un texto que explica qué va a haber, no una ventana vacía.
- El precio en Robux lo da el módulo de monetización con el valor que devuelve Roblox; el botón abre el prompt nativo. La UI nunca confirma una compra: espera el estado del servidor.
- Lo pagado no lleva colores de alarma ni urgencia falsa ("¡solo hoy!") si no es cierto.

## Menús y ventanas

- Una ventana a la vez; abrir otra cierra la anterior (`Kit.modal` lo hace solo).
- Siempre se puede salir: botón de cerrar visible, B en gamepad y el mismo atajo que la abrió. El botón vive en una cabecera fija, nunca al final del contenido: en un celular en horizontal la pantalla mide ~360 px de alto y la ventana no cabe. El contenido se desplaza dentro de la ventana, que nunca es más alta que la capa.
- Revisa cada ventana con el alto más bajo (celular horizontal, ~640 × 360 sin la barra superior de Roblox) y comprueba que el botón de cerrar se ve y se puede tocar.
- En gamepad el foco cae en el botón más probable al abrir.
- Los textos explican la consecuencia de la acción ("Reiniciar nivel: vuelves al checkpoint"), no solo su nombre.

## Fin de ronda y resultados

- Primero el resultado del jugador (ganó, puesto, recompensa), después el ranking.
- Tiempo visible hasta la siguiente ronda y un botón para salir al lobby si corresponde.
- La recompensa que muestra la UI es la que confirmó el servidor.

## Onboarding

- La primera instrucción coincide con el primer paso del funnel del GDD y se va sola cuando el jugador la cumple.
- Mensajes de uno en uno, cortos, con el control de la entrada actual (`Kit.Input.hint`).
- Quien vuelve no ve el tutorial completo.

## Viajes entre places

- Antes de viajar, una pantalla breve que diga a dónde va el jugador. Durante el viaje Roblox muestra su pantalla de carga; `TeleportService:SetTeleportGui` la reemplaza por una propia, pero sus scripts no corren: solo imagen y texto fijos.
- Si el viaje falla, el servidor pone en el jugador el atributo `TravelFailed` con el destino: un `Kit.toast` que diga que no se pudo y que puede volver a intentar. El jugador sigue jugando donde estaba.
- En Studio no hay viajes: la pantalla de viaje se prueba en la experiencia publicada.

## Notificaciones

- `Kit.toast` para logros, recompensas y avisos breves; nunca para información que el jugador necesita después (eso va en el HUD o en una ventana).
- Sin acumular: si llegan muchas seguidas, agrúpalas ("+3 monedas" en lugar de tres avisos).
