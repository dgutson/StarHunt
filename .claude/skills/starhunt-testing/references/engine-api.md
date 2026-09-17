# How the checkers know the sm64coopdx API

Background, not a step. Read it when `~/.local/share/sm64coopdx/refresh.sh` did not settle a
checker reporting undefined globals, or when setting this project up on another machine.

`StarHunt/main.lua` calls about 59 engine functions and reads roughly 1,090 engine constants.
Without the game's API those are all undefined globals and both checkers are useless — they
would report over a thousand problems and hide the real ones. So the API list is generated from
sm64coopdx's own `autogen/lua_definitions`: 6,337 globals, being 2,008 functions, 4,307
constants and 22 mutable engine tables.

It is stored **outside the repository**, because the game runs every `.lua` file it finds under
a mod's folder and these would be loaded as part of StarHunt if they sat inside it.

| path | contents |
|---|---|
| `~/.local/share/sm64coopdx/definitions/` | `functions.lua`, `constants.lua`, `structs.lua`, `manual.lua`, taken from the game repository |
| `~/.local/share/sm64coopdx/luacheck_globals.lua` | the generated read/write global lists, loaded by `.luacheckrc` |
| `~/.local/share/sm64coopdx/refresh.sh` | re-downloads the definitions and regenerates the above |

The two checker configs that do stay in the repository, `.luarc.json` and `.luacheckrc`, have no
`.lua` extension, so the game ignores them even if the folder is copied into `mods/`.

Because the list is generated from the engine's own definitions rather than written by hand, a
clean `lua-language-server --check` also confirms something the tests cannot: every engine symbol
the mod uses still exists in the version of sm64coopdx being targeted. That is why a rise in its
problem count after a game update is worth reading carefully rather than re-baselining.
