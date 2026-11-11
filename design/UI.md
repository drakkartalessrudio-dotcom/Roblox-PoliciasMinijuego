# Interfaz de TravesurasBrainrot

Fuente: `GDD.md` (loop, onboarding, plataformas y Estado para la UI) y `design/ART.md` (estilo "Caramelo Brainrot"). Código: `src/client/UI/` con el kit de la fábrica sin cambios. Verificado con `check_ui.py` el 26 de octubre de 2026 (resultado al final).

## Principios

1. **El mundo primero.** El centro de la pantalla es de la persecución. El HUD vive en los bordes y solo muestra lo que cambia decisiones: estrellas, Botín y Dinero.
2. **Las estrellas mandan.** Lo más grande y con más contraste es el medidor de búsqueda (color `hazard`, exclusivo de la policía); el resto es secundario.
3. **Un dedo alcanza.** Todo se juega y se compra con un toque: minijuegos de un dedo, botones de acción junto al salto y tienda por pestañas.
4. **Dilo con palabras.** Cada aviso cuenta lo que pasó con números ("+$45 · +60 XP · ¡Combo!") y no solo con colores o sonidos.
5. **El servidor decide.** La interfaz muestra atributos y envía intenciones; nunca calcula un precio, una recompensa ni un resultado.

## Pantallas

| Pantalla | Módulo | Dónde | Qué muestra | Estado que usa |
| --- | --- | --- | --- | --- |
| HUD | `Screens/Hud.luau` | Slots `top`, `right` y `bottom` | Estrellas y estado de búsqueda (en un escondite: «Escondido · quédate quieto», «¡no te muevas!», segundos que le quedan al contenedor, «¡Te vieron! Este escondite ya no sirve», «Escondite lleno»), nivel y barra de XP; Dinero, Botín con tope, Cerebros, distrito y velocidad; pista del tutorial y, en el lobby, qué hacer allí | `Stars`, `WantedState`, `Spotted`, `Hidden`, `HideState`, `HideKind`, `HideLeft`, `HideMoving`, `Level`, `Xp`, `XpNeeded`, `Dinero`, `Botin`, `BotinCap`, `Cerebros`, `District`, `Speed`, `TutorialStep`, `PlotId` |
| Avisos | `Screens/Alerts.luau` | Capa `toast` | Resultado de cada travesura, estrellas, escape, arresto, depósito, subida de nivel, medalla, Ascensión, logros, viajes bloqueados por nivel y errores | Mensaje `notify` |
| Acciones | `Screens/Actions.luau` | Slot `actions` | Embestida, Empujón, herramientas compradas con su enfriamiento y, con el pase del teléfono, Depositar | `Tool_<id>`, `ToolReady_<id>`, `Pass_phone`, `Botin`, `Stars`; envía `use_tool`, `deposit` |
| Minijuegos | `Screens/Minigames.luau` | Capa `menu` (ventana arriba) | Los cinco minijuegos de las travesuras (secuencia, mantener, tocar rápido, ritmo, memoria) con temporizador | Mensaje `mischief_start`; envía `mischief_submit` y `mischief_cancel` |
| Tienda | `Screens/Shop.luau` | Modal; botón en slot `left` | Mejoras, herramientas, cosméticos y ofertas de Robux | `Up_<id>`, `Tool_<id>`, `Owns_<id>`, `Equipped_<slot>`, `Pass_<key>`, `Dinero`, `Level`; envía `buy_*`, `equip_cosmetic`, `unequip_cosmetic`, `shop_pass`, `shop_product` |
| Carrera | `Screens/Career.luau` | Modal; botón en slot `left` | Misiones diarias, cartel semanal, racha, alijo, Ascensión y perks | `Quest<i>…`, `QuestStreak`, `Weekly…`, `AscensionCount`, `AscensionBonus`, `AscensionFee`, `Perk_<id>`, `Cerebros`; envía `claim_*`, `ascend`, `buy_perk` |
| Banda | `Screens/Band.luau` | Modal; botón en slot `left`; modal de invitación | Crear, invitar, abrir, unirse, expulsar y salir; bono de banda | `BandId`, `BandName`, `BandSize`, `BandLeader`, `BandOpen`, `BandMembers`, `BandBonus`; mensajes `band_list`, `band_invite`; envía `band` |
| La Guarida | `Screens/Hub.luau` | Modal con 3 pestañas (Viajar, Logros, Jugadores); botón en slot `left` (H / L2); fundido a negro de pantalla completa en su propio `ScreenGui` (a propósito: cubre también el borde seguro durante el viaje) | Destinos con su nivel y viaje; parcela propia; lista de logros con progreso; jugadores del servidor con nivel, Ascensiones y logros, perfil de quien se toca y atajo para invitar a la banda | `Level`, `AscensionCount`, `AchCount`, `Ach_<id>`, `BandId`, `BandName`, `PlotId`, `District`; mensajes `travel`, `hub_inspect`; envía `travel`, `plot_go`, `plot_release`, `band` |
| Sala | `Screens/Sala.luau` | Slot `bottom`; modal del reto | Estado del entrenamiento y reto de check-in con íconos en lugares al azar | `AfkActive`, `AfkReason`, `AfkUsed`, `AfkCap`, `AfkNextCheckIn`; mensaje `afk_challenge`; envía `afk_answer` |

## Flujos

- **Travesura:** prompt del mundo (E o toque) → servidor valida → `mischief_start` → Minijuegos → `mischief_submit` → Avisos ("+$ · +XP").
- **Persecución:** el HUD sube las estrellas → Acciones (Embestida, tarta, banana…) → escondite o Guarida → "¡Escapaste!" con XP.
- **Esconderse:** con ≥ 1 estrella los escondites a ≤ 80 studs brillan en amarillo (rojo si están quemados) → rompe el contacto, entra y quédate quieto → el HUD dice «Escondido · quédate quieto» y baja una estrella cada 3 s; si te vieron entrar o te descubren, el escondite se pone rojo y el HUD avisa.
- **Arresto:** Avisos ("¡Te agarraron! … te rescata si llega en 5 s") → resultado con el Botín perdido.
- **Compra:** HUD → botón Tienda (B / Y) → pestaña → "Comprar" → aviso o error ("Solo se puede en una Guarida") → mismo modal.
- **Robux:** Tienda → Robux → "Comprar" → aviso nativo de Roblox con el precio; si la oferta no tiene ID, "Disponible pronto".
- **Ascensión:** HUD → Carrera (J / L1) → pestaña Ascensión → "Ascender" → segunda pulsación para confirmar → aviso con los Cerebros.
- **Banda:** botón Banda (G / R1) → crear o ver abiertas → invitar o unirse → el HUD muestra el bono; una invitación abre su modal con Aceptar y Rechazar.
- **Viaje:** portal del lobby (aviso "Viajar") o botón La Guarida (H / L2) → Viajar → servidor valida nivel, estrellas y zona segura → pantalla a negro con el nombre del destino → aparece en la Guarida del distrito. Sin el nivel: aviso "Colegio Brainrot se abre en el nivel 6".
- **Parcela:** pedestal libre (aviso "Reclamar parcela") → el cartel muestra al dueño; al tocar una parcela ajena se abre su perfil en Jugadores para compararse.
- **Sala:** el jugador entra al volumen → el HUD (slot `bottom`) cuenta el tiempo pagado → aparece "¿Sigues ahí?" → toca el ícono pedido.

## Distribución por plataforma

| Elemento | PC (teclado y ratón) | Celular y tableta | Consola (gamepad) |
| --- | --- | --- | --- |
| Estrellas y nivel | Slot `top` | Slot `top` (compacto) | Slot `top` |
| Dinero, Botín, Cerebros | Slot `right` | Slot `right` | Slot `right` |
| Acciones y herramientas | Slot `actions` + atajos Q, F, 1 a 5 | Slot `actions`, junto al botón de salto | Slot `actions` + X (Embestida), B (Empujón) |
| Tienda | Botón a la izquierda + B | Botón a la izquierda | Y |
| Carrera | Botón + J | Botón | L1 |
| Banda | Botón + G | Botón | R1 |
| Minijuegos | Ventana arriba, clic | Ventana arriba, un dedo | Selección con el stick y A |
| Pista del tutorial y Sala | Slot `bottom` | Slot `bottom` (entre los controles táctiles) | Slot `bottom` |

Zonas que no se usan: el chat (arriba a la izquierda), la barra superior de Roblox, el joystick y el botón de salto en táctil, y la barra de herramientas de Roblox (no se usa: las herramientas son botones propios).

## Estados

| Pantalla | Cargando | Vacío | Error o no disponible | Normal |
| --- | --- | --- | --- | --- |
| HUD | "Cargando…" hasta que llega `Level` | — | — | Estrellas, nivel y saldos |
| Tienda | Valores en 0 hasta que cargue el perfil | — | Compra desactivada: "Solo se puede en una Guarida", "No te alcanza el dinero", "Ya está al máximo"; ofertas Robux sin ID: "Disponible pronto" | Botones "Comprar" con el costo |
| Carrera | — | Sin misiones activas: la fila no se muestra | "No está disponible" si el servidor la rechaza | Progreso y "Cobrar" |
| Banda | — | "No hay bandas abiertas ahora", "No hay jugadores sin banda ahora" | "La banda está llena", "Ese jugador ya tiene banda" | Lista de miembros y acciones |
| La Guarida | — | "Todavía no tiene logros" en el perfil de otro jugador; sin parcela: "Reclama una parcela libre…" | "Te falta nivel", "Estás buscado: pierde a los policías primero", "Solo se puede en una Guarida o en el lobby", "No se pudo viajar, inténtalo de nuevo" | Destinos disponibles, logros con ✓ y lista ordenada por progreso |
| Sala | — | Oculta si no se entrena | Pausas explicadas: reto sin responder, errores, tope diario | Tiempo pagado y próximo check-in |
| Minijuegos | — | — | "Fallaste", "Muy rápido: no cuenta", "Se acabó el tiempo" | El minijuego en curso |

## Accesibilidad

Texto con tamaño mínimo de 14 px y máximo de 36 px, que respeta el tamaño de texto preferido de Roblox. Botones de 48 px o más. Las estrellas parpadean solo si no hay movimiento reducido. El color nunca es la única señal: las estrellas son ★ (forma), los errores traen texto y el Botín lleno se pone en rojo además de decir "Botín lleno". Cada acción tiene botón en pantalla y atajo de teclado o gamepad. Los íconos del reto de la Sala llevan el nombre escrito.

## Verificación en Studio

Pendiente del usuario: emulador de teléfono chico apaisado, tableta y 1080p; gamepad; y `DebugZones` del kit para ver las zonas reservadas. Revisar que los cinco slots no se pisen con el HUD de dos modales abiertos, que el minijuego no tape los botones de acción en el teléfono más chico y que el reto de la Sala quepa en 640 × 360.

## Pendientes

- ui-designer → builder: precio en Robux de cada oferta (hoy dice "se muestra al comprar"); si se quiere mostrar el precio regional hace falta que el cliente consulte `MarketplaceService:GetProductInfoAsync` con los IDs reales cuando existan (abierto)
- ui-designer → environment-artist: iluminación por distrito en el cliente (los presets `playa`, `neon`, `queso`, `puerto` y `sala` del tema) según el atributo `District` (abierto)
- ui-designer → art-director: íconos propios de las estrellas, los policías y las herramientas en lugar de emojis (abierto)
