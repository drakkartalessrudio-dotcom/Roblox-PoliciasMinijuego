---
name: roblox-monetization-game-passes
description: Diseñar e implementar ventajas permanentes de compra única con Game Passes de Roblox cuando el GDD selecciona pases, como VIP, espacios extra o multiplicadores permanentes. Verifica propiedad y aplica beneficios desde el servidor. También para preguntas o arreglos sobre Game Passes aunque no haya GDD.
metadata:
  version: "1.1.1"
  last_verified: "2026-10-07"
---

# Monetización con Game Passes

Entrega privilegios permanentes y verificables, incluyendo compras previas o realizadas fuera de la sesión actual.

## Integración y alcance

- Sigue el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md). El skill [roblox-game-designer](../roblox-game-designer/SKILL.md), si está disponible, propone en el GDD las ofertas, su beneficio y la hipótesis; este módulo completa el catálogo (key, ID real o "pendiente"), el flujo y las pruebas. El código lo escribe [roblox-game-builder](../roblox-game-builder/SKILL.md) con estas reglas, dentro de su único servicio de datos.
- Los eventos se emiten con `Telemetry` ([puntos de enganche](../roblox-game-builder/references/hooks.md)); no crees un sistema de eventos paralelo.
- Activa este módulo cuando `monetization.enabled` incluya `game-passes`. Si el usuario lo solicitó y el campo no existe, registra la selección. Sin GDD, aplica sus reglas a la pregunta o al arreglo concreto.
- El GDD define qué privilegios se ofrecen y su balance; este módulo completa su contrato. No elimines un pase solicitado solo porque el builder lo considera una función para después.
- Comparte datos y economía con los otros módulos seleccionados; este módulo no define `ProcessReceipt`.
- Consumibles repetibles corresponden a Developer Products. Un pase no es una suscripción ni una venta de un artículo del avatar global.

## Contrato del catálogo

Para cada pase define `key`, `passId` real, beneficio, límites, alcance, reglas de acumulación y qué sucede al cambiar de personaje o servidor. Explica exactamente qué significa “x2”, “VIP” o “más velocidad”. No inventes IDs; si faltan, deja el prompt desactivado y documenta la configuración pendiente.

Los pases cobran una vez por privilegios dentro de la experiencia. Deben pertenecer a esta experiencia; las ventas entre experiencias fueron deshabilitadas el 30 de mayo de 2026. Usa `PromptGamePassPurchase` y consulta propiedad con `UserOwnsGamePassAsync` desde el servidor. Al ingreso aplica los privilegios ya comprados; escucha `PromptGamePassPurchaseFinished` en el servidor para actualizar una compra en la sesión. [Passes](https://create.roblox.com/docs/production/monetization/passes).

## Servicio de privilegios

Representa cada consulta con estados separados: `loading`, `owned`, `not-owned` y `unavailable`. Un fallo de red no equivale a ausencia de propiedad.

1. Registra el listener de ingreso y atiende también jugadores ya presentes, con inicialización idempotente.
2. Consulta propiedad con `pcall` y reintentos limitados. Usa caché de sesión para evitar consultas en cada frame o cada cobro de monedas.
3. En el evento de compra del servidor comprueba el ID permitido y el éxito. Actualiza el privilegio a partir del evento autorizado o vuelve a consultar propiedad; no aceptes una confirmación enviada por el cliente.
4. Aplica el beneficio mediante una función idempotente y actualiza la UI desde el estado del servidor.
5. Reaplica efectos del personaje en `CharacterAdded`. Limpia conexiones y cachés al salir.

La propiedad registrada por Roblox es la fuente de verdad. Un flag local o guardado por el juego no la reemplaza. No impongas DataStore solo para recordar propiedad si el privilegio se deriva de Roblox; agrega persistencia si el pase incluye estado propio del juego, por ejemplo un espacio de construcción. Un fallo de consulta no debe borrar ese estado. Con el servicio de datos de la fábrica ([roblox-data-architect](../roblox-data-architect/SKILL.md)), ese estado va en la sección del core que lo usa; la sección con `role: entitlements` es para derechos que da el propio juego (compras permanentes con Developer Products, regalos, premios), no para copiar la propiedad de un pase.

Usa `GetProductInfoAsync(passId, Enum.InfoType.GamePass)` para los metadatos; `GetProductInfo` está deprecado. No confundas los parámetros ni el ID del pase con un ID de producto. [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService#GetProductInfoAsync).

## Aplicación y balance

- Recalcula valores desde la base: `velocidad = velocidadBase * factorAutorizado`. Multiplicar la velocidad actual cada vez que reaplicas el pase genera acumulación accidental.
- Centraliza el cálculo de ganancias. Para un pase “x2 monedas ganadas”, define qué fuentes cubre: recolección, rondas, offline, boosts y otros pases. No dupliques paquetes comprados con Robux salvo que esté explícitamente anunciado y diseñado.
- Define si varios multiplicadores se suman, se multiplican o seleccionan el mayor, junto con sus límites. La descripción y el código deben producir el mismo resultado.
- La UI puede mostrar un acceso VIP; el servidor también valida uso, recompensa o acceso relevante. Una puerta visible o un atributo cambiado por el cliente no concede el privilegio.
- Diseña un recorrido gratuito completo. Como criterio inicial, prioriza personalización, comodidad y capacidad antes que ventajas que decidan enfrentamientos; si el GDD requiere poder competitivo, documenta su efecto en balance y rankings.
- Para beneficios de una sola entrega incluidos en un pase, usa un registro durable idempotente separado del privilegio continuo. Una consulta de propiedad repetida no vuelve a entregar el bono.

Si un pase otorga suerte o modifica recompensas aleatorias, revisa y aplica la [política de aleatoriedad pagada](https://create.roblox.com/docs/production/monetization/paid-random-items) antes de implementarlo. Ser una compra única no lo exime de esa política.

## Tienda y recuperación

Muestra beneficio, permanencia, límites, precio actual y “Ya lo tienes” para propietarios. Obtén precios en el contexto del cliente para respetar precios regionales o personalizados; no uses precios fijos del GDD como precio final. [Regional pricing](https://create.roblox.com/docs/production/monetization/regional-pricing).

- Abre el prompt nativo después de una acción intencional; evita prompts repetidos al reaparecer o cruzar una puerta.
- Si no puedes verificar propiedad, informa que la comprobación está temporalmente pendiente y ofrece reintento limitado. Mantén jugable el recorrido gratuito.
- Verifica también al reingresar para cubrir compras fuera de la experiencia. Si se requiere actualizar una compra externa durante la sesión, usa una actualización explícita y controlada; considera caché y propagación de Roblox, sin prometer efecto inmediato.
- No cambies el significado de un pase vendido al ajustar el catálogo. Conserva su implementación o documenta una migración que preserve el beneficio prometido.

## Pruebas de aceptación

Usa un proveedor de propiedad simulado en desarrollo para comprobar:

- Propietario previo al ingreso y comprador dentro de la sesión: mismo privilegio.
- Cancelación y jugador sin pase: cero privilegio adicional.
- Fallo de consulta: `unavailable`, sin borrar propiedad ni datos del juego.
- Respawn, reingreso y reaplicación repetida: beneficio conservado sin multiplicación accidental.
- Distintos pases y boosts activos: resultado exactamente igual a la fórmula del GDD.
- Solicitud falsa desde el cliente: no abre accesos ni aumenta recompensas.
- Comprador previo que nunca usó la tienda interna: recibe su beneficio al ingreso.
- Bono inicial opcional: se entrega una vez aunque se reconecte o haya operaciones concurrentes.
- UI con teclado, touch y gamepad si está dentro de las plataformas objetivo: acceso y cierre utilizables.

Prueba el flujo Marketplace en una experiencia de prueba publicada cuando sea posible. Los mocks no demuestran propiedad real ni cobro; registra lo probado y lo pendiente, sin gastar Robux sin autorización.

## Entrega del agente

Incluye catálogo, servicio de privilegios, fórmula de efectos, integración con el ciclo de personaje y UI. Registra comprobaciones fallidas y métricas de adopción; los ingresos se concilian con Roblox. Documenta configuración pendiente y decisiones de acumulación en README/GDD.

Antes de activar ventas, verifica nuevamente las fuentes oficiales. Si no puedes verificarlas, señala la revisión pendiente y conserva deshabilitada la parte afectada.
