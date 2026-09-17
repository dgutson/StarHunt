# StarHunt — nota de desarrollo obligatoria

Esta nota debe revisarse **antes de programar cualquier cambio** en StarHunt.
Su objetivo es evitar arreglos rápidos que rompan HUD, guardado, red, OMM o
una estrella ya probada.

Este documento contiene solo lo que sigue vigente. El historial de versiones
cerradas, las verificaciones antiguas y los cambios ya implementados están en
`HISTORY.md`. El trabajo pendiente está en `ROADMAP.md`.

## Proceso obligatorio antes de editar

1. Escribir el cambio pedido en `ROADMAP.md` (un ítem con What/Why/Outcome).
2. Identificar qué sistema toca usando `Mapa del código`.
3. Revisar `Errores ya encontrados y solución que no se debe deshacer` para no
   reintroducir un fallo. Varias de esas soluciones parecen código redundante y
   no lo son.
4. Decidir una solución concreta y anotar por qué respeta multijugador,
   guardado y mods compatibles.
5. Añadir o modificar una prueba en `test/` **antes** de instalar.
6. Ejecutar las comprobaciones. Los comandos y las cifras de referencia viven en
   la **habilidad `starhunt-testing`** (`.claude/skills/starhunt-testing/SKILL.md`),
   que es la única copia: repetirlas aquí garantiza que una de las dos quede
   desfasada. **Cualquier subida sobre esas cifras es una regresión.**
7. Mutar el código cambiado y comprobar que la prueba lo detecta; la habilidad
   explica cómo. Estar publicado en `STARHUNT_TEST_API` **no** significa estar
   probado: ocho veces una función publicada resultó no tener ni una sola prueba
   que la llamara.
8. Instalar solamente si todo pasa. Copiar la **carpeta `StarHunt/` entera**, no
   `main.lua` solo, y comprobar que la copia instalada coincide con la fuente.

El paso 5 nombraba `work/starhunt_v11_load_test.lua`, un arnés que nunca estuvo
en este repositorio y no existe en esta máquina. `test/` es su reemplazo.

## Regla adicional para cambios que solo mueven código

Un traslado byte a byte no puede deshacer una solución de la tabla de abajo,
pero sí puede romperla si el traslado no es exacto. Para esos cambios, además
de los ocho pasos:

- Demostrar que las líneas movidas son idénticas byte a byte, en las dos
  direcciones: el cuerpo del módulo contra las líneas extraídas, y el
  `main.lua` reconstruido desde el commit anterior contra el archivo nuevo.
- Mutar el código movido y comprobar que la prueba lo detecta. Una ejecución
  verde no demuestra que el traslado sea correcto; en veintiuno de los veinticuatro
  traslados ya hechos la mutación encontró un área sin ninguna cobertura.
  Calcular el rango de líneas **después** de la última edición del archivo: un
  rango calculado antes queda desplazado por las líneas añadidas.
- Volver a comparar el módulo contra su original **justo antes** de hacer
  commit. Una vez quedó una mutación aplicada y la prueba siguió pasando.

## Mapa del código

`main.lua` ya está dividido en `StarHunt/modules/`. La columna «Zona» nombra
el módulo; lo único que sigue en `main.lua` es la limpieza del vestíbulo, y el
motivo está en el apéndice de `REFACTOR_PLAN.md`.

| Sistema | Responsabilidad | Zona |
|---|---|---|
| Objetivos | Lista de estrellas, mundo, acto, poder y retos | `modules/goals.lua` (`GOALS`) |
| Reclamo de estrella | Qué estrella cuenta, y oculta las demás | `modules/goals.lua` (`on_allow_interact`, `on_interact`, `update_star_visibility`) |
| Auditoría | Acepta/rechaza cada reto para cada estrella | `modules/audit.lua` (`goal_traits`, `audit_modifier`, `rebuild_audited_modifiers`) |
| Dificultad | Escala cada reto y vuelve a auditarlo | `modules/difficulty.lua` (`effective_modifier_for_goal`) |
| Ronda normal | Asigna objetivos, puntos, ganador y retornos | `modules/round.lua` (`host_start_round`, `host_update_round`, `host_end_round`; el lado cliente, `local_goal_warp_update` y `force_return_to_lobby`) |
| Retos | Aplica el modificador personal del jugador local | `modules/modifiers.lua` (`apply_local_modifier`) |
| Gorras | Da Wing/Metal/Vanish sin borrar poderes externos | `modules/goals.lua` (`apply_goal_power`, `restore_starhunt_power`) |
| Guardado | Quita solo la bandera temporal de la estrella obtenida | `modules/save.lua` (`save_course_index_for`, `remove_starhunt_save_flag`) |
| Boss | Vida de Bowser, ventajas, ataques y reaparición | `modules/boss.lua` (datos, vida, cola de ataques, `apply_boss_hazards`, la oleada de bombas de reserva y `ensure_boss_health_owner`); `modules/round.lua` (`host_update_boss_round`, y del lado cliente `local_boss_warp_update` y `on_before_boss_cutscene`) |
| Chaos | Mapa, reroll de modificadores y eliminación | `modules/chaos.lua`; `modules/round.lua` (`host_update_chaos_round`) |
| Team | Equipos, paletas y PvP | `modules/team.lua` |
| Idiomas | Seis idiomas de interfaz y su persistencia | `modules/i18n.lua` (`translated`) |
| Privacidad/PvP | Oculta jugadores con geometría o área incompatible, y les quita el contacto | `modules/goals.lua` (`players_have_private_variant`, `players_can_share_world`, y la rama `INTERACT_PLAYER` de `on_allow_interact` con `player_index_of_body`) |
| Lobby | Agua, puertas, Lakitu y retorno al castillo | `modules/goals.lua` (`on_allow_interact`); `modules/modifiers.lua` (`keep_moat_lowered`); `main.lua` (`skipIntro`, `remove_castle_lakitu`, `remove_existing_castle_lakitu`, `on_find_water_level` — se quedan ahí a propósito; el motivo está en el apéndice de `REFACTOR_PLAN.md`) |
| HUD y menú | Marcadores, timer, salud, menú `/starhunt` | `modules/menu.lua` (opciones, selección y `/starhunt`); `modules/hud.lua` (`draw_hud_text`, `measure_hud_text`, contadores nativos, DARKNESS PULSE, `draw_hud`, `draw_player_health_bar` y `draw_config_menu`) |
| Autocomprobación | Revisa el catálogo y la matriz al cargar el mod | `modules/modifiers.lua` (`MODIFIER_KINDS`, `run_static_modifier_checks`) |
| Compartido | `SH` (lo que vale en los cuatro modos), `Team` (lo que solo vale en Team), `local_runtime` y los ayudantes transversales | `modules/core.lua` (incluye `is_local_player_on_floor`, que usan los modificadores y los peligros del Boss) |

## Errores ya encontrados y solución que no se debe deshacer

| Problema | Causa | Solución actual | Comprobación |
|---|---|---|---|
| Estrellas guardadas o borrado del curso equivocado | Curso de juego es 1-based; guardado es 0-based | `save_course_index_for()` resta 1 | La prueba verifica el índice correcto |
| Lakitu reaparecía | Se comparaban símbolos C no disponibles en Lua | Usar `id_bhvCameraLakitu` | `test/suite/lobby.lua` (12 pruebas): borra al Lakitu de cámara en la explanada, respeta a los objetos de otro behavior, no hace nada fuera de la explanada, y el barrido retroactivo espera quince frames entre pasadas |
| Gorras desaparecían o quedaban permanentes | Estado de StarHunt y de otros mods se mezclaba | Guardar timer, flags propios y cap externa | `test/suite/caps.lua` (12 pruebas) |
| Vidas quedaban en 99 | No se restauraba el valor previo | Guardar vidas al empezar y restaurar al terminar | Prueba de vidas |
| HUD de otro mod se mostraba de nuevo | StarHunt siempre llamaba a `hud_show()` | Recordar si estaba oculto antes de la ronda | Prueba de HUD oculto |
| Ataques de Bowser se perdían con lag | Solo existía el último ataque sincronizado | Cola circular de 8 ataques, reproducida entera por cada cliente | `test/suite/boss_hazards.lua`: varios ataques llegados en una sola actualización se reproducen todos, la cola da la vuelta en el noveno, y un hueco en la ranura más nueva recurre al campo único |
| Bowser atacaba mientras un jugador lo agarraba | Ni el host ni el cliente miraban `oHeldState` ni la accion 1 | los ataques se detienen durante el agarre (`boss_is_held`, que mira `oHeldState`) y durante el lanzamiento que lo sigue (`BOWSER_ACT.THROWN`, probado junto a las otras acciones en los dos puntos de uso, no dentro de la funcion): el host no encola y adelanta un segundo el siguiente, y cada cliente consume la secuencia y descarta las olas y meteoritos pendientes. **`BOWSER_ACT.THROWN` no es un rango**: las acciones 0 y 2 son Bowser actuando por su cuenta. Los numeros de accion viven en `BOWSER_ACT` (`modules/boss.lua`); las pruebas siguen escribiendo el numero a proposito, para que un valor equivocado en la tabla se detecte en vez de confirmarse | `test/suite/boss_hazards.lua` y `test/suite/round_host.lua`: agarrado y lanzado no atacan y no dejan nada en vuelo, soltado vuelve a atacar, las acciones vecinas a la 1 si atacan, y un `oHeldState` que el motor no responde deja la pelea como estaba |
| Un modo podia pasar por dificultad o por color de equipo | Los once valores vivian planos en una sola tabla llamada `Team`, asi que `NORMAL`, `EASY` y `NONE` eran 0, y `CHAOS` y `NIGHTMARE` eran 3; ningun test, luacheck ni lua-language-server puede ver ese cambiazo. Esa misma tabla mezclaba lo que vale en los cuatro modos con lo que solo vale en Team, asi que los ejes quedaban en un espacio de nombres que nombra un solo modo | Tres tablas separadas repartidas en dos espacios de nombres: `SH.Mode`, `SH.Difficulty` y `Team.Color`. Son tablas planas: un nombre del eje equivocado da `nil`, asi que la comparacion que lo lee es falsa en vez de verdadera por la razon equivocada. Se probo un metatable que lanzaba error y se descarto en la revision (agregaba una forma nueva de cortar una partida y defendia un error que el cambio de nombres ya hace dificil); **no volver a ponerlo**. **Los numeros no cambiaron**: `sh5_mode` y `sh5_difficulty` van por la red y se usan en aritmetica (`% 4`, `+ 1` como indice, `clamp(..., 0, 3)`), asi que renumerar enfrentaria a un cliente publicado con uno parcheado | `test/suite/core.lua`: los tres ejes son tablas distintas sin ningun nombre en comun, un nombre de otro eje da `nil` en vez de un numero, cada numero es el que se publico, los once nombres planos no estan ni en `SH` ni en `Team`, y `SH` y `Team` siguen siendo dos tablas con cada eje en la suya |
| Ráfagas/congelación se omitían | Dependían de un frame exacto | Usar número de ciclo, no igualdad exacta | Pruebas de salto de temporizador |
| Jugadores se veían entre subzonas | Solo se comparaba el nivel | Comparar también `currAreaIndex` | Prueba de áreas distintas |
| Un jugador oculto seguía siendo sólido | Se ocultaba el modelo y se negaba el daño, pero nada impedía que los cuerpos se tocaran: `interact_player` es el único camino del motor hacia `resolve_player_collision` y `gServerSettings.playerInteractions` vale `PVP` durante toda la ronda | `on_allow_interact` niega `INTERACT_PLAYER` cuando `players_have_private_variant` es cierto para el par, en las dos direcciones, porque el motor mueve al jugador que está procesando. La rama va **encima** de los cortes por modo, para que el contacto y la visibilidad respondan al mismo predicado; Boss y Chaos se eximen dentro del predicado. `player_index_of_body` lee `globalPlayerIndex` del objeto y **compara contra el `marioObj` de ese jugador**: un objeto cualquiera lleva `globalPlayerIndex` 0 y sin esa comparación se leería como el cuerpo del host | `test/suite/world.lua`: un par oculto se atraviesa en las dos direcciones, un par que comparte mundo se sigue tocando, la negativa termina con la ronda, y un objeto que no es el cuerpo de nadie no se niega |
| Retos imposibles | B o Z necesarios, rutas precisas o espera | Auditoría de cuatro etapas y ajustes por estrella | Matriz de 2.976 pares (2.222 aprobados, 754 rechazados); `test/suite/selfcheck.lua` comprueba que no falte ninguna. **2.232 era el tamaño de la matriz en v0.8, con 24 modificadores; esta fila lo citaba todavía** |
| Piso Maldito injusto en ascensores | Temporizador demasiado corto en plataformas lentas | 9 segundos en rutas de plataforma | Prueba de HMC/LLL/WDW |

## Regla del dos-puntos en el HUD

La fuente HUD de Mario 64 no tiene un dos-puntos normal: `FONT_HUD` dibuja `:`
como una `X`. Esta regla ya está implementada y no debe deshacerse.

1. No imprimir `:` directamente con `djui_hud_print_text`.
2. Todo texto HUD pasa por `draw_hud_text` / `measure_hud_text`, que cortan en
   cada dos-puntos y dibujan dos `.` pequeños, como ya hace el timer.
3. Al añadir texto HUD nuevo que incluya `:` (timer, estado, saltos, vida, Boss,
   menú y mensajes), comprobar que va por esas funciones.
4. Verificar en una partida real a resolución normal y pantalla ancha.
