# Obby (carrera de obstáculos)

## Loop

Superar un obstáculo, llegar a un checkpoint, enfrentar el siguiente. La sesión se organiza en etapas o niveles; el regreso suele venir de etapas nuevas, récords de tiempo o cosméticos.

## Palancas de diseño

- **Vocabulario de obstáculos**: saltos, plataformas móviles, peligros que matan, timing, escaladas, caminos angostos. Cada etapa introduce o combina uno.
- **Ritmo**: tensión y alivio. Después de un tramo difícil, uno corto y fácil.
- **Castigo**: volver al último checkpoint. Cuanto más lejos está, más pesa cada error.
- **Progreso visible**: "Etapa 4/10" y el nombre de la etapa. Un obby sin indicador de progreso parece infinito.

## Onboarding

La primera etapa enseña a saltar sin castigar: saltos cortos, plataformas anchas, caída a un piso seguro o checkpoint inmediato. El primer peligro aparece solo, con un color inconfundible, antes de combinarlo con saltos. El primer checkpoint llega en segundos.

Pasos de funnel habituales: `joined`, `first_checkpoint`, `level_1_complete`.

## Economía y progresión

Muchos obbies no tienen moneda: el progreso son las etapas. Si se agregan monedas para cosméticos, que no permitan saltar la dificultad gratis. Saltar etapa con Robux es un Developer Product con sus propias reglas de entrega.

## Brief de niveles

`design.levels: true`. Por etapa: mecánica nueva, dificultad buscada, tiempo esperado y checkpoint al inicio. Indica la física del personaje: los saltos de las primeras etapas deben quedar bien por debajo del alcance máximo, y el level designer valida cada salto contra la física declarada.

## KPIs útiles

- Embudo de progresión por etapa: el porcentaje que completa cada una muestra los picos de dificultad.
- Muertes por etapa: un pico aislado suele ser un obstáculo injusto, no difícil.
- Tiempo por etapa contra el esperado.

## Errores frecuentes

- Dificultad que sube demasiado pronto o sin descansos.
- Saltos a ciegas, cámara tapada o peligros que no se distinguen del suelo.
- Checkpoints muy espaciados, que convierten un error en minutos perdidos.
- Etapas iguales con colores distintos: variedad aparente sin decisiones nuevas.

## Qué no asumir

No todo obby necesita monedas, tienda ni ranking. No subas la velocidad o el salto sin revisar todos los niveles: cambian qué saltos son posibles.
