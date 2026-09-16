# StarHunt — nota de desarrollo obligatoria

**Estado del proyecto: FINALIZADO. Versión final: v1.1 (2026-07-30).**

No hay versiones nuevas planificadas. Solo se aceptan actualizaciones de
mantenimiento sobre v1.1. Actualmente hay una excepción en curso: la rama
`refactor/modularize` divide `main.lua` en módulos sin cambiar comportamiento.

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
6. Ejecutar la comprobación de sintaxis y la prueba completa:
   `lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"` y `lua5.4 test/run.lua`.
7. Instalar solamente si ambas pruebas pasan y comprobar que la copia instalada
   coincide con la fuente.

El paso 5 nombraba `work/starhunt_v11_load_test.lua`, un arnés que nunca estuvo
en este repositorio y no existe en esta máquina. `test/` es su reemplazo.

## Regla adicional para cambios que solo mueven código

Un traslado byte a byte no puede deshacer una solución de la tabla de abajo,
pero sí puede romperla si el traslado no es exacto. Para esos cambios, además
de los siete pasos:

- Demostrar que las líneas movidas son idénticas byte a byte, en las dos
  direcciones: el cuerpo del módulo contra las líneas extraídas, y el
  `main.lua` reconstruido desde el commit anterior contra el archivo nuevo.
- Mutar el código movido y comprobar que la prueba lo detecta. Una ejecución
  verde no demuestra que el traslado sea correcto; en quince de los diecisiete traslados
  ya hechos la mutación encontró un área sin ninguna cobertura.
- Volver a comparar el módulo contra su original **justo antes** de hacer
  commit. Una vez quedó una mutación aplicada y la prueba siguió pasando.

## Mapa del código

`main.lua` se está dividiendo en `StarHunt/modules/`. La columna «Zona» nombra
el módulo cuando ya existe, y la función dentro de `main.lua` cuando todavía no.

| Sistema | Responsabilidad | Zona |
|---|---|---|
| Objetivos | Lista de estrellas, mundo, acto, poder y retos | `modules/goals.lua` (`GOALS`) |
| Reclamo de estrella | Qué estrella cuenta, y oculta las demás | `modules/goals.lua` (`on_allow_interact`, `on_interact`, `update_star_visibility`) |
| Auditoría | Acepta/rechaza cada reto para cada estrella | `modules/audit.lua` (`goal_traits`, `audit_modifier`, `rebuild_audited_modifiers`) |
| Dificultad | Escala cada reto y vuelve a auditarlo | `modules/difficulty.lua` (`effective_modifier_for_goal`) |
| Ronda normal | Asigna objetivos, puntos, ganador y retornos | `modules/round.lua` (`host_start_round`, `host_update_round`, `host_end_round`) |
| Retos | Aplica el modificador personal del jugador local | `modules/modifiers.lua` (`apply_local_modifier`) |
| Gorras | Da Wing/Metal/Vanish sin borrar poderes externos | `modules/goals.lua` (`apply_goal_power`, `restore_starhunt_power`) |
| Guardado | Quita solo la bandera temporal de la estrella obtenida | `modules/save.lua` (`save_course_index_for`, `remove_starhunt_save_flag`) |
| Boss | Vida de Bowser, ventajas, ataques y reaparición | `modules/boss.lua` (datos, vida, cola de ataques, `apply_boss_hazards`, la oleada de bombas de reserva y `ensure_boss_health_owner`); `modules/round.lua` (`host_update_boss_round`) |
| Chaos | Mapa, reroll de modificadores y eliminación | `modules/chaos.lua`; `modules/round.lua` (`host_update_chaos_round`) |
| Team | Equipos, paletas y PvP | `modules/team.lua` |
| Idiomas | Seis idiomas de interfaz y su persistencia | `modules/i18n.lua` (`translated`) |
| Privacidad/PvP | Oculta jugadores con geometría o área incompatible | `modules/goals.lua` (`players_have_private_variant`, `players_can_share_world`) |
| Lobby | Agua, puertas, Lakitu y retorno al castillo | `modules/goals.lua` (`on_allow_interact`); `modules/modifiers.lua` (`keep_moat_lowered`); `main.lua` (`skipIntro`, `remove_castle_lakitu`, `remove_existing_castle_lakitu`, `on_find_water_level` — se quedan ahí a propósito; el motivo está en el apéndice de `REFACTOR_PLAN.md`) |
| HUD y menú | Marcadores, timer, salud, menú `/starhunt` | `modules/menu.lua` (opciones, selección y `/starhunt`); `modules/hud.lua` (`draw_hud_text`, `measure_hud_text`, contadores nativos, DARKNESS PULSE, `draw_hud`, `draw_player_health_bar` y `draw_config_menu`) |
| Autocomprobación | Revisa el catálogo y la matriz al cargar el mod | `modules/modifiers.lua` (`MODIFIER_KINDS`, `run_static_modifier_checks`) |
| Compartido | `Team`, `local_runtime` y los ayudantes transversales | `modules/core.lua` (incluye `is_local_player_on_floor`, que usan los modificadores y los peligros del Boss) |

## Errores ya encontrados y solución que no se debe deshacer

| Problema | Causa | Solución actual | Comprobación |
|---|---|---|---|
| Estrellas guardadas o borrado del curso equivocado | Curso de juego es 1-based; guardado es 0-based | `save_course_index_for()` resta 1 | La prueba verifica el índice correcto |
| Lakitu reaparecía | Se comparaban símbolos C no disponibles en Lua | Usar `id_bhvCameraLakitu` | `test/suite/lobby.lua` (12 pruebas): borra al Lakitu de cámara en la explanada, respeta a los objetos de otro behavior, no hace nada fuera de la explanada, y el barrido retroactivo espera quince frames entre pasadas |
| Gorras desaparecían o quedaban permanentes | Estado de StarHunt y de otros mods se mezclaba | Guardar timer, flags propios y cap externa | `test/suite/caps.lua` (12 pruebas) |
| Vidas quedaban en 99 | No se restauraba el valor previo | Guardar vidas al empezar y restaurar al terminar | Prueba de vidas |
| HUD de otro mod se mostraba de nuevo | StarHunt siempre llamaba a `hud_show()` | Recordar si estaba oculto antes de la ronda | Prueba de HUD oculto |
| Ataques de Bowser se perdían con lag | Solo existía el último ataque sincronizado | Cola circular de 8 ataques, reproducida entera por cada cliente | `test/suite/boss_hazards.lua`: varios ataques llegados en una sola actualización se reproducen todos, la cola da la vuelta en el noveno, y un hueco en la ranura más nueva recurre al campo único |
| Ráfagas/congelación se omitían | Dependían de un frame exacto | Usar número de ciclo, no igualdad exacta | Pruebas de salto de temporizador |
| Jugadores se veían entre subzonas | Solo se comparaba el nivel | Comparar también `currAreaIndex` | Prueba de áreas distintas |
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
