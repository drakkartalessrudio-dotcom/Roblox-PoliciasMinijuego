# Supervivencia por oleadas

## Loop

Prepararse, sobrevivir una oleada de enemigos, recibir recompensa, mejorar y enfrentar una oleada más difícil. La partida termina cuando cae el equipo; el regreso viene de llegar más lejos, desbloqueos o cooperación.

## Palancas de diseño

- **Curva de oleadas**: cantidad, vida, velocidad y tipos de enemigo. Subir solo la vida crea "esponjas de daño"; cambia también tipos y comportamientos.
- **Descanso entre oleadas**: tiempo para mejorar y respirar.
- **Mejoras y armas**: decisiones entre opciones, no una mejora obvia.
- **Cooperación**: revivir compañeros, roles o recursos compartidos.
- **Presupuesto de NPCs**: máximo de enemigos simultáneos que el juego soporta con fluidez. Declarado en el GDD; el builder lo respeta.

## Onboarding

La primera oleada es corta y casi imposible de perder: enseña a atacar y muestra la recompensa. El jugador sabe en qué oleada está y cuánto falta para la siguiente.

Pasos de funnel habituales: `joined`, `first_kill`, `wave_1_cleared`.

## Economía y progresión

Moneda por enemigo o por oleada superada, gastada en mejoras durante la partida. Si algo se conserva entre partidas, define qué y cómo afecta al balance de las primeras oleadas.

## Brief de niveles

`design.levels: true` para la arena: puntos de aparición de enemigos fuera de la vista inmediata, varios carriles de llegada, posiciones defensivas y espacio para moverse. Geometría que los enemigos puedan recorrer sin trabarse: rampas suaves y huecos que no requieran saltar.

## KPIs útiles

- Distribución de la oleada alcanzada.
- Muertes por oleada: un pico marca una oleada injusta.
- Duración de partida y porcentaje que juega otra.

## Errores frecuentes

- Oleadas que escalan sin descanso ni variedad.
- Enemigos que se atascan en la geometría.
- Daño calculado en el cliente.
- Demasiados NPCs para el rendimiento del servidor.

## Qué no asumir

No inventes IDs de modelos ni animaciones para los enemigos: si el usuario no los aporta, se construyen con Parts. Armas de fuego, construcción de defensas y jefes son sistemas grandes; van a "posterior" salvo pedido explícito.
