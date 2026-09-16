# StarHunt v1.1

**Versión final del proyecto — desarrollo cerrado el 30 de julio de 2026.**

## ¿De qué se trata?

StarHunt convierte SM64CoopDX en una colección de desafíos multijugador con 93
objetivos, 32 modificadores auditados, cuatro modos de juego y cuatro niveles
de dificultad.

## Modos

- **Normal:** carrera individual para completar objetivos y sumar estrellas.
- **Team:** carrera por equipos rojo y azul con balance de jugadores.
- **Boss:** todos cooperan contra Bowser con vida y ataques sincronizados.
- **Chaos:** todos contra todos en un mapa compartido; gana el último jugador
  vivo y cada participante recibe modificadores personales.

## Dificultad

Easy, Normal, Hard y Nightmare son una configuración independiente del modo.
Nightmare añade un modificador compatible adicional a cada modo y Boss conserva
su configuración especial de vida.

## Cambios de v1.1

- Mantenimiento del 16 de septiembre: en Boss, agarrar a Bowser de la cola
  detiene sus ataques mientras se lo sujeta. Antes seguían saliendo desde su
  propia posición, es decir encima del jugador que lo tenía agarrado, y el
  aturdimiento de una onda vaciaba el mando, soltaba la B y lo dejaba caer. Las
  olas retardadas y los meteoritos ya lanzados tampoco caen durante el agarre.
  Al soltarlo, la pelea sigue un segundo después.
- Mantenimiento del 4 de agosto: Boss conserva sus cinco bombas originales y,
  después de que el host confirme que todas se agotaron, recibe una única
  reserva sincronizada en posiciones originales aleatorias y distintas: dos
  bombas en Hard y cuatro en Nightmare. Una espera de un segundo evita confundir
  la carga del escenario o un cambio de host con una arena vacía. Easy y Medium
  no cambian.
- Mantenimiento del 4 de agosto: las restricciones pulsadas de Easy conservan
  ahora su ventana completa; antes el primer fotograma activo reiniciaba el
  reloj y apagaba los siguientes.
- Slippery Easy ya no recupera la velocidad guardada por una pulsación anterior.
- Las parejas Nightmare se comprueban en ambos órdenes. Se bloquearon las
  cancelaciones entre Control Pulse y controles espejo, además de Congelación
  con Sigue moviéndote o Piso maldito. Boss usa el mismo filtro.
- Mantenimiento del 1 de agosto: `Landing Stun` fue retirado por repetir la
  inmovilización de `Periodic Freeze` después de cada salto. Lo reemplaza
  **Coin Surge / Impulso de moneda**, que da un empujón controlado al recoger
  monedas y se excluye de rutas donde ese impulso sería injusto.
- `Periodic Freeze` ahora conserva el ángulo del personaje antes y después del
  moveset; ya no permite que Mario rote mientras está congelado y libera el
  ángulo al terminar los 24 fotogramas.
- Nightmare evita combinar Coin Surge con Speed Cap, Slow Pulse o Coin Weight,
  porque el resultado dependía del orden de ejecución y podía anular el reto.
- Actualizacion de mantenimiento: el menu se abre automaticamente mientras se
  espera una ronda, no puede cerrarse con B, START ni `/starhunt`, se cierra
  para todos al comenzar y reaparece al terminar.
- Nuevo comando `/starhunt updates`.
- Explicación del mod, modos, dificultad y novedades en los seis idiomas.
- Una sola entrada `starhunt` en `/help`.
- Verificación automática de las 16 combinaciones entre modo y dificultad.
- Conservación de las correcciones de modificadores personales de Chaos y
  segundo modificador de Nightmare.
- Preferencia de idioma propia de v1.1 con migración desde v1.0.
- Botón **Otro nivel** en `Pausa > Mods > StarHunt` durante Normal y Team.
- El botón exige dos minutos desde la asignación, muestra la cuenta regresiva,
  elige un curso distinto y reinicia la espera tras utilizarse.

Estas pruebas no sustituyen una partida visual y multijugador dentro de
SM64CoopDX.

v1.0 permanece como respaldo. Las versiones v0.7, v0.8 y v0.9, junto con sus
pruebas independientes, fueron retiradas.
