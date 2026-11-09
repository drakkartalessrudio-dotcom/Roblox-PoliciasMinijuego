# Niveles de PlazaYTorre

Física: walkSpeed 16, jumpHeight 7,2, gravedad 196,2 (alcance en plano 9,67 studs). Cada nivel declara su `place`: los places son mundos aparte, así que la plaza y el primer tramo de la torre comparten coordenadas sin superponerse. Validado con `validate_levels.py`: 0 errores, 0 advertencias.

## plaza (place plaza)

Plaza de 60 × 60 studs con muros bajos. El jugador aparece al sur, de frente al portal: un arco con la zona `portal:torre`, que lleva al place torre.

## torre-1 (place torre)

Primer tramo, dificultad 2: tres saltos cortos que suben de a un stud sobre lava. La salida es el único spawn del place.

## torre-2 (place torre)

La cima, dificultad 4: tres saltos con un desvío lateral. La meta devuelve a la plaza.
