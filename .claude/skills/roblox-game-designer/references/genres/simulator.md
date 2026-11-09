# Simulador o clicker

## Loop

Realizar una acción repetible (click, recolectar, entrenar), ganar un recurso, comprar mejoras que aumentan la ganancia y desbloquear zonas o niveles nuevos. El regreso suele venir de metas largas, coleccionables o reinicios con ventaja (rebirth).

## Palancas de diseño

- **Curva de costos e ingresos**: es el corazón del género. Lee [economía](../economy.md) y haz la tabla de tiempo hasta hitos.
- **Decisiones de compra**: varias mejoras que compiten (más por acción, ingreso automático, capacidad). Una sola mejora repetida no es una decisión.
- **Zonas**: cada una cambia algo además de los números (recurso nuevo, peligro, actividad).
- **Rebirth**: reinicia el progreso a cambio de un multiplicador permanente. Define cuándo se ofrece y cuánto acelera.

## Onboarding

La acción básica y su recompensa en los primeros segundos; la primera mejora comprable en los primeros minutos. Muestra el siguiente objetivo ("faltan 30 para la mejora") en vez de esperar que el jugador lo descubra.

Pasos de funnel habituales: `joined`, `first_action`, `first_upgrade`.

## Economía y progresión

Define la regla de apilamiento de multiplicadores (mejoras, rebirth, eventos y beneficios pagados). Si hay ganancias sin jugar, tienen tope y se calculan en el servidor. El servidor limita la frecuencia de la acción: un autoclicker no debe superar lo que permite el diseño.

## Brief de niveles

Normalmente `design.levels: true` solo si las zonas son espacios diseñados (hub, zonas con portales). Indica tamaño de cada zona, distancia del spawn a la primera actividad y qué bloquea el acceso a cada una.

## KPIs útiles

- Tiempo real hasta la primera mejora y hasta el primer rebirth.
- Moneda ganada y gastada por sesión: si se gasta poco, faltan sumideros atractivos.
- Retención D1: el género depende del regreso.

## Errores frecuentes

- Muros de grind: el siguiente hito pasa de minutos a horas de golpe.
- Números enormes sin decisiones nuevas.
- Multiplicadores que se multiplican entre sí sin tope.
- Acciones de cliente que el servidor no limita.

## Qué no asumir

No hace falta incluir mascotas, huevos ni tradeo: son sistemas grandes y los huevos pagados traen reglas de aleatoriedad. Van a "posterior" salvo que el usuario los pida.
