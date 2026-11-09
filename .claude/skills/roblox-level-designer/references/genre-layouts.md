# Layouts por género

Lee solo la sección del género del juego. Las cifras son puntos de partida para ajustar con pruebas.

## Obby (`linear`)

- Un nivel por etapa, con `start` al inicio y `goal` al final. Los niveles van separados en el espacio; el juego lleva al jugador al siguiente al tocar la meta.
- Vocabulario: saltos planos, subidas, diagonales (más difíciles de medir para el jugador), plataformas angostas, peligros sobre plataformas, plataformas móviles, barras giratorias y escaleras.
- Una mecánica nueva por nivel como máximo; los niveles siguientes la combinan con las conocidas.
- Checkpoint antes de cada tramo exigente. Peligro debajo de todo el recorrido.
- La cámara sigue al jugador desde atrás: evita saltos hacia atrás de la dirección del recorrido o tapados por paredes.

## Rondas y arenas (`arena`)

- Un `spawn` habilitado en el lobby y, en la arena, al menos tantos `spawn` con `enabled: false` como el máximo de jugadores más un margen. El juego los usa al empezar la ronda.
- `zone` con nombre para el lobby, el área de juego y las áreas especiales (por ejemplo `area-monedas`, donde el juego hace aparecer monedas).
- Tamaño: mide el tiempo para cruzar la arena a `walkSpeed` (distancia / velocidad). Para rondas cortas, cruzarla debería llevar pocos segundos; un mapa enorme con pocos jugadores se siente vacío.
- Varios caminos entre zonas, coberturas si hay combate y ningún punto de aparición a la vista directa de otro en juegos de combate.

## Tycoon (`plots`)

- Una `zone` por parcela (`parcela-1`, `parcela-2`…), al menos tantas como el máximo de jugadores del servidor.
- Dentro de cada parcela, posiciones fijas para los botones de compra en el orden de la progresión, con `prop` o `platform` para marcar su lugar. Los objetos que se compran los crea el juego.
- La parcela es visible desde su entrada; el siguiente botón a comprar se ve desde el anterior.
- Separación entre parcelas para que los jugadores no se estorben, y un área común (`zone` `plaza`) cerca del spawn.

## Simulador y hub (`hub`)

- Un hub con el `spawn` habilitado, la tienda y la primera actividad a pocos segundos de caminata.
- Una `zone` por área de recolección (`zona-1`, `zona-2`…), con su requisito de desbloqueo indicado en `note` y en `LEVELS.md`; la puerta o barrera es una `wall` que el juego quita al desbloquear.
- Las zonas más avanzadas, más lejos del spawn pero conectadas por un camino claro.

## Supervivencia por oleadas (`arena`)

- `spawn` habilitado para los jugadores en el centro o en una zona segura.
- Puntos de aparición de enemigos como `zone` con nombre (`enemigos-norte`, `enemigos-sur`…), fuera de la vista inmediata de los jugadores y con al menos dos direcciones de llegada.
- Posiciones defensivas y espacio para moverse; nada de pasillos donde un solo enemigo bloquee al equipo.
- Geometría navegable para los enemigos: rampas suaves, sin huecos que haya que saltar, sin esquinas donde se atasquen. Si el juego usa PathfindingService, deja pasos anchos.
