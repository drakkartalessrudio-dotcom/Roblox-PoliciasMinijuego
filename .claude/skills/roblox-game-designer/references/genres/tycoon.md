# Tycoon

## Loop

Reclamar una parcela, comprar generadores que producen dinero, usar ese dinero en más generadores y mejoras hasta completar la base. El regreso suele venir de bases más grandes, rebirth o personalización. Ver la base de los demás da un componente social.

## Palancas de diseño

- **Orden de compras**: los botones aparecen en un camino que guía al jugador; cada compra muestra la siguiente.
- **Ingreso por segundo** y costo de cada compra: definen el ritmo. Haz la tabla de tiempo hasta hitos de [economía](../economy.md).
- **Esperas con decisiones**: mientras junta dinero, el jugador debería tener algo que elegir o hacer (recolectar a mano, minijuegos, mejoras alternativas).
- **Final de la base**: qué pasa al comprar todo (rebirth, expansión, cosméticos).

## Onboarding

Reclamar la parcela debe ser obvio y estar a pocos pasos del spawn. La primera compra está disponible con el dinero inicial y produce algo visible de inmediato.

Pasos de funnel habituales: `joined`, `plot_claimed`, `first_purchase`.

## Economía y progresión

El dinero lo calcula y descuenta el servidor; los botones de compra validan saldo, orden y que la parcela sea del jugador. Si el progreso se conserva entre sesiones, define qué se guarda (compras, dinero) y cómo se reconstruye la base al entrar.

## Brief de niveles

`design.levels: true` para las parcelas y el espacio común. La cantidad de parcelas debe ser al menos el máximo de jugadores del servidor. Indica tamaño de parcela, ubicación de los botones en secuencia y distancia entre parcelas.

## KPIs útiles

- Tiempo hasta la primera compra y porcentaje que completa la base.
- Abandono mientras espera dinero: muestra esperas sin decisiones.
- Duración de sesión.

## Errores frecuentes

- Esperas largas sin nada que hacer.
- Parcelas que no se liberan cuando el dueño sale.
- Compras que se pueden saltar o duplicar con dos clicks simultáneos.
- Más jugadores que parcelas.

## Qué no asumir

No todo tycoon necesita combate, robos entre bases ni pases VIP. Son decisiones de diseño con consecuencias en balance; inclúyelas solo si el usuario las quiere.
