---
name: roblox-monetization-developer-products
description: Diseñar e implementar compras repetibles con Robux en Roblox, como moneda, consumibles, revivir o saltar etapas, cuando el GDD selecciona Developer Products. Incluye recibos persistentes y recompensas aleatorias pagadas si el diseño las requiere. También para preguntas o arreglos sobre Developer Products y ProcessReceipt aunque no haya GDD.
metadata:
  version: "1.2.0"
  last_verified: "2026-10-07"
---

# Monetización con Developer Products

Implementa compras repetibles que entreguen exactamente el beneficio anunciado, aunque el jugador se desconecte o Roblox vuelva a enviar el recibo.

## Integración y alcance

- Sigue el [contrato de la fábrica](../roblox-game-builder/references/factory-contract.md). El skill [roblox-game-designer](../roblox-game-designer/SKILL.md), si está disponible, propone en el GDD las ofertas, su beneficio y la hipótesis; este módulo completa el catálogo (key, ID real o "pendiente"), el flujo y las pruebas. El código lo escribe [roblox-game-builder](../roblox-game-builder/SKILL.md) con estas reglas, dentro de su único servicio de datos.
- Los eventos se emiten con `Telemetry` ([puntos de enganche](../roblox-game-builder/references/hooks.md)); no crees un sistema de eventos paralelo. Después de una entrega durable que da moneda, registra `Telemetry.economy(player, "source", moneda, cantidad, saldo, "IAP", sku)` una sola vez por `PurchaseId`.
- En un juego de la fábrica, actívalo solo si el GDD incluye `developer-products` en `monetization.enabled`. Si el usuario pidió esta monetización y el campo no existe, documenta la selección en el GDD. Sin GDD, aplica sus reglas a la pregunta o al arreglo concreto.
- El GDD decide qué se ofrece y el balance; este skill completa el contrato del catálogo y decide cómo cobrar y entregar correctamente. Si la base propone omitir persistencia, implementa la persistencia necesaria para las compras.
- Si se combinan monetizaciones, integra sus servicios en el mismo proyecto y sistema de datos. Solo este módulo controla `ProcessReceipt`.
- Una ventaja permanente comprada una vez corresponde a un Game Pass. Un cosmético del inventario global de Roblox corresponde al módulo UGC.

## Contrato del catálogo

Antes de programar, define cada producto en el GDD y en una configuración validada:

| Campo | Decisión necesaria |
| --- | --- |
| `key`, `productId` | Clave estable del juego e ID real de Developer Product; no confundir con un pass o asset |
| Beneficio | Cantidad, moneda, objeto o derecho canjeable concreto |
| Aplicación | Inmediata, inventario o canje; condiciones válidas y comportamiento si ya no se cumplen |
| Duración | Para boosts: cuándo inicia, qué sucede al salir y cómo se acumula |
| Dependencias | Perfil cargado, estado de ronda, checkpoint o política de aleatoriedad |
| Versionado | Cómo atender recibos antiguos si el catálogo cambia o se retira |

Si faltan IDs, entrega el juego con las ofertas desactivadas y un adaptador de pruebas separado. No inventes IDs ni simules cobros reales. Lista la configuración pendiente en el README generado.

## Presentación y flujo de compra

Los Developer Products admiten compras repetidas. Cobra mediante `PromptProductPurchase`; la entrega se confirma exclusivamente mediante `ProcessReceipt` en el servidor. `PromptProductPurchaseFinished` no demuestra un pago exitoso. Los productos deben pertenecer a esta experiencia; las ventas entre experiencias fueron deshabilitadas el 30 de mayo de 2026. [Developer Products](https://create.roblox.com/docs/production/monetization/developer-products).

- Consulta información con `GetProductInfoAsync(productId, Enum.InfoType.Product)` y controla errores. El método anterior `GetProductInfo` está deprecado. [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService#GetProductInfoAsync).
- Obtén el precio que ve el jugador desde el cliente, especialmente si hay precios personalizados o regionales. No uses un precio fijo del GDD como precio mostrado ni como prueba del pago. [Regional pricing](https://create.roblox.com/docs/production/monetization/regional-pricing).
- Explica cantidad, duración y destino antes de abrir el prompt nativo, mediante una acción intencional del jugador. Incluye estados disponible, pendiente, entregado y temporalmente no disponible.
- Desactiva solicitudes nuevas si el perfil no puede guardarse. Eso no elimina la obligación de recuperar una compra que ya ocurrió.
- El cliente solicita una clave de oferta. El servidor resuelve el catálogo y valida elegibilidad; nunca acepta cantidad, recompensa, precio ni confirmación de compra del cliente.

## Servicio de recibos

Mantén un único `MarketplaceService.ProcessReceipt` con dispatch por `ProductId`. En una experiencia con varios places, regístralo en todos los places donde haya jugadores (con el código compartido de la fábrica ya ocurre): Roblox reintenta un recibo pendiente cuando el jugador vuelve a entrar, y puede entrar a cualquier place. Valida `PlayerId`, `ProductId` y `PurchaseId` contra el catálogo y los datos del jugador. Conserva handlers para productos retirados con recibos pendientes. [MarketplaceService.ProcessReceipt](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService#ProcessReceipt).

Sus decisiones son `Enum.ProductPurchaseDecision.PurchaseGranted` y `Enum.ProductPurchaseDecision.NotProcessedYet`; usa esos enums, no los de otros sistemas de recibos.

Diseña la operación alrededor de estas invariantes:

1. Un `PurchaseId` produce un único cambio económico durable. Dos compras distintas del mismo producto producen dos cambios.
2. El beneficio y su registro de recibo se guardan juntos. Evita dos escrituras independientes, una para monedas y otra para recibos.
3. Todas las escrituras del perfil —incluidos autosave, progreso y compras— usan el mismo coordinador. Un guardado posterior no puede borrar una compra ya confirmada.
4. Serializa operaciones de un jugador y protege su perfil frente a servidores concurrentes mediante bloqueo de sesión o una estrategia equivalente demostrada.
5. No depende de la presencia del personaje, de una ventana de UI ni de que siga activa la ronda que originó el prompt.

Planifica el crecimiento del registro de recibos y los límites de almacenamiento. No borres IDs antiguos para ahorrar espacio sin una estrategia que conserve la deduplicación ante un reenvío.

**Con el servicio de datos de la fábrica** ([roblox-data-architect](../roblox-data-architect/SKILL.md)): el único `ProcessReceipt` despacha por `ProductId` y devuelve `PlayerData.grantPurchase(player, receipt.PurchaseId, grant)`, donde `grant` aplica el beneficio con la API de los cores (por ejemplo `Economy.add`) y devuelve `true`. El servicio cumple las invariantes de arriba: espera a que cargue el perfil, no vuelve a entregar un `PurchaseId` registrado, guarda el beneficio y el recibo en la misma escritura (la sección con `role: purchases` del esquema) y devuelve `PurchaseGranted` solo si ese guardado terminó; si falló, `NotProcessedYet` y el reintento de Roblox no duplica la entrega. Al llegar al límite de recibos borra el más viejo de los ya guardados, porque Roblox no reenvía un recibo confirmado. Lo prueban las pruebas con Lune del servicio de datos.

Roblox recomienda manejo atómico y protección de sesiones para evitar pérdida o duplicación de compras. Una carga fallida no debe convertirse en datos vacíos que sobrescriban un perfil existente. [Player data and purchasing systems](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing).

### Resolución del recibo

- Perfil ausente, carga fallida, bloqueo ajeno, producto desconocido o fallo de escritura: registra el problema y devuelve `NotProcessedYet`.
- Recibo ya aplicado **y confirmado en almacenamiento durable**: devuelve `PurchaseGranted` sin volver a concederlo.
- Recibo nuevo: prepara un cambio del perfil, añade beneficio y marcador, persiste la operación y sincroniza el estado autorizado antes de devolver `PurchaseGranted`.
- Si la escritura pudo completarse pero la respuesta falló, reconcilia con el estado durable antes de reintentar. Nunca asumas que un error implica que no se guardó.
- Distingue cambios preparados en memoria de cambios confirmados; un marcador solo en memoria no justifica `PurchaseGranted`. Evita que el jugador gaste un saldo preparado mientras la entrega sigue incierta.
- Los callbacks de `UpdateAsync` no pueden hacer yield. Mantén sus transformaciones sin efectos externos; no abras prompts, crees objetos, envíes remotes ni vuelvas a sortear dentro de ellas. [Data stores](https://create.roblox.com/docs/cloud-services/data-stores).

No prometas reintentos automáticos con una frecuencia inventada. El `NotProcessedYet` deja el recibo pendiente; diseña la recuperación para futuras invocaciones y reingresos. [Developer Products](https://create.roblox.com/docs/production/monetization/developer-products).

## Consumibles que dependen del momento

Como convención de esta fábrica, vende derechos durables canjeables para acciones frágiles:

- **Revivir:** otorga un crédito de revive. El servidor valida la oportunidad de uso; si la ronda terminó, el crédito permanece para otra oportunidad compatible.
- **Saltar etapa:** otorga un crédito de salto. El servidor calcula el próximo checkpoint permitido; el cliente no decide a cuál teletransportarse.
- **Boost:** representa duración y reglas de acumulación en datos. Decide en el GDD si corre en tiempo real o tiempo jugado; la descripción debe coincidir.

El canje consume el derecho mediante una operación protegida frente a solicitudes concurrentes. Para efectos que cruzan datos y mundo, define recuperación ante un cierre entre el consumo y el efecto. No vendas una ventana de segundos que pueda desaparecer mientras se cobra. No habilites ventas externas para un producto cuyo beneficio solo pueda existir en una ronda actual, salvo que exista una entrega recuperable explícita.

## Aleatoriedad pagada: cargar solo cuando corresponde

Si hay huevos, cajas, ruletas, rerolls, suerte o moneda comprable que permita obtener recompensas aleatorias, lee [paid-random-items.md](references/paid-random-items.md) antes de implementarlos. No agregues gacha a un juego que no lo pidió.

## Pruebas de aceptación

Usa recibos sintéticos en un adaptador de desarrollo aislado; nunca expongas un remote de “confirmar compra”. Verifica resultados observables:

- Repetir el mismo recibo, incluso concurrentemente: una entrega; procesar dos `PurchaseId` distintos: dos entregas.
- Fallo de carga, escritura y respuesta después de guardar: sin pérdida, doble saldo ni confirmación prematura.
- Desconexión, reingreso y cambio de servidor durante la operación: beneficio recuperable.
- Ronda terminada, personaje ausente y compra externa: derecho utilizable o recuperación definida.
- Autosave concurrente: la compra y su registro sobreviven.
- Producto retirado o desconocido: conserva el recibo pendiente y genera diagnóstico; no lo confirma sin entregar.
- Cancelación del prompt y payloads falsos: cero beneficio. Precio indisponible: oferta desactivada.

Separa la prueba local del flujo Marketplace real. Registra qué se verificó en Studio y qué falta comprobar en una experiencia de prueba publicada; no gastes Robux sin autorización del usuario.

## Entrega del agente

Incluye catálogo, handler único de recibos, integración con datos, UI y evidencia de las pruebas anteriores. Documenta en el GDD el comportamiento de canje y en el README los IDs/configuración pendientes. Mantén logs estructurados de recibos pendientes y fallos; calcula métricas de entrega desde cambios durables. Los ingresos y la conciliación provienen de los reportes de Roblox, no de clicks en “comprar”.

Antes de activar ventas, vuelve a verificar las fuentes oficiales enlazadas. Si no puedes verificarlas, señala la revisión pendiente y conserva deshabilitada la parte afectada.
