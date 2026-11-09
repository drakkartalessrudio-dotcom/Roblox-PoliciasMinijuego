# Analíticas de ObbyEjemplo

Fuente: `GDD.md` (KPIs objetivo y funnel de onboarding). Esquema: `src/server/AnalyticsSchema.json`. Módulo: `src/server/Analytics.luau` (plantilla sin cambios). Verificado contra la documentación de Roblox el 2026-10-09.

## KPIs y eventos

| KPI del GDD | Eventos | Cómo se calcula | Dónde se ve |
| --- | --- | --- | --- |
| Conversión del onboarding | Onboarding: `joined`, `first_checkpoint`, `level_1_complete` | Jugadores nuevos en el paso 3 / jugadores nuevos en el paso 1 | Funnel de onboarding en Creator Analytics |
| Progresión por nivel | Progresión `Obby`, niveles 1 a 3 (inicio y final) | Completan el nivel / lo empiezan | Eventos de progresión en Creator Analytics |
| Muertes por nivel | Evento propio `death`, valor = nivel | Suma de `death` por nivel / jugadores que empiezan el nivel | Eventos propios en Creator Analytics |

## Eventos

| Nombre | Tipo | Cuándo lo emite el servidor | Valor | Campos |
| --- | --- | --- | --- | --- |
| `joined` (paso 1) | Onboarding | El servidor registra al jugador | — | — |
| `first_checkpoint` (paso 2) | Onboarding | Primer checkpoint del nivel 1 | — | — |
| `level_1_complete` (paso 3) | Onboarding | Toca la meta del nivel 1 | — | — |
| `Obby` | Progresión | Empieza y completa cada nivel | Nivel 1 a 3 | — |
| `death` | Propio | Muere el personaje (sin haber terminado) | Nivel actual | — |
| `obby_finished` | Propio | Toca la meta del último nivel | Segundos desde que entró | — |

Sin monedas, funnels adicionales ni campos propios.

## Presupuesto

Un jugador genera como mucho unos 3 eventos de onboarding, 6 de progresión y algunas muertes por minuto en los peores tramos: muy por debajo de 20 por jugador y minuto.

## Verificación

- **Studio:** AnalyticsService no envía eventos desde Studio. Con el atributo `Debug` en `true` en los ModuleScripts `Telemetry` y `Analytics`, el Output muestra cada evento que se enviaría.
- **Experiencia de prueba publicada:** la herramienta View Events de Creator Analytics muestra los eventos casi en tiempo real; los gráficos tardan hasta 24 horas.

## Privacidad

Ningún evento ni campo incluye nombres de usuario, texto de chat ni identificadores del jugador: AnalyticsService ya asocia cada evento a su jugador.
