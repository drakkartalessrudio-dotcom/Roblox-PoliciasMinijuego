# Minijuegos por rondas

Incluye juegos de lobby y ronda: recolección de monedas contra reloj, último en pie, escondidas, carreras.

## Loop

Esperar en el lobby, jugar una ronda con un objetivo claro, ver resultados y volver al lobby. El regreso viene de variedad (mapas, modos), progreso entre rondas o competencia con amigos.

## Palancas de diseño

- **Duración** de lobby, ronda y resultados. Un lobby largo es tiempo muerto.
- **Mínimo de jugadores**: define qué pasa con 1 o 2 jugadores. Un juego que necesita 8 para empezar casi nunca empieza.
- **Ingreso a mitad de ronda**: espera en el lobby, entra como espectador o se une con desventaja controlada.
- **Regla de victoria** fácil de entender y visible durante la ronda (marcador, tiempo restante).
- **Recompensa por participar**, no solo por ganar, para que perder no expulse.

## Onboarding

El jugador nuevo entiende qué hacer en la ronda sin haber leído nada: objetivo en pantalla al empezar y feedback inmediato al lograrlo. Si entra durante una ronda, sabe cuánto falta para jugar.

Pasos de funnel habituales: `joined`, `first_round_started`, `first_round_finished`.

## Economía y progresión

Opcional. Si hay moneda, se gana por participar y por desempeño; evita que el que más tiene gane siempre (bola de nieve).

## Brief de niveles

`design.levels: true` para arenas y lobby. Por mapa: cantidad de jugadores para la que está pensado, tiempo para cruzarlo, puntos de aparición y zonas de interés.

## KPIs útiles

- Rondas por sesión y porcentaje que se queda a la segunda ronda.
- Tiempo medio de espera en el lobby.
- Distribución de ganadores: si siempre gana el mismo perfil, hay un problema de balance.

## Errores frecuentes

- Lobby con espera larga o sin nada que hacer.
- Reglas que no se ven en pantalla.
- Estado de ronda que se rompe cuando alguien sale o entra a mitad de partida.
- Mapas pensados para servidor lleno que con pocos jugadores se sienten vacíos.

## Qué no asumir

No hace falta ranking global ni matchmaking. Con un servidor y reglas claras alcanza para un prototipo.
