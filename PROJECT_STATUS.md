# StarHunt — estado final

- **Estado:** FINALIZADO
- **Versión final:** v1.1
- **Fecha de cierre:** 2026-07-30
- **Juego:** SM64CoopDX
- **Lenguaje:** Lua
- **Desarrollo futuro planificado:** ninguna versión nueva; solo mantenimiento
  correctivo de v1.1

## Entrega final

StarHunt v1.1 contiene 93 objetivos, 32 modificadores auditados, los modos
Normal, Boss, Team y Chaos, cuatro dificultades y seis idiomas.

La prueba automatizada valida sintaxis, carga, 2.976 pares
estrella/modificador, los flujos principales y las 16 combinaciones entre modo
y dificultad.

SHA-256 de `main.lua` tal como se publico v1.1, en un solo archivo:
`EBC76DBEC1554D24522E907B49FF2DE5948282029E95C6DA51C31B42A906B883`.
Ese valor sigue siendo el de la entrega de v1.1 y no cambia.

## Reorganizacion en modulos (2026-09-16)

El mod se dividio en catorce archivos sin cambiar el comportamiento: `main.lua`
(420 lineas) conserva la cabecera, los `require`, el bloque de hooks, la semilla
de las tablas sincronizadas y `STARHUNT_TEST_API`, y el resto vive en
`StarHunt/modules/`. Cada traslado se probo identico byte a byte en ambas
direcciones y se verifico con mutaciones; la suite pasa de 72 a 767 pruebas.
Las etiquetas `v1.1-monolithic` y `v1.1-modular` marcan el antes y el despues.

**Ya no basta con el hash de `main.lua`**, porque el mod son catorce archivos.
El identificador es el SHA-256 de la lista ordenada de hashes de todos los
`.lua` bajo `StarHunt/`:

```bash
(cd StarHunt && find . -name '*.lua' | sort | xargs sha256sum | sha256sum)
```

`E03B9B6CCEF6B2D14459B6A7DD5FE859AF13185BBE082681F7F0DB215E4A45B9`, tras las correcciones
del 16 de septiembre. El valor de la division en modulos era
`27BEDAA820964202EABAAFB96633B8F4A9C4812BA7866C3F97E463CC5D3DD0C7`.

La actualizacion de mantenimiento del 31 de julio abre y bloquea el menu de
configuracion durante la espera. El estado sincronizado de la ronda lo cierra
para host y clientes al comenzar y hace que reaparezca al terminar.

La actualización correctiva del 1 de agosto sustituye el redundante
Aturdimiento al aterrizar por Impulso de moneda y fija la orientación de Mario
durante Congelación Periódica. Conserva 32 modificadores y la matriz de 2.976
pares, con 2.222 aprobados y 754 rechazados.

La actualización correctiva del 4 de agosto repara la duración de los pulsos
Easy, elimina la inercia residual de Slippery y hace simétrica la compatibilidad
de parejas Nightmare en Normal, Team, Chaos y Boss. No cambia modos, objetivos,
puntuación ni cantidad de modificadores.

La actualización correctiva del 4 de agosto evita el bloqueo de Boss al
agotarse las cinco bombas originales. Hard crea una sola reserva sincronizada
de dos bombas y Nightmare una de cuatro, elegidas sin repetir entre las cinco
posiciones originales. Easy y Medium conservan el escenario nativo sin reservas.

## Versiones conservadas

- **v1.1:** versión final instalada.
- **v1.0:** respaldo estable conservado e intacto.

## Versiones retiradas

v0.7, v0.8 y v0.9 fueron eliminadas de la fuente y de la carpeta de mods.
También se eliminaron sus pruebas auxiliares independientes.

## Instalacion

Copiar la carpeta `StarHunt/` completa dentro de `sm64coopdx/mods/`. Copiar solo
`main.lua` ya no alcanza: el juego recorre la carpeta del mod y carga cada `.lua`
que encuentra, y `main.lua` resuelve `modules/...` por `require` relativo a esa
carpeta.

## Límite de la validación

El cierre se basa en pruebas automatizadas y las verificaciones visuales ya
registradas. No afirma que todas las combinaciones multijugador, de resolución
y de mods externos hayan sido probadas dentro de SM64CoopDX.

**La version en modulos todavia no se jugo dentro de SM64CoopDX.** Las 775
pruebas corren fuera del juego contra un doble del motor, asi que no alcanzan el
renderizado, la red, los warps ni la interaccion con otros mods -- y tampoco el
`require` relativo a la carpeta, que es justamente lo que cambio la division. Es
el punto R-010 de `ROADMAP.md`.

La actualización de mantenimiento añade `Otro nivel` al menú de pausa para
Normal y Team. El host impone dos minutos por objetivo y nunca entrega otro
objetivo del mismo curso mediante ese botón.
