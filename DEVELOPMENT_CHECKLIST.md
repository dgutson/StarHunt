# StarHunt — nota de desarrollo obligatoria

**Estado del proyecto: FINALIZADO. Versión final: v1.1 (2026-07-30).**

No hay versiones nuevas planificadas. Solo se aceptan actualizaciones de
mantenimiento sobre v1.1. Este documento conserva el historial técnico y las
limitaciones conocidas de la versión final.

Esta nota debe revisarse **antes de programar cualquier cambio** en StarHunt.
Su objetivo es evitar arreglos rápidos que rompan HUD, guardado, red, OMM o
una estrella ya probada.

## Proceso obligatorio antes de editar

1. Escribir el cambio pedido en `Cambios pendientes`.
2. Identificar qué sistema toca usando `Mapa del código`.
3. Revisar `Errores conocidos y decisiones` para no reintroducir un fallo.
4. Decidir una solución concreta y anotar por qué respeta multijugador,
   guardado y mods compatibles.
5. Añadir o modificar una prueba en `work/starhunt_v11_load_test.lua` antes de
   instalar.
6. Ejecutar compilación Lua y la prueba completa.
7. Instalar solamente si ambas pruebas pasan y comprobar que la copia instalada
   coincide con la fuente.

## Cambios pendientes

- **2026-08-04 — reserva de bombas de Boss (implementado):** evitar que Hard y
  Nightmare queden sin forma de terminar la pelea cuando desaparecen las cinco
  bombas originales de Bowser in the Sky. El host debe confirmar primero que
  las cinco bombas nativas llegaron a cargarse y, cuando su contador llegue a
  cero, crear una sola oleada sincronizada en posiciones originales elegidas
  sin repetir: dos bombas en Hard y cuatro en Nightmare. Easy y Medium no deben
  crear bombas adicionales. Dos campos globales sincronizados conservarán el
  avistamiento y la oleada ante entradas tardías o un cambio de host.

- **2026-08-04 — Pulsos Easy y parejas Nightmare (implementado):** corregir el
  reinicio tardío que reduce a un solo fotograma las restricciones pulsadas de
  Easy; hacer simétrica la validación de parejas para que invertir el orden no
  permita efectos que se cancelan; y excluir combinaciones donde un reto obliga
  a detenerse mientras otro castiga hacerlo. La solución solo toca estado local
  de modificadores y selección autoritativa del host, sin cambiar objetivos,
  puntuación, guardado ni la cantidad de retos.

- **2026-08-01 — Retos redundantes y congelación estable (implementado):** sustituir
  `landing_stun`, que inmoviliza después de casi cada salto y se solapa con
  `periodic_freeze`, por un reto de monedas mecánicamente distinto. Durante la
  congelación periódica también se fijará la orientación de Mario antes y
  después del moveset para impedir giros residuales. Se conservarán los 32
  modificadores, la dificultad independiente y la auditoría por estrella; se
  añadirán regresiones directas antes de instalar.

- **2026-07-31 — Apertura obligatoria del menú de espera (implementado):** abrir el menú de
  StarHunt automáticamente cuando todavía no existe una ronda activa, consumir
  B/START y cualquier intento de alternarlo mientras se espera, y cerrarlo para
  todos cuando comience la ronda. Si la ronda termina, el menú debe reaparecer.
  La solución conserva el bloqueo existente de movimiento y el control del host;
  no modifica objetivos, balance, guardado, red ni compatibilidad de modos.

## Mapa del código

| Sistema | Responsabilidad | Zona principal de `main.lua` |
|---|---|---|
| Objetivos | Lista de estrellas, mundo, acto, poder y retos | `GOALS` |
| Auditoría | Acepta/rechaza cada reto para cada estrella | `goal_traits`, `audit_modifier`, `rebuild_audited_modifiers` |
| Ronda normal | Asigna objetivos, puntos, ganador y retornos | `host_start_round`, `host_update_round`, `host_end_round` |
| Retos | Aplica el modificador personal del jugador local | `apply_local_modifier` |
| Gorras | Da Wing/Metal/Vanish sin borrar poderes externos | `apply_goal_power`, `restore_starhunt_power` |
| Guardado | Quita solo la bandera temporal de la estrella obtenida | `save_course_index_for`, `remove_starhunt_save_flag` |
| Boss | Vida de Bowser, ventajas, ataques y reaparición | `host_update_boss_round`, `apply_boss_hazards` |
| Privacidad/PvP | Oculta jugadores con geometría o área incompatible | `players_have_private_variant`, `players_can_share_world` |
| Lobby | Agua, puertas, Lakitu y retorno al castillo | `keep_moat_lowered`, `on_allow_interact`, `remove_castle_lakitu` |
| HUD y menú | Marcadores, timer, salud, menú `/starhunt` | `draw_hud`, `draw_player_health_bar`, `draw_config_menu` |

## Arquitectura añadida en v1.0

### Revisión v1.1

- v1.1 parte de la fuente final verificada de v1.0 y no modifica ese respaldo.
- `/starhunt updates` explica el propósito del mod, los cuatro modos, la
  independencia de la dificultad y los cambios principales de v1.1.
- El comando informativo usa el mismo registro `/starhunt`; no añade entradas
  duplicadas a `/help`.
- La prueba inicia las 16 combinaciones de cuatro modos por cuatro dificultades
  y comprueba sus invariantes principales.
- Los textos del comando se comprueban en los seis idiomas.

- `Team.CHAOS` es eliminación todos contra todos: no asigna estrellas y gana el
  último jugador vivo.
- El host elige uno de los 15 mundos principales y un acto al azar. Todos son
  enviados al mismo nivel, área y variante para que el PvP sea posible.
- En Chaos cada jugador recibe sus propios modificadores, que cambian cada 15
  segundos. Easy, Normal y Hard asignan uno; Nightmare asigna dos distintos y
  compatibles por jugador.
- En Normal y Team, Nightmare asigna dos modificadores compatibles a cada
  jugador. En Boss asigna dos modificadores de jugador, conserva las tres
  ventajas de Bowser y mantiene sus 9 puntos de vida.
- Las estrellas quedan ocultas e inusables. Morir marca al jugador como
  eliminado y lo envía al castillo como espectador.
- CHAOS requiere al menos dos jugadores. Las entradas tardías son espectadores
  y no pueden atacar ni recibir ataques.
- `sh5_difficulty` sincroniza Easy, Medium, Hard o Nightmare. El valor queda
  bloqueado mientras una ronda está activa.
- `Team.effective_modifier_for_goal()` aplica la dificultad y vuelve a pasar el
  resultado por la auditoría de la estrella. Una dificultad nunca debe saltarse
  los filtros mecánicos ni los márgenes numéricos.
- Normal conserva los valores de v0.9. Easy convierte restricciones binarias en
  pulsos de tres segundos; Hard y Nightmare aumentan presión, daño y frecuencia.
- Boss usa 3/5/7/9 puntos de vida según dificultad y acelera sus ataques en Hard
  y Nightmare.
- Los idiomas locales son inglés, español, portugués de Brasil, francés, alemán
  e italiano. Cambiar idioma nunca modifica el estado sincronizado de la ronda.
- Los nombres propios de estrellas sin traducción segura conservan el texto
  original de SM64; menú, dificultad, modos y modificadores sí se localizan.

## Errores ya encontrados y solución que no se debe deshacer

| Problema | Causa | Solución actual | Comprobación |
|---|---|---|---|
| Estrellas guardadas o borrado del curso equivocado | Curso de juego es 1-based; guardado es 0-based | `save_course_index_for()` resta 1 | La prueba verifica el índice correcto |
| Lakitu reaparecía | Se comparaban símbolos C no disponibles en Lua | Usar `id_bhvCameraLakitu` | Prueba de borrado por behavior ID |
| Gorras desaparecían o quedaban permanentes | Estado de StarHunt y de otros mods se mezclaba | Guardar timer, flags propios y cap externa | Pruebas de cambio de gorra y gorra externa |
| Vidas quedaban en 99 | No se restauraba el valor previo | Guardar vidas al empezar y restaurar al terminar | Prueba de vidas |
| HUD de otro mod se mostraba de nuevo | StarHunt siempre llamaba a `hud_show()` | Recordar si estaba oculto antes de la ronda | Prueba de HUD oculto |
| Ataques de Bowser se perdían con lag | Solo existía el último ataque sincronizado | Cola circular de 8 ataques | Prueba de dos ataques juntos |
| Ráfagas/congelación se omitían | Dependían de un frame exacto | Usar número de ciclo, no igualdad exacta | Pruebas de salto de temporizador |
| Jugadores se veían entre subzonas | Solo se comparaba el nivel | Comparar también `currAreaIndex` | Prueba de áreas distintas |
| Retos imposibles | B o Z necesarios, rutas precisas o espera | Auditoría de cuatro etapas y ajustes por estrella | Matriz de 2.232 pares |
| Piso Maldito injusto en ascensores | Temporizador demasiado corto en plataformas lentas | 9 segundos en rutas de plataforma | Prueba de HMC/LLL/WDW |

## Historial heredado del tercer piso

Objetivo: añadir **Tick Tock Clock** y **Rainbow Ride**, seis estrellas por
curso y sin las de 100 monedas. El total pasará de 75 a 87 objetivos.

1. Añadir ambos mundos y sus 12 objetivos, con títulos inglés/español.
2. Marcar las rutas con espera, precisión, plataformas, vuelo, cañón y botones
   requeridos antes de elegir retos.
3. Ejecutar de nuevo las cuatro etapas de auditoría **solo para las 12 nuevas
   estrellas**, además de mantener la matriz global.
4. Probar visualmente cada reto candidato: plataformas de TTC, péndulos,
   agujas, alfombra mágica, barco y secciones de Rainbow Ride.
5. Rechazar combinaciones que pidan esperar quieto, dependan de un salto
   perfecto o requieran un botón bloqueado.
6. Añadir pruebas automáticas para los casos mecánicos conocidos; lo que no se
   pueda simular se marca para prueba humana.
7. Actualizar límites de tiempo según 87 estrellas y hasta 16 jugadores.

### Riesgos específicos del tercer piso

- **TTC:** tiempos variables, péndulos y plataformas pueden hacer injustos
  Piso Maldito, Sigue Moviéndote, Congelación, Gravedad Alta y controles
  alterados.
- **Rainbow Ride:** alfombra mágica, barco, cañones y vuelo hacen sensibles
  los retos de velocidad, saltos limitados, viento y control aéreo.
- Ninguna estrella debe aprobarse solo porque el código no falla: debe tener
  una ruta humana con margen de error.

## Mejora futura del HUD

Problema reportado: algunos símbolos `:` vuelven a verse como `X` porque la
fuente HUD de Mario 64 no tiene un dos-puntos normal.

Solución obligatoria:

1. No imprimir `:` directamente con `FONT_HUD`.
2. Dibujar los dos puntos como dos `.` pequeños, como ya hace el timer.
3. Buscar todo texto HUD nuevo que incluya `:` (timer, estado, saltos, vida,
   Boss, menú y mensajes).
4. Verificar en una partida real a resolución normal y pantalla ancha.

## Historial de cambios cerrados

| Pedido | Solución propuesta | ¿Confirmada? | Pruebas necesarias |
|---|---|---:|---|
| Tercer piso | TTC + RR, 12 estrellas sin 100 monedas | Implementado; falta prueba humana | Auditoría nueva + prueba humana |
| Big Boo's Haunt | Seis estrellas normales; los jefes conservan B y las rutas precisas se auditan | Implementado; falta prueba humana | Auditoría BBH + prueba humana |
| Borrado inmediato al terminar | Host limpia al cerrar; cada cliente limpia al recibir la orden de volver al lobby | Implementado | F12 + retorno global tardío |
| HUD sin `X` | Render común que convierte `:` en dos puntos dibujados | Implementado | HUD normal, Boss y menú |
| Menú repetía acciones al mantener un botón | Detectar pulsaciones nuevas con un registro propio hasta soltar el botón | Implementado | Mantener dirección/A varios frames y exigir una sola acción |
| Nombre del mod con colores seguros | Amarillo para Star, celeste para Hunt, blanco para v1.1 y cierre en gris predeterminado | Implementado | Validar encabezado exacto, longitud, sintaxis y carga |
| Movimiento residual con menú abierto | Anular velocidad horizontal, velocidad de deslizamiento e impulso frontal | Implementado | Abrir menú con impulso activo y exigir velocidad horizontal cero |
| Cambio de personaje durante TEAM | Asociar la paleta guardada a la identidad del modelo y no restaurarla sobre otro personaje | Implementado | Cambiar modelo antes y después de una actualización de paleta |
| Asignación TEAM tras desconexiones | Equilibrar jugadores conectados y, con empate numérico, ayudar al equipo que pierde por 2+ puntos | Implementado | Reserva desconectada, diferencia de 1 punto y diferencia de 2 puntos |
| Compatibilidad con mods populares | Mantener HUD de Day/Night y Gun Mod sobre DARKNESS PULSE, impedir fuego aliado de sus balas, coordinar el menú de WiddlePets y reaplicar límites seguros tras movesets personalizados | Implementado; falta prueba humana | Capas HUD, bala aliada/rival/Boss/área privada, exclusión de menús y límites posteriores al moveset |
| `/help` repetía StarHunt tres veces | Registrar únicamente el comando exacto y en minúsculas `/starhunt` | Implementado | Exigir un solo registro llamado `starhunt` |
| Revisión integral y HUD nocturno | Separar marcador, reloj, objetivo y vida en paneles legibles; sustituir la barra de vida por ocho segmentos; corregir solamente fallos demostrables sin cambiar reglas de balance | Implementado; Normal panorámico verificado dentro del juego | Geometría y colores del HUD, 0/1/4/7/8 de vida, Normal/Boss/TEAM, textura opaca, 30 regresiones completas y prueba visual Normal 1920x1009 |
| StarHunt v0.9 | Añadir ocho modificadores auditados; completar el menú español; inmovilizar por completo al jugador mientras el menú está abierto; permitir que aliados y rivales se vean al coincidir en nivel y área durante TEAM; reforzar la identificación azul/roja usando todas las partes de paleta que admite el motor | Implementado y automatizado; falta prueba humana. Los botones amarillos fijos del modelo no son una parte de paleta expuesta por Lua | Matriz ampliada, efectos aislados, posición/velocidad del menú, texto español, visibilidad, PvP, paleta y restauración |
| Posición final del objetivo | Restaurar la composición compacta de v0.7: nivel, estrella y modificador centrados directamente en la parte superior, sin una tarjeta que ocupe casi toda la pantalla; escalar dentro del espacio entre los paneles laterales | Implementado y automatizado; la captura real confirmó el fallo anterior y falta validar visualmente la corrección | Normal, TEAM, Boss, 320 y 426 unidades; comprobar textos en `y = 3/15/28/40`, centrados y sin panel de objetivo |
| COIN TOLL rehabilitaba una estrella incorrecta | Recordar por jugador que un objeto de estrella ya fue rechazado para el objetivo y ronda actuales, y mantenerlo bloqueado aunque después se pague el peaje o cambien sus parámetros sincronizados | Implementado y automatizado; falta prueba humana | Rechazar estrella incorrecta antes de 20 monedas, mutar su ID, pagar el peaje y exigir que siga bloqueada; la estrella asignada debe habilitarse |
| Retiro de v0.7 y v0.8 | Eliminar sus fuentes, instalaciones y pruebas auxiliares sin tocar v1.0 | Implementado | Verificar que no quede ninguna ruta o archivo de esas versiones |
| Comando de novedades v1.1 | Usar `/starhunt updates` para explicar mod, modos, dificultad y cambios sin crear otra entrada en `/help` | Implementado | Comando, alias, texto y seis idiomas |
| Cierre del proyecto | Eliminar v0.9, conservar v1.0 como respaldo y declarar v1.1 como versión final | Implementado | Ausencia de v0.9, hashes de v1.0/v1.1 y documento de estado |
| Botón Otro nivel | Añadirlo al menú de pausa de SM64CoopDX, limitarlo a Normal/Team, exigir dos minutos por objetivo y escoger otro curso | Implementado y automatizado; falta prueba visual | Entrada tardía, 1:59.29, 2:00, doble pulsación, curso distinto, reinicio del temporizador, Boss/Chaos |

## Correcciones de estabilidad posteriores

| Problema | Solucion aplicada | Estado |
|---|---|---:|
| Retos antes de llegar | Activar reto y gorra solo cuando nivel, acto y area coinciden | Implementado |
| Agua invisible global | Conservar la altura hallada y bajar solo las regiones reales del foso | Implementado |
| Reconexiones mezcladas | No reutilizar el slot si el nombre del jugador cambio | Implementado |
| Bowser se curaba | La vida autoritativa solo puede bajar durante una ronda | Implementado |
| Ataques diferidos perdidos | Guardar ondas y meteoritos en colas independientes | Implementado |
| Un cuadro de animacion de muerte | Cancelar acciones mortales antes de que comiencen | Implementado |
| Menu filtraba controles | Consumir todos los botones, camara y stick mientras esta abierto | Implementado |
| HUD ajeno modificado | Guardar y restaurar flags solo al entrar y salir de una ronda | Implementado |
| Lakitu ya cargado | Escaneo periodico ademas de `HOOK_ON_OBJECT_LOAD` | Implementado |
| BBH incompatible | Aislar actos distintos solo dentro de habitaciones | Implementado |
| Lobby grande sin objetivos | Reducir el maximo de tiempo entre 8 y 16 jugadores | Implementado |
| Objetivo centrado en la zona superior | Texto compacto de v0.7 sin tarjeta; reservar las esquinas para puntuación, vida y reloj; ancho adaptativo limitado al hueco central | Implementado |
| COIN TOLL aceptaba una estrella rechazada previamente | Registrar el rechazo por objeto, jugador, objetivo y ronda; limpiarlo al recargar el nivel | Implementado |
| Mario podía rotar durante Congelación Periódica | Capturar su orientación al congelarse y reaplicarla después del moveset; liberarla al finalizar el efecto | Implementado |
| Aturdimiento al aterrizar repetía otra inmovilización | Sustituirlo por Impulso de moneda, auditar su velocidad y evitar parejas Nightmare que anulan el impulso | Implementado |
| Restricciones Easy duraban un solo fotograma | Inicializar la clave y el reloj del reto antes de comprobar su ventana pulsada | Implementado |
| Slippery Easy recuperaba velocidad de un pulso anterior | Limpiar la inercia privada durante cada intervalo inactivo | Implementado |
| Parejas Nightmare dependían del orden | Consultar los conflictos de ambos modificadores y probar las 496 parejas en ambos sentidos | Implementado |
| Nightmare podía obligar a detenerse y castigar esa detención | Incompatibilizar Congelación con Sigue moviéndote y Piso maldito; aplicar el filtro también en Boss | Implementado |
| Hard/Nightmare podían agotar las cinco bombas antes de derrotar a Bowser | Tras observar y agotar las cinco nativas, crear una sola reserva sincronizada de 2/4 bombas en posiciones originales aleatorias y distintas | Implementado |

## StarHunt v0.9 — TEAM

- `MODE_TEAM` conserva objetivos individuales, pero suma resultados por equipo.
- `starhunt_lifetime_stars` es local, permanente y no aparece en pantalla.
- Los equipos se equilibran por experiencia y nunca difieren en más de una persona.
- Los participantes desconectados conservan puntuación y objetivo, pero no
  ocupan una plaza activa al asignar jugadores nuevos.
- Una reconexión recupera su equipo anterior si el balance activo y una
  desventaja de dos o más puntos no requieren asignarla al otro equipo.
- `sh5_team` debe sobrevivir reconexiones y limpiarse al terminar.
- El fuego amigo se bloquea; los rivales requieren mundo y geometría compatibles.
- Las ocho partes de la paleta se guardan, pintan y restauran exactamente.
- TEAM no puede iniciar con menos de dos jugadores.
- Los nuevos retos pasan por la misma matriz de auditoría de cuatro etapas.

## Verificación histórica de v0.9

- 93 objetivos y 32 modificadores.
- 2.976 pares auditados: 2.222 aprobados y 754 rechazados.
- Los ocho efectos nuevos tienen pruebas mecánicas directas.
- El menú español, el bloqueo de posición XYZ y la velocidad vertical están
  cubiertos.
- TEAM permite visibilidad/PvP entre actos distintos al coincidir en nivel y
  área, mantiene el fuego amigo bloqueado y conserva el aislamiento entre
  áreas.
- La cobertura heredada de v0.8 permanece integrada en la prueba de v1.1; las
  copias y pruebas independientes de v0.8 fueron retiradas por solicitud.
- La prueba humana dentro del juego sigue siendo necesaria para dificultad,
  apariencia, geometría entre actos y modelos personalizados.

Las fuentes, instalación y prueba independiente de v0.9 fueron eliminadas al
cerrar el proyecto. Su comportamiento heredado permanece integrado en v1.1.

## Verificación automatizada de v1.1

- `lua -e "assert(loadfile('StarHunt_v1.1/main.lua'))"` pasa.
- `lua work/starhunt_v11_load_test.lua` pasa completo.
- La prueba conserva los flujos heredados Normal, Boss y Team.
- Las cuatro dificultades se prueban sobre el catálogo y conservan la auditoría
  heredada de 2.976 pares estrella/modificador en Normal y Team.
- Cada dificultad conserva modificadores personales válidos para Chaos.
- Se prueban mapa y acto compartidos, ausencia de estrella, un modificador
  personal por jugador en Easy/Normal/Hard, dos por jugador en Nightmare,
  incompatibilidades, renovación a 15 segundos y contador de saltos.
- Se prueban eliminación, espectador tardío, bloqueo de estrellas, PvP exclusivo
  entre supervivientes y victoria del último jugador vivo.
- Se verifica que Nightmare pueda formar una pareja compatible en los 93
  objetivos y que Normal, Team, Boss y Chaos reciban el modificador adicional.
- Se prueban los cuatro idiomas añadidos en el menú.
- Se prueban las 16 combinaciones de modo y dificultad.
- `/starhunt updates` conserva una sola entrada en `/help` y se prueba en los
  seis idiomas.
- El menú de pausa registra un solo botón `Otro nivel`; el host valida los dos
  minutos, evita el curso anterior y reinicia el temporizador al reasignar.
- Se prueba que Normal conserva valores, Easy pulsa restricciones y Nightmare
  eleva la vida de Bowser a 9.
- Se prueba que una arena todavía sin cargar no activa la reserva; Nightmare
  crea cuatro bombas y Hard dos, sin repetir posiciones originales, sin una
  segunda oleada y sin alterar Medium.
- SHA-256 de `main.lua`:
  `EBC76DBEC1554D24522E907B49FF2DE5948282029E95C6DA51C31B42A906B883`.
- Fuente e instalación de v1.1 coinciden por SHA-256. v1.0 permanece intacta
  como respaldo; v0.9 fue eliminada al finalizar el proyecto.
- Estas comprobaciones no sustituyen una prueba visual y de red dentro de
  SM64CoopDX.
- Se prueba al menos una ronda Normal y una Boss si el cambio toca red, HUD,
  gorras, muerte o retorno.
