# Analíticas de TravesurasBrainrot

Fuente: `GDD.md` (KPIs objetivo, onboarding, progresión, economía). Esquema: `src/server/AnalyticsSchema.json`. Módulo: `src/server/Analytics.luau` (plantilla sin cambios). Reglas de Roblox verificadas el 26 de octubre de 2026 (ver [reglas de AnalyticsService](../.claude/skills/roblox-analytics-dev/references/platform-rules.md)).

## KPIs y eventos

| KPI del GDD | Eventos | Cómo se calcula | Dónde se ve |
| --- | --- | --- | --- |
| Conversión del onboarding (y abandono por paso) | Onboarding: `joined`, `first_mischief`, `first_star`, `first_escape`, `first_deposit`, `first_upgrade`, `first_level_up` | Nuevos en `first_deposit` / nuevos en `joined`; el abandono de cada paso sale del mismo embudo | Funnel de onboarding de Creator Analytics |
| Uso de la Sala AFK | Propios: `afk_enter`, `afk_exit`, `afk_checkin`, `afk_suspect` | Jugadores nivel ≥ 8 con `afk_enter` en la semana / jugadores nivel ≥ 8 activos; `afk_checkin` y `afk_suspect` sobre el total de check-ins | Eventos propios |
| Retención D1 y D7 (con y sin banda) | Creator Analytics + propios: `band_mischief`, `session_level` | Retención de quienes tuvieron `band_mischief` frente a quienes no; `session_level` (valor = nivel) separa por avance | Retención y eventos propios |
| Embudo de progresión | Progresión `Ciudad`, un evento por nivel completado (1 a 49); propio `ascension` | % que llega a los niveles 6, 14, 20, 26, 40 y a la 1ª Ascensión | Progresión de Creator Analytics |
| Tasa de arrestos | Propio `arrest` (valor = Botín perdido, campo `stars`) | Arrestos por hora de juego por banda de nivel | Eventos propios |
| Salud de la economía | Economía: monedas `dinero` y `cerebros` (fuente y sumidero, con tipo `Gameplay`, `Shop`, `TimedReward`, `IAP`) | Dinero ganado y gastado por sesión; tiempo hasta la 1ª Ascensión con `ascension` | Economía de Creator Analytics |

## Eventos

| Nombre | Tipo | Cuándo lo emite el servidor | Valor | Campos |
| --- | --- | --- | --- | --- |
| `joined` (paso 1), `first_mischief` (2), `first_star` (3), `first_escape` (4), `first_deposit` (5), `first_upgrade` (6), `first_level_up` (7) | Onboarding | La primera vez que ocurre cada hito (bandera con fecha en el perfil) | — | — |
| `Ciudad` | Progresión | Al subir de nivel (completa el nivel anterior) | Nivel alcanzado | — |
| `dinero`, `cerebros` | Economía | Después de aplicar cada ganancia o gasto | Cantidad | Tipo: `Gameplay`, `Shop`, `TimedReward`, `IAP` |
| `session_level` | Propio | Cuando el perfil queda listo | Nivel del jugador | — |
| `mischief_complete` | Propio | Termina una travesura individual o de banda | Botín ganado | `item` = id de la travesura |
| `band_mischief` | Propio | Termina una travesura de banda | Jugadores que participaron | `item` |
| `star_reached` | Propio | Se alcanza una estrella nueva en el ciclo | Estrellas | — |
| `cop_knockdown` | Propio | Se derriba un policía | 1 | `item` = tipo de policía |
| `arrest` | Propio | Se resuelve un arresto | Botín perdido | `stars` = estrellas al arresto |
| `band_rescue` | Propio | Un compañero rescata a otro | 1 | — |
| `ascension` | Propio | Se completa una Ascensión | Número de Ascensión | — |
| `upgrade_bought` | Propio | Se compra un nivel de mejora | Nivel nuevo | `item` = id de la mejora |
| `district_entered` | Propio | Entra a un distrito distinto | 1 | `district` = id del nivel de `Levels.json` |
| `travel` | Propio | Termina un viaje por portal o menú (Transit) | 1 | `district` = id del destino (`lobby`, `colegio`…) |
| `plot_claimed` | Propio | Reclama una parcela del lobby | 1 | `item` = id de la parcela |
| `achievement_unlocked` | Propio | Cruza la meta de un logro durante la sesión | 1 | `item` = id del logro |
| `afk_enter`, `afk_exit` | Propio | Empieza y termina de entrenar en la Sala | 1 | — |
| `afk_checkin` | Propio | Responde bien un reto | 1 | — |
| `afk_suspect` | Propio | Se marca una respuesta sospechosa (tiempos casi idénticos) | 1 | — |
| `hide_entered` | Propio | Un escondite te oculta a salvo (nadie te vio entrar) | Estrellas | `item` = `bush` o `container`; `stars` |
| `hide_burned` | Propio | Un escondite deja de ocultarte | 1 | `item` = motivo (`seen` te vieron entrar, `discovered` un policía te encontró, `timeout` se acabó el contenedor); `stars` |
| `hide_escaped` | Propio | Pierdes todas las estrellas estando oculto | Estrellas que tenías | `item` = `bush` o `container`; `stars` |

## Campos propios

| Ranura | Dimensión | Valores posibles |
| --- | --- | --- |
| CustomField01 | `item` | ids de travesuras (14), de policías (6), de mejoras (8) y de escondites (`bush`, `container`, `seen`, `discovered`, `timeout`): 33 valores |
| CustomField02 | `district` | 6 distritos |
| CustomField03 | `stars` | 0 a 6 |

Combinaciones máximas: 33 × 6 × 7 = 1.386, muy por debajo de las 8.000 que admite Roblox.

## Presupuesto

Lo más activo son unas 4 a 6 travesuras por minuto (cada una genera `mischief_complete`, 2 de economía y a veces `star_reached`), más derribos y eventos de la Sala cada 5 s solo en `afk_*` de cambio de estado. Pico estimado: unos 12 a 16 eventos por jugador y minuto, bajo el límite de 20 de `Analytics.luau`. Si una sesión intensa lo supera, el módulo descarta el exceso con un aviso en vez de poner en riesgo el límite global.

## Verificación

- **Studio:** AnalyticsService no envía eventos desde Studio. Con el atributo `Debug` en `true` en los ModuleScripts `Telemetry` y `Analytics`, el Output muestra cada evento que se enviaría; hay que recorrer el loop (travesura, estrella, escape, depósito, compra, subida de nivel) y comprobar el orden y que no haya duplicados.
- **Experiencia de prueba publicada:** la herramienta View Events de Creator Analytics muestra los eventos casi en tiempo real; los gráficos tardan hasta 24 horas. Publicar lo hace el usuario.

## Privacidad

Ningún evento ni campo incluye nombres de usuario, nombres de banda, texto de chat ni identificadores del jugador: AnalyticsService asocia cada evento a su jugador.

## Pendientes

- analytics-dev → builder: `check_analytics.py` avisa que `dinero` y `cerebros` no aparecen como literales en llamadas a `Telemetry` porque los nombres vienen de `Game/Content.luau` y `Economy.add` (falso positivo; las monedas están declaradas) (cerrado)
- analytics-dev → game-designer: el KPI de retención con y sin banda se calcula en Creator Analytics comparando cohortes, no con un evento propio (abierto)
