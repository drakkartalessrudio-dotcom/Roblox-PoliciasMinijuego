# Legibilidad

Un estilo funciona si el jugador lee el juego sin esfuerzo: qué es seguro, qué es peligroso, qué puede tocar y qué dice la interfaz. Estas reglas son las que comprueba `check_art.py` y las que no se pueden comprobar con un script.

## Lo que mide el validador

| Regla | Umbral | Por qué |
| --- | --- | --- |
| Texto sobre su fondo (`text`, `textMuted` sobre `panel`; `textOnAccent` sobre `accent`) | Contraste 4,5:1 | Nivel AA de WCAG para texto normal: se lee en pantallas chicas y con brillo bajo |
| Elementos de UI (`accent`, `danger`, `success` sobre `panel`) | Contraste 3:1 | Nivel AA de WCAG para componentes y texto grande |
| Colores de juego entre sí y contra `surface` | ΔE de 25 o más en visión normal, protanopia, deuteranopia y tritanopia | Alrededor del 8 % de los hombres de origen europeo tiene daltonismo rojo-verde; rojo y verde, o naranja y amarillo, pueden verse iguales |

El contraste es el de WCAG (luminancia relativa). La diferencia de color ΔE es CIE76 en el espacio Lab; la visión con daltonismo se simula con las matrices de Machado, Oliveira y Fernandes (2009) a severidad completa. Los umbrales son puntos de partida: si un par pasa raspando, pruébalo en Studio.

## Lo que el validador no ve

- **El color nunca es la única señal.** Un peligro además brilla (`Neon`), tiene forma propia o se mueve. Un botón además tiene texto o icono.
- **La iluminación cambia los colores.** Un amarillo puede verse naranja bajo un atardecer cálido. Revisa los pares críticos en Studio con el preset aplicado.
- **El texto sobre el mundo 3D** no tiene un fondo fijo: ponlo sobre un panel o con contorno (`UIStroke`).
- **El brillo y el bloom** pueden borrar bordes: el borde de una plataforma debe verse aunque brille la lava de abajo.
- **El tamaño importa más en celulares:** un detalle que en PC se ve, en un teléfono desaparece. Prioriza siluetas claras.

## Ajustes típicos

| Problema | Ajuste |
| --- | --- |
| Texto secundario con poco contraste | Subir la luminosidad de `textMuted` o oscurecer `panel` |
| Peligro y checkpoint parecidos con deuteranopia (naranja y amarillo) | Aclarar el amarillo, llevar el checkpoint a cian o blanco, o hacer la lava más roja y oscura |
| Recompensa que se pierde contra la superficie | Cambiar de tono (por ejemplo, violeta sobre piedra gris) en vez de solo aclarar |
| Todo brilla y nada destaca | Desaturar fondo y superficies; dejar la saturación para los roles de juego |
