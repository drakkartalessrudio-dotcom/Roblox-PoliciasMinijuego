---
name: roblox-monetization-avatar-ugc
description: Integrar ventas de artículos del avatar de Roblox dentro de una experiencia cuando el GDD selecciona UGC, con catálogo, permisos de venta, prompts y comisiones verificadas. Distingue venta de artículos existentes de creación y publicación de assets propios. También para preguntas o arreglos sobre la venta de artículos UGC aunque no haya GDD.
metadata:
  version: "1.1.0"
  last_verified: "2026-10-07"
---

# Monetización con artículos de avatar y UGC

Integra un catálogo autorizado y una compra nativa que entregue el artículo al inventario de Roblox. Un cosmético que solo existe dentro del juego no se convierte automáticamente en UGC del Marketplace.

## Integración y alcance

- Sigue el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md). El skill [roblox-game-designer](../roblox-game-designer/SKILL.md), si está disponible, propone en el GDD las ofertas, su beneficio y la hipótesis; este módulo completa el catálogo (key, ID real o "pendiente"), el flujo y las pruebas. El código lo escribe [roblox-game-builder](../roblox-game-builder/SKILL.md) con estas reglas, dentro de su único servicio de datos.
- Los eventos se emiten con `Telemetry` ([puntos de enganche](../roblox-game-builder/references/hooks.md)); no crees un sistema de eventos paralelo.
- Activa este módulo cuando `monetization.enabled` incluya `avatar-ugc`, o cuando el usuario solicite esta venta; registra la selección en el GDD. Sin GDD, aplica sus reglas a la pregunta o al arreglo concreto.
- El GDD decide qué se ofrece, el estilo y el contexto de exhibición; este módulo completa el contrato del catálogo. Integra los assets verificados necesarios aunque el builder tenga un modo de prototipo sin assets externos.
- Elige la ruta: **vender artículos existentes** o **crear y publicar artículos propios**. La segunda requiere producción de assets y configuración fuera del código del juego.
- No agregues Developer Products para cobrar otra vez por el mismo artículo, ni reemplaces la compra Marketplace por una moneda interna.

## Contrato del catálogo

Para cada entrada define `key`, `assetId` o `bundleId` real, tipo, creador, permiso de venta, disponibilidad, modalidad de propiedad y método de preview. Diferencia ID de artículo, bundle, Developer Product y Game Pass.

Si no hay IDs o autorización/configuración verificable, entrega el espacio de tienda con compras desactivadas y explica lo pendiente. No presentes placeholders como productos reales ni prometas vender un asset aún no moderado.

## Permisos y habilitación

Para habilitar ventas de avatar dentro de una experiencia, el creador del artículo añade el **Start Place ID** a sus ubicaciones de venta y el dueño del juego habilita el **Asset ID** en **Monetization → Avatar Items**. Si ambos son el mismo creador, Roblox puede habilitarlo automáticamente. Comprueba estas condiciones para cada artículo, junto con disponibilidad y moderación. [Avatar items](https://create.roblox.com/docs/production/monetization/avatar-items).

No supongas que encontrar un artículo en el catálogo concede permiso para venderlo en cualquier experiencia. Evita insertar modelos desconocidos con scripts para construir el exhibidor; emplea datos de avatar y assets revisados.

Si se crean assets propios, documenta herramientas de producción, validación técnica, derechos de uso, requisitos vigentes del creador, moderación y costes de publicación. Crear ropa o accesorios no termina al generar Luau. No pagues tasas ni publiques assets sin autorización para esas acciones.

## Comisiones y proyecciones

La tabla base vigente para compras dentro del juego asigna **30% al creador del artículo y 40% al dueño del juego**. Son roles diferentes; si una misma entidad ocupa ambos, puede recibir ambas participaciones. No uses “30–40%” como una única comisión universal. La reventa de Limiteds tiene otra distribución y la venta directa en Marketplace puede usar reparto progresivo. [Marketplace fees and commissions](https://create.roblox.com/docs/marketplace/marketplace-fees-and-commissions).

Antes de estimar margen, verifica modalidad, comisiones, tasas y precio aplicables al artículo. Presenta las cifras como supuestos fechados; no las incrustes como garantía de ingreso en el juego. La venta requiere integración y configuración, aunque no se creen nuevos assets.

## Integración técnica

Para artículos individuales utiliza `GetProductInfoAsync(assetId, Enum.InfoType.Asset)`, `PromptPurchase` y, si se necesita verificar propiedad, `PlayerOwnsAssetAsync`. Para bundles emplea las APIs específicas, como `PromptBundlePurchase` y `PlayerOwnsBundleAsync`; no los pases como assets individuales. [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService).

- El cliente muestra catálogo y solicita una clave. Si hay remotes, el servidor valida la clave contra su catálogo; no acepta IDs arbitrarios para conceder beneficios propios del juego.
- La UI muestra nombre, creador, artículo o bundle, precio vigente y tipo de propiedad. Si admite opciones temporales, no las anuncies como permanentes; soporta esa modalidad explícitamente o exclúyela del catálogo.
- Respeta el precio devuelto para el jugador y el precio del prompt nativo. Si falla la consulta o el artículo no puede venderse, desactiva el botón y permite seguir jugando.
- Abre el prompt tras una acción intencional. Cancelarlo no castiga al jugador ni concede propiedad.
- Roblox entrega el artículo del avatar. No crees una copia en DataStore para simular que fue comprado ni uses `ProcessReceipt` para confirmar esta venta.
- El cierre de un prompt sirve para actualizar la UI; verifica propiedad en el servidor antes de otorgar un beneficio propio del juego. Considera errores, caché y propagación; estado desconocido no significa “no comprado”.
- No inventes una confirmación de comisión a partir del cierre del prompt. Concíliala con los reportes del creador/dueño del juego.

## Preview y experiencia de compra

Usa un maniquí o un `ViewportFrame` para previews; si haces try-on sobre el personaje, guarda y restaura la apariencia al salir, cancelar o reaparecer. Probarse un artículo no prueba propiedad.

- La tienda debe encajar con el juego: boutique de roleplay, estación de personalización o zona cosmética, según el GDD.
- El preview no modifica estadísticas competitivas, colisiones ni inventario económico.
- Carga previews de forma limitada y libera instancias al cerrar; no cargues todo el catálogo al entrar.
- Evita que overlays y botones tapen controles touch o impidan navegación con gamepad en plataformas objetivo.
- Si ofreces un premio interno por poseer un artículo, declara si alcanza a propietarios previos. Consulta de propiedad no demuestra dónde se compró; no prometas identificar compra en esta sesión sin un mecanismo verificable.
- Un premio interno de una sola entrega necesita persistencia idempotente; no se entrega en cada respawn o consulta.

## Pruebas de aceptación

- Artículo permitido, retirado, moderado, sin ubicación autorizada e ID incorrecto: comportamiento controlado sin ventas falsas.
- Compra cancelada y error del servicio: juego utilizable, sin privilegios falsos.
- Propietario previo, compra nueva y reingreso: UI coherente con la propiedad verificada.
- Asset y bundle: cada uno usa la ruta y la verificación correctas.
- Try-on, cancelar, morir y salir de tienda: apariencia restaurada sin alterar progreso.
- Solicitudes con ID arbitrario o confirmación falsa: no conceden beneficios internos.
- UI móvil/gamepad si corresponde: producto, precio, compra y cierre utilizables.
- Bono interno opcional: una entrega durable, sin duplicación por reingreso.

Usa mocks para errores y estados locales; verifica la configuración y el flujo real en una experiencia de prueba publicada. Registra lo observado y lo pendiente, sin realizar compras que gasten Robux sin autorización.

## Entrega del agente

Incluye catálogo, preview, UI y configuración requerida de ventas. Documenta propietario de la experiencia y creador de cada asset, bloqueos, pruebas realizadas y supuestos de comisiones. Mide descubrimiento, try-on y apertura del prompt como acciones; ventas e ingresos se confirman con reportes de Roblox.

Vuelve a consultar las fuentes oficiales antes de activar las ventas o proyectar ingresos. Si no puedes verificarlas, conserva deshabilitada la parte afectada y señala qué revisión falta.
