# Plantilla de `design/ART.md`

Copia esta estructura en `<Juego>/design/ART.md`. Ejemplo completo: [ART.md del obby](../assets/example/ART.md).

```markdown
# Dirección de arte de <Juego>

Fuente: `GDD.md` (concepto y pilares). Tokens: `src/shared/Theme.json` ("<nombre del estilo>"). Verificado con `check_art.py` el <fecha>: <resultado>.

## Intención visual

<Qué siente el jugador al ver el juego y qué ve primero, en pocas frases.>

Pilares visuales:

1. **<Regla corta>.** <Qué decide.>

## Paleta

| Color | Hex | Rol | Uso |
| --- | --- | --- | --- |

## Materiales

| Rol | Material | Por qué |
| --- | --- | --- |

## Iluminación

<Estilo (Soft o Realistic), presets y su intención: hora, tono del ambiente, atmósfera, postprocesado.>

## Tipografía

| Uso | Fuente | Peso |
| --- | --- | --- |

## Estilo de interfaz

<Paneles, esquinas, bordes, espaciado, tamaño táctil mínimo, texto sobre el mundo.>

## Reglas de legibilidad

<Umbrales cumplidos según el validador, señales además del color, pares a revisar en Studio.>

## Para los demás skills

- **Level designer y environment artist:** <colores y materiales por rol; qué nunca usar en zonas seguras.>
- **UI designer y builder:** <tokens de Theme.json mediante Style; nada de colores ni fuentes escritos en el código.>

## Pendientes

<Pedidos a otros skills con el formato del GDD: origen → destino: pedido (estado).>
```
