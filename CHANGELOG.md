# StarHunt v1.1

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

## Sin publicar

Esto no esta en ningun paquete todavia, y **necesita una version parcheada del
juego**: el sm64coopdx publicado descarta todo contacto entre dos jugadores con
actos distintos antes de que el mod pueda opinar, asi que sobre el juego
publicado el mod se comporta igual que en v1.1.2. La rama que lo permite es
`feature/cross-act-interpolation` en `github.com/dgutson/sm64coopdx`, que sale
de `feature/cross-act-players`; agrega un solo campo y viene apagada de fabrica.
Ese juego se identifica como `v1.5.1-crossact`, asi que no se puede jugar con
alguien que tenga el sm64coopdx normal: la partida se rechaza al entrar en lugar
de desincronizarse.

- Dos jugadores que estan en el mismo curso con estrellas de actos distintos se
  ven, se empujan y se pegan, y cada uno sigue teniendo los objetos de su propio
  acto: el barco hundido de Jolly Roger Bay para quien juega el acto 1, el
  levantado para quien juega otro. El mod ya no esconde a nadie por su acto ni
  le quita el cuerpo.
- El cuerpo del otro jugador se mueve suave. Cuando alguien esta parado sobre
  algo que en tu acto no existe, tu juego ya no intenta adivinar donde cae: lo
  pone donde su dueno dice que esta. A cambio, ese cuerpo va un poco atrasado
  respecto de lo que el otro jugador ve en su pantalla, y no hace ruido de pasos
  ni levanta polvo, porque esos los produce la simulacion que ya no corre.

## v1.1.2 - 17 de septiembre de 2026

Tres correcciones, y nada mas:

- En Wet-Dry World los jugadores ya se ven, se tocan y pelean entre si aunque
  tengan actos distintos.
- En Dire, Dire Docks pasa lo mismo: se ven, se tocan y pelean entre si con
  actos distintos.
- Cuando el mod oculta a otro jugador porque su acto carga otra geometria,
  ahora ademas se atraviesan; antes seguia siendo un cuerpo solido contra el
  que chocar o pararse encima.

El detalle de cada una esta abajo, en los tres puntos fechados 17 de
septiembre dentro de los cambios de v1.1. **Nada mas cambia para el
jugador**, y los numeros que viajan por la red siguen siendo los mismos que
en v1.1 y v1.1.1.

## v1.1.1 - 16 de septiembre de 2026

Primer paquete publicado desde que el mod dejo de ser un solo archivo. **Para
instalarlo hay que descomprimir el zip dentro de `sm64coopdx/mods/`**, de modo
que quede la carpeta completa `mods/StarHunt/`: el juego recorre la carpeta del
mod y `main.lua` resuelve `modules/...` con un `require` relativo a ella, asi
que copiar `main.lua` solo no alcanza.

- En Boss, agarrar a Bowser de la cola detiene sus ataques mientras se lo
  sujeta, y el lanzamiento cuenta como parte del agarre. El detalle esta abajo,
  en el primer punto de los cambios de v1.1.
- **Nada mas cambia para el jugador.** Los modos, los objetivos, los
  modificadores, las dificultades y los puntajes son los mismos que en v1.1, y
  los numeros que viajan por la red no se tocaron, asi que una partida entre
  esta version y v1.1 sigue entendiendose. El resto del trabajo de esta version
  es interno: el mod paso de un archivo a catorce, y las constantes de modo,
  dificultad y color de equipo dejaron de compartir los mismos numeros.

## Cambios de v1.1

- Mantenimiento del 17 de septiembre: en Wet-Dry World los jugadores se ven, se
  tocan y pelean entre sí aunque tengan actos distintos. Nada en ese curso
  depende del acto, y el nivel del agua —lo único en lo que dos jugadores
  podían diferir— se lo pasa el juego a cada uno al entrar al área, así que
  todos ven el mismo.
- Mantenimiento del 17 de septiembre: en Dire, Dire Docks los jugadores se ven,
  se tocan y pelean entre sí aunque tengan actos distintos. El submarino, su
  puerta y los nueve postes aparecen o desaparecen según la partida guardada,
  que es la misma para todos los jugadores de la sesión, así que el curso se ve
  igual desde cualquier acto; lo único que depende del acto es la manta raya.
- Mantenimiento del 17 de septiembre: cuando el mod oculta a otro jugador
  porque su acto carga otra geometría, ahora además se atraviesan. Antes el
  jugador oculto seguía siendo un cuerpo sólido: se chocaba con él y hasta se
  podía quedar parado encima, en el aire. El daño entre los dos ya estaba
  desactivado; lo que faltaba era el contacto. Donde el mod no oculta a nadie
  los jugadores se siguen empujando y pisando como siempre.
- Mantenimiento del 16 de septiembre: en Boss, agarrar a Bowser de la cola
  detiene sus ataques mientras se lo sujeta. Antes seguían saliendo desde su
  propia posición, es decir encima del jugador que lo tenía agarrado, y el
  aturdimiento de una onda vaciaba el mando, soltaba la B y lo dejaba caer. Las
  olas retardadas y los meteoritos ya lanzados tampoco caen durante el agarre.
  El lanzamiento cuenta como parte del agarre: mientras Bowser vuela hacia una
  bomba tampoco ataca, porque quien lo lanzó no puede moverse hasta que caiga.
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
