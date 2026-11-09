# Recompensas aleatorias pagadas

Referencia condicional del skill Developer Products. Verificación documental: 7 de octubre de 2026.

## Política de plataforma

La regla cubre pagos directos en Robux y pagos indirectos con moneda comprable con Robux. Muestra todos los resultados y sus probabilidades numéricas antes del gasto; las probabilidades reales suman 100%. Si redondeas la presentación, sigue la precisión y aclaración admitidas por Roblox. Suerte, pity y otros modificadores pagados requieren explicar su efecto y mostrar probabilidades actualizadas. [Paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items).

Consulta `PolicyService:GetPolicyInfoForPlayerAsync()` y aplica `ArePaidRandomItemsRestricted` en el servidor. Para trading pagado aplica también `IsPaidItemTradingAllowed`. Un jugador restringido no puede usar generadores aleatorios pagados; utiliza una alternativa admitida por la política o deshabilita esa ruta. Si la consulta falla, deshabilita temporalmente la ruta afectada. [PolicyService](https://create.roblox.com/docs/reference/engine/classes/PolicyService).

## Decisiones e implementación

- Registra si cada moneda es comprable con Robux. Una moneda de fuentes mixtas no evita estas reglas por tener también una ruta gratuita.
- Define resultados individuales, pesos, duplicados, pity y conversiones de duplicados en configuración del servidor. La UI recibe la misma distribución efectiva que usa el sorteo.
- Un porcentaje de “legendario” no describe cada resultado si contiene mascotas con probabilidades distintas. Facilita los detalles antes de gastar.
- Cuando las probabilidades cambien por inventario o modificadores, recalcula tanto la distribución del servidor como la información mostrada.
- Usa una operación durable para gasto, resultado y avance de pity. Conserva el resultado elegido al reintentar; un fallo no concede un reroll gratis ni consume dos veces.
- No cambies la distribución mientras hay una operación aceptada en curso. Versiona la tabla aplicada y guarda el resultado, no solo su índice en un catálogo mutable.
- Para recibos que lleguen tras cambiar la elegibilidad, conserva el derecho comprado y aplica una recuperación compatible con la política vigente. No sortees para un usuario restringido ni confirmes un recibo sin entrega válida. Si el producto carece de recuperación, deshabilita nuevas ventas y documenta el bloqueo.
- La animación revela un resultado decidido por el servidor; nunca produce ni valida el premio.

## Validación adicional

- Comprueba suma de probabilidades, resultados alcanzables, distribución por usuario, modificadores y duplicados.
- Simula consulta de política restringida, permitida y fallida; la restricción funciona aunque el cliente invoque el flujo directamente.
- Repite una operación tras fallar el guardado: conserva gasto, resultado y pity sin duplicarlos.
- Usa simulación de muchas tiradas como diagnóstico de distribución, junto a pruebas de cálculo. No la presentes como prueba de cumplimiento o como garantía comercial.

No incorpores trading, apuestas ni premios convertibles a dinero por iniciativa propia. Esas funciones necesitan diseño y revisión específicos.
