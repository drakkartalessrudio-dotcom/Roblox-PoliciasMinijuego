# Plantilla de `design/ENVIRONMENT.md`

Copia esta estructura en `<Juego>/design/ENVIRONMENT.md`. Ejemplo completo: [ENVIRONMENT.md del obby](../assets/example/ENVIRONMENT.md). `check_environment.py` avisa si un nivel de `Environment.json` no aparece en este documento.

```markdown
# Pase de arte de <Juego>

Fuente: `design/ART.md` y `src/shared/Theme.json` ("<estilo>"), `design/LEVELS.md` y `src/shared/Levels.json`. Datos: `src/shared/Environment.json`. Verificado con `check_environment.py` el <fecha>: <resultado>.

## Referencias y assets del usuario

<Qué referencias dio el usuario y qué se toma de cada una (paleta, materiales, densidad, luz). Assets usados: nombre, tipo, origen, licencia y dónde se usa. Si no hay, "Ninguno: el usuario no aportó referencias ni assets (se preguntó el <fecha>)".>

## Intención

<Lugar, momento y sensación. Qué guía la vista hacia el objetivo.>

## Reglas que se mantienen

<Geometría intacta, colores de juego, alcance de un salto con la física del juego, y cualquier regla propia.>

## Superficies y piezas jugables

| Tipo | Aspecto | Adornos |
| --- | --- | --- |

## Decoración por nivel

| Nivel | Props | Terreno | Luces |
| --- | --- | --- | --- |

## Iluminación y cielo

<Preset de cada nivel, nubes y colores del terreno.>

## Rendimiento

<Piezas y luces del resultado de check_environment.py contra el presupuesto.>

## Revisión visual

<Vistas previas generadas y qué se corrigió por cada punto de la lista de revisión visual; después, lo mismo con las capturas de Studio.>

## Verificación en Studio

<Recorrido, caídas, emulador de teléfono, MicroProfiler y capturas de antes y después.>

## Pendientes

<Pedidos al art director (colores, presets), al level designer (geometría) o al builder (integración), con el formato del GDD.>
```
