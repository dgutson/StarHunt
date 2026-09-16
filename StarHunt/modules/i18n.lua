-- StarHunt v1.1 - the six UI languages.
--
-- SH.language is an index into SH.language_codes, persisted under
-- "starhunt_v11_language" and migrated from the v1.0 down to v0.6 keys on first
-- load, so a player's choice survives an upgrade from any earlier version.
--
-- Only text with a safe translation is localized. Goal and world names carry
-- their own title/title_es fields on the goal and fall back to English in the
-- other four languages, which is deliberate.

local SH = require("core").SH

SH.saved_language = mod_storage_load("starhunt_v11_language")
    or mod_storage_load("starhunt_v10_language")
    or mod_storage_load("starhunt_v09_language")
    or mod_storage_load("starhunt_v08_language")
    or mod_storage_load("starhunt_v07_language")
    or mod_storage_load("starhunt_v06_language")
SH.language = math.max(0, math.min(5, math.floor(tonumber(SH.saved_language) or 1)))
SH.saved_language = nil

SH.language_codes = { "en", "es", "pt", "fr", "de", "it" }
SH.menu_lock_labels = {
    "MENU LOCKED UNTIL ROUND STARTS",
    "MENU BLOQUEADO HASTA INICIAR LA RONDA",
    "MENU BLOQUEADO ATE A RODADA COMECAR",
    "MENU VERROUILLE JUSQU'AU DEBUT DE LA MANCHE",
    "MENU BIS ZUM RUNDENSTART GESPERRT",
    "MENU BLOCCATO FINO ALL'INIZIO DEL ROUND",
}
SH.language_names = { "ENGLISH", "ESPAÑOL", "PORTUGUÊS", "FRANÇAIS", "DEUTSCH", "ITALIANO" }
SH.ui_translations = {
    pt = {
        ["START!"] = "COMEÇAR!", ["START ROUND"] = "INICIAR RODADA", ["STOP ROUND"] = "PARAR RODADA",
        ["LANGUAGE"] = "IDIOMA", ["GAME MODE"] = "MODO DE JOGO", ["TIME"] = "TEMPO",
        ["STATUS"] = "ESTADO", ["WAITING"] = "ESPERANDO", ["ACTIVE "] = "ATIVO ",
        ["BOSS"] = "CHEFE", ["TEAM"] = "EQUIPES", ["CHAOS"] = "CAOS", ["DIFFICULTY"] = "DIFICULDADE",
        ["EASY"] = "FÁCIL", ["NORMAL"] = "NORMAL", ["HARD"] = "DIFÍCIL", ["NIGHTMARE"] = "PESADELO",
        ["LOCKED"] = "BLOQUEADO", ["(LOCKED)"] = "(BLOQUEADO)", ["NEEDS 2 PLAYERS"] = "PRECISA DE 2 JOGADORES",
        ["MINUTES"] = "MINUTOS", ["open the StarHunt menu"] = "abre o menu StarHunt",
        ["MODE IS LOCKED DURING A ROUND"] = "O MODO FICA BLOQUEADO DURANTE A RODADA",
        ["DIFFICULTY IS LOCKED DURING A ROUND"] = "A DIFICULDADE FICA BLOQUEADA DURANTE A RODADA",
        ["TIME IS LOCKED DURING A ROUND"] = "O TEMPO FICA BLOQUEADO DURANTE A RODADA",
        ["FINISH THE ROUND OR ASK THE HOST TO STOP IT."] = "TERMINE A RODADA OU PEÇA AO HOST PARA PARÁ-LA.",
        ["ALIVE "] = "VIVOS ", ["LAST PLAYER STANDING"] = "ÚLTIMO JOGADOR VIVO",
        ["ELIMINATED - SPECTATING"] = "ELIMINADO - ASSISTINDO", ["ELIMINATED! SPECTATING..."] = "ELIMINADO! ASSISTINDO...",
        ["CHAOS WINNER: "] = "VENCEDOR DO CAOS: ",
        ["CHAOS ENDED WITHOUT A WINNER."] = "O CAOS TERMINOU SEM VENCEDOR.",
        ["CHAOS IS ACTIVE: YOU WILL SPECTATE."] = "O CAOS ESTÁ ATIVO: VOCÊ SERÁ ESPECTADOR.",
        ["show what StarHunt is and what changed"] = "mostra o que é StarHunt e o que mudou",
        ["ABOUT: A multiplayer challenge mod with four game modes."] = "SOBRE: Um mod multijogador de desafios com quatro modos de jogo.",
        ["MODES: Normal star race, team competition, cooperative Boss and last-player-standing Chaos."] = "MODOS: Corrida Normal, competição em equipes, Boss cooperativo e Chaos de último sobrevivente.",
        ["DIFFICULTY: Easy, Normal, Hard or Nightmare applies independently to every mode."] = "DIFICULDADE: Fácil, Normal, Difícil ou Pesadelo se aplica independentemente a cada modo.",
        ["V1.1: Personal Chaos modifiers, Nightmare extras and an in-game Another Level button with a two-minute cooldown."] = "V1.1: Modificadores pessoais no Chaos, extras no Pesadelo e botão Outro Nível no menu com espera de dois minutos.",
        ["ANOTHER LEVEL"] = "OUTRO NÍVEL", ["READY"] = "PRONTO",
        ["NORMAL/TEAM ONLY"] = "SÓ NORMAL/EQUIPES",
        ["ANOTHER LEVEL IS ONLY AVAILABLE IN NORMAL OR TEAM."] = "OUTRO NÍVEL SÓ ESTÁ DISPONÍVEL EM NORMAL OU EQUIPES.",
        ["ANOTHER LEVEL AVAILABLE IN "] = "OUTRO NÍVEL DISPONÍVEL EM ",
        ["A LEVEL CHANGE IS ALREADY PENDING."] = "JÁ HÁ UMA TROCA DE NÍVEL PENDENTE.",
        ["NEW LEVEL REQUESTED."] = "NOVO NÍVEL SOLICITADO.",
    },
    fr = {
        ["START!"] = "PARTEZ!", ["START ROUND"] = "LANCER LA MANCHE", ["STOP ROUND"] = "ARRÊTER LA MANCHE",
        ["LANGUAGE"] = "LANGUE", ["GAME MODE"] = "MODE DE JEU", ["TIME"] = "TEMPS",
        ["STATUS"] = "ÉTAT", ["WAITING"] = "EN ATTENTE", ["ACTIVE "] = "ACTIVE ",
        ["BOSS"] = "BOSS", ["TEAM"] = "ÉQUIPES", ["CHAOS"] = "CHAOS", ["DIFFICULTY"] = "DIFFICULTÉ",
        ["EASY"] = "FACILE", ["NORMAL"] = "NORMAL", ["HARD"] = "DIFFICILE", ["NIGHTMARE"] = "CAUCHEMAR",
        ["LOCKED"] = "VERROUILLÉ", ["(LOCKED)"] = "(VERROUILLÉ)", ["NEEDS 2 PLAYERS"] = "2 JOUEURS REQUIS",
        ["MINUTES"] = "MINUTES", ["open the StarHunt menu"] = "ouvre le menu StarHunt",
        ["MODE IS LOCKED DURING A ROUND"] = "LE MODE EST VERROUILLÉ PENDANT LA MANCHE",
        ["DIFFICULTY IS LOCKED DURING A ROUND"] = "LA DIFFICULTÉ EST VERROUILLÉE PENDANT LA MANCHE",
        ["TIME IS LOCKED DURING A ROUND"] = "LE TEMPS EST VERROUILLÉ PENDANT LA MANCHE",
        ["FINISH THE ROUND OR ASK THE HOST TO STOP IT."] = "TERMINEZ LA MANCHE OU DEMANDEZ À L'HÔTE DE L'ARRÊTER.",
        ["ALIVE "] = "EN VIE ", ["LAST PLAYER STANDING"] = "DERNIER JOUEUR EN VIE",
        ["ELIMINATED - SPECTATING"] = "ÉLIMINÉ - SPECTATEUR", ["ELIMINATED! SPECTATING..."] = "ÉLIMINÉ ! MODE SPECTATEUR...",
        ["CHAOS WINNER: "] = "VAINQUEUR DU CHAOS : ",
        ["CHAOS ENDED WITHOUT A WINNER."] = "LE CHAOS SE TERMINE SANS VAINQUEUR.",
        ["CHAOS IS ACTIVE: YOU WILL SPECTATE."] = "LE CHAOS EST ACTIF : VOUS SEREZ SPECTATEUR.",
        ["show what StarHunt is and what changed"] = "affiche ce qu'est StarHunt et ses changements",
        ["ABOUT: A multiplayer challenge mod with four game modes."] = "À PROPOS : Un mod multijoueur de défis avec quatre modes de jeu.",
        ["MODES: Normal star race, team competition, cooperative Boss and last-player-standing Chaos."] = "MODES : Course Normal, compétition en équipes, Boss coopératif et Chaos du dernier survivant.",
        ["DIFFICULTY: Easy, Normal, Hard or Nightmare applies independently to every mode."] = "DIFFICULTÉ : Facile, Normal, Difficile ou Cauchemar s'applique séparément à chaque mode.",
        ["V1.1: Personal Chaos modifiers, Nightmare extras and an in-game Another Level button with a two-minute cooldown."] = "V1.1 : Modificateurs personnels en Chaos, extras en Cauchemar et bouton Autre niveau avec attente de deux minutes.",
        ["ANOTHER LEVEL"] = "AUTRE NIVEAU", ["READY"] = "PRÊT",
        ["NORMAL/TEAM ONLY"] = "NORMAL/ÉQUIPES SEULEMENT",
        ["ANOTHER LEVEL IS ONLY AVAILABLE IN NORMAL OR TEAM."] = "UN AUTRE NIVEAU EST DISPONIBLE UNIQUEMENT EN NORMAL OU ÉQUIPES.",
        ["ANOTHER LEVEL AVAILABLE IN "] = "AUTRE NIVEAU DISPONIBLE DANS ",
        ["A LEVEL CHANGE IS ALREADY PENDING."] = "UN CHANGEMENT DE NIVEAU EST DÉJÀ EN ATTENTE.",
        ["NEW LEVEL REQUESTED."] = "NOUVEAU NIVEAU DEMANDÉ.",
    },
    de = {
        ["START!"] = "LOS!", ["START ROUND"] = "RUNDE STARTEN", ["STOP ROUND"] = "RUNDE STOPPEN",
        ["LANGUAGE"] = "SPRACHE", ["GAME MODE"] = "SPIELMODUS", ["TIME"] = "ZEIT",
        ["STATUS"] = "STATUS", ["WAITING"] = "WARTET", ["ACTIVE "] = "AKTIV ",
        ["BOSS"] = "BOSS", ["TEAM"] = "TEAMS", ["CHAOS"] = "CHAOS", ["DIFFICULTY"] = "SCHWIERIGKEIT",
        ["EASY"] = "LEICHT", ["NORMAL"] = "NORMAL", ["HARD"] = "SCHWER", ["NIGHTMARE"] = "ALBTRAUM",
        ["LOCKED"] = "GESPERRT", ["(LOCKED)"] = "(GESPERRT)", ["NEEDS 2 PLAYERS"] = "BRAUCHT 2 SPIELER",
        ["MINUTES"] = "MINUTEN", ["open the StarHunt menu"] = "öffnet das StarHunt-Menü",
        ["MODE IS LOCKED DURING A ROUND"] = "DER MODUS IST WÄHREND DER RUNDE GESPERRT",
        ["DIFFICULTY IS LOCKED DURING A ROUND"] = "DIE SCHWIERIGKEIT IST WÄHREND DER RUNDE GESPERRT",
        ["TIME IS LOCKED DURING A ROUND"] = "DIE ZEIT IST WÄHREND DER RUNDE GESPERRT",
        ["FINISH THE ROUND OR ASK THE HOST TO STOP IT."] = "BEENDE DIE RUNDE ODER BITTE DEN HOST, SIE ZU STOPPEN.",
        ["ALIVE "] = "AM LEBEN ", ["LAST PLAYER STANDING"] = "LETZTER SPIELER AM LEBEN",
        ["ELIMINATED - SPECTATING"] = "AUSGESCHIEDEN - ZUSCHAUER", ["ELIMINATED! SPECTATING..."] = "AUSGESCHIEDEN! ZUSCHAUEN...",
        ["CHAOS WINNER: "] = "CHAOS-SIEGER: ",
        ["CHAOS ENDED WITHOUT A WINNER."] = "CHAOS ENDETE OHNE SIEGER.",
        ["CHAOS IS ACTIVE: YOU WILL SPECTATE."] = "CHAOS LÄUFT: DU BIST ZUSCHAUER.",
        ["show what StarHunt is and what changed"] = "zeigt, was StarHunt ist und was sich geändert hat",
        ["ABOUT: A multiplayer challenge mod with four game modes."] = "INFO: Eine Mehrspieler-Herausforderungsmod mit vier Spielmodi.",
        ["MODES: Normal star race, team competition, cooperative Boss and last-player-standing Chaos."] = "MODI: Normales Sternrennen, Teamwettkampf, kooperativer Boss und Chaos bis zum letzten Spieler.",
        ["DIFFICULTY: Easy, Normal, Hard or Nightmare applies independently to every mode."] = "SCHWIERIGKEIT: Leicht, Normal, Schwer oder Albtraum gilt unabhängig für jeden Modus.",
        ["V1.1: Personal Chaos modifiers, Nightmare extras and an in-game Another Level button with a two-minute cooldown."] = "V1.1: Persönliche Chaos-Modifikatoren, Albtraum-Extras und Anderes-Level-Knopf mit zwei Minuten Wartezeit.",
        ["ANOTHER LEVEL"] = "ANDERES LEVEL", ["READY"] = "BEREIT",
        ["NORMAL/TEAM ONLY"] = "NUR NORMAL/TEAM",
        ["ANOTHER LEVEL IS ONLY AVAILABLE IN NORMAL OR TEAM."] = "EIN ANDERES LEVEL IST NUR IN NORMAL ODER TEAM VERFÜGBAR.",
        ["ANOTHER LEVEL AVAILABLE IN "] = "ANDERES LEVEL VERFÜGBAR IN ",
        ["A LEVEL CHANGE IS ALREADY PENDING."] = "EIN LEVELWECHSEL WARTET BEREITS.",
        ["NEW LEVEL REQUESTED."] = "NEUES LEVEL ANGEFORDERT.",
    },
    it = {
        ["START!"] = "VIA!", ["START ROUND"] = "AVVIA ROUND", ["STOP ROUND"] = "FERMA ROUND",
        ["LANGUAGE"] = "LINGUA", ["GAME MODE"] = "MODALITÀ", ["TIME"] = "TEMPO",
        ["STATUS"] = "STATO", ["WAITING"] = "IN ATTESA", ["ACTIVE "] = "ATTIVO ",
        ["BOSS"] = "BOSS", ["TEAM"] = "SQUADRE", ["CHAOS"] = "CAOS", ["DIFFICULTY"] = "DIFFICOLTÀ",
        ["EASY"] = "FACILE", ["NORMAL"] = "NORMALE", ["HARD"] = "DIFFICILE", ["NIGHTMARE"] = "INCUBO",
        ["LOCKED"] = "BLOCCATO", ["(LOCKED)"] = "(BLOCCATO)", ["NEEDS 2 PLAYERS"] = "SERVONO 2 GIOCATORI",
        ["MINUTES"] = "MINUTI", ["open the StarHunt menu"] = "apre il menu StarHunt",
        ["MODE IS LOCKED DURING A ROUND"] = "LA MODALITÀ È BLOCCATA DURANTE IL ROUND",
        ["DIFFICULTY IS LOCKED DURING A ROUND"] = "LA DIFFICOLTÀ È BLOCCATA DURANTE IL ROUND",
        ["TIME IS LOCKED DURING A ROUND"] = "IL TEMPO È BLOCCATO DURANTE IL ROUND",
        ["FINISH THE ROUND OR ASK THE HOST TO STOP IT."] = "FINISCI IL ROUND O CHIEDI ALL'HOST DI FERMARLO.",
        ["ALIVE "] = "VIVI ", ["LAST PLAYER STANDING"] = "ULTIMO GIOCATORE VIVO",
        ["ELIMINATED - SPECTATING"] = "ELIMINATO - SPETTATORE", ["ELIMINATED! SPECTATING..."] = "ELIMINATO! SPETTATORE...",
        ["CHAOS WINNER: "] = "VINCITORE CAOS: ",
        ["CHAOS ENDED WITHOUT A WINNER."] = "IL CAOS È FINITO SENZA VINCITORE.",
        ["CHAOS IS ACTIVE: YOU WILL SPECTATE."] = "IL CAOS È ATTIVO: SARAI SPETTATORE.",
        ["show what StarHunt is and what changed"] = "mostra cos'è StarHunt e cosa è cambiato",
        ["ABOUT: A multiplayer challenge mod with four game modes."] = "INFO: Una mod multigiocatore di sfide con quattro modalità.",
        ["MODES: Normal star race, team competition, cooperative Boss and last-player-standing Chaos."] = "MODALITÀ: Gara Normal, competizione a squadre, Boss cooperativo e Chaos con ultimo giocatore vivo.",
        ["DIFFICULTY: Easy, Normal, Hard or Nightmare applies independently to every mode."] = "DIFFICOLTÀ: Facile, Normale, Difficile o Incubo si applica separatamente a ogni modalità.",
        ["V1.1: Personal Chaos modifiers, Nightmare extras and an in-game Another Level button with a two-minute cooldown."] = "V1.1: Modificatori personali in Chaos, extra in Incubo e pulsante Altro livello con attesa di due minuti.",
        ["ANOTHER LEVEL"] = "ALTRO LIVELLO", ["READY"] = "PRONTO",
        ["NORMAL/TEAM ONLY"] = "SOLO NORMAL/SQUADRE",
        ["ANOTHER LEVEL IS ONLY AVAILABLE IN NORMAL OR TEAM."] = "UN ALTRO LIVELLO È DISPONIBILE SOLO IN NORMAL O SQUADRE.",
        ["ANOTHER LEVEL AVAILABLE IN "] = "ALTRO LIVELLO DISPONIBILE TRA ",
        ["A LEVEL CHANGE IS ALREADY PENDING."] = "UN CAMBIO DI LIVELLO È GIÀ IN ATTESA.",
        ["NEW LEVEL REQUESTED."] = "NUOVO LIVELLO RICHIESTO.",
    },
}
SH.modifier_translations = {
    pt = {
        no_b="BOTÃO B BLOQUEADO", floor_doom="CHÃO AMALDIÇOADO", speed_cap="PÉS PESADOS",
        low_jump="PULOS BAIXOS", water_cap="NADO PESADO", jump_limit="PULOS", reverse_controls="CONTROLES INVERTIDOS",
        periodic_freeze="CONGELAMENTO PERIÓDICO", fragile="FRÁGIL", high_gravity="GRAVIDADE ALTA",
        wind_gust="RAJADAS DE VENTO", no_z="BOTÃO Z BLOQUEADO", air_brake="CONTROLE AÉREO FRACO",
        lava_clock="DANO PERIÓDICO", turbo="MODO TURBO", slippery="SAPATOS ESCORREGADIOS",
        swap_ab="BOTÕES A/B TROCADOS", keep_moving="CONTINUE EM MOVIMENTO", jump_cooldown="ESPERA ENTRE PULOS",
        coin_surge="IMPULSO DE MOEDA", control_drift="CONTROLES ONDULANTES", coin_toll="PEDÁGIO DE MOEDAS",
        darkness_pulse="PULSO DE ESCURIDÃO", mirrored_steering="DIREÇÃO ESPELHADA", coin_leak="VAZAMENTO DE MOEDAS",
        slow_pulse="PULSO LENTO", air_mirror="ESPELHO AÉREO", momentum_burst="IMPULSO PERIÓDICO",
        control_pulse="PULSO DE CONTROLE", coin_weight="PESO DAS MOEDAS", gravity_wave="ONDA DE GRAVIDADE",
        overheat="SUPERAQUECIMENTO",
    },
    fr = {
        no_b="BOUTON B BLOQUÉ", floor_doom="SOL MAUDIT", speed_cap="PIEDS LOURDS", low_jump="SAUTS BAS",
        water_cap="NAGE LOURDE", jump_limit="SAUTS", reverse_controls="COMMANDES INVERSÉES",
        periodic_freeze="GEL PÉRIODIQUE", fragile="FRAGILE", high_gravity="FORTE GRAVITÉ",
        wind_gust="RAFALES DE VENT", no_z="BOUTON Z BLOQUÉ", air_brake="FAIBLE CONTRÔLE AÉRIEN",
        lava_clock="DÉGÂTS PÉRIODIQUES", turbo="MODE TURBO", slippery="CHAUSSURES GLISSANTES",
        swap_ab="BOUTONS A/B INVERSÉS", keep_moving="RESTEZ EN MOUVEMENT", jump_cooldown="DÉLAI DE SAUT",
        coin_surge="ÉLAN DE PIÈCE", control_drift="COMMANDES ONDULANTES",
        coin_toll="PÉAGE DE PIÈCES", darkness_pulse="PULSATION NOIRE", mirrored_steering="DIRECTION MIROIR",
        coin_leak="FUITE DE PIÈCES", slow_pulse="PULSATION LENTE", air_mirror="MIROIR AÉRIEN",
        momentum_burst="POUSSÉE PÉRIODIQUE", control_pulse="PULSATION DES COMMANDES", coin_weight="POIDS DES PIÈCES",
        gravity_wave="VAGUE DE GRAVITÉ", overheat="SURCHAUFFE",
    },
    de = {
        no_b="B-TASTE GESPERRT", floor_doom="VERFLUCHTER BODEN", speed_cap="SCHWERE FÜSSE",
        low_jump="NIEDRIGE SPRÜNGE", water_cap="SCHWERES SCHWIMMEN", jump_limit="SPRÜNGE",
        reverse_controls="UMGEKEHRTE STEUERUNG", periodic_freeze="REGELMÄSSIGES EINFRIEREN", fragile="ZERBRECHLICH",
        high_gravity="HOHE SCHWERKRAFT", wind_gust="WINDBÖEN", no_z="Z-TASTE GESPERRT",
        air_brake="SCHWACHE LUFTKONTROLLE", lava_clock="REGELMÄSSIGER SCHADEN", turbo="TURBO-MODUS",
        slippery="RUTSCHIGE SCHUHE", swap_ab="A/B VERTAUSCHT", keep_moving="BLEIB IN BEWEGUNG",
        jump_cooldown="SPRUNG-ABKLINGZEIT", coin_surge="MÜNZSCHUB", control_drift="WELLIGE STEUERUNG",
        coin_toll="MÜNZGEBÜHR", darkness_pulse="DUNKELHEITSIMPULS", mirrored_steering="GESPIEGELTE LENKUNG",
        coin_leak="MÜNZVERLUST", slow_pulse="LANGSAMER IMPULS", air_mirror="LUFTSPIEGEL",
        momentum_burst="BEWEGUNGSSCHUB", control_pulse="STEUERUNGSIMPULS", coin_weight="MÜNZGEWICHT",
        gravity_wave="SCHWERKRAFTWELLE", overheat="ÜBERHITZUNG",
    },
    it = {
        no_b="TASTO B BLOCCATO", floor_doom="PAVIMENTO MALEDETTO", speed_cap="PIEDI PESANTI",
        low_jump="SALTI BASSI", water_cap="NUOTO PESANTE", jump_limit="SALTI", reverse_controls="COMANDI INVERTITI",
        periodic_freeze="GELO PERIODICO", fragile="FRAGILE", high_gravity="GRAVITÀ ALTA",
        wind_gust="RAFFICHE DI VENTO", no_z="TASTO Z BLOCCATO", air_brake="SCARSO CONTROLLO AEREO",
        lava_clock="DANNO PERIODICO", turbo="MODALITÀ TURBO", slippery="SCARPE SCIVOLOSE",
        swap_ab="TASTI A/B SCAMBIATI", keep_moving="CONTINUA A MUOVERTI", jump_cooldown="ATTESA TRA I SALTI",
        coin_surge="SLANCIO MONETA", control_drift="COMANDI ONDULATI", coin_toll="PEDAGGIO MONETE",
        darkness_pulse="IMPULSO OSCURO", mirrored_steering="STERZO SPECCHIATO", coin_leak="PERDITA MONETE",
        slow_pulse="IMPULSO LENTO", air_mirror="SPECCHIO AEREO", momentum_burst="SLANCIO PERIODICO",
        control_pulse="IMPULSO COMANDI", coin_weight="PESO DELLE MONETE", gravity_wave="ONDA DI GRAVITÀ",
        overheat="SURRISCALDAMENTO",
    },
}
SH.boss_modifier_translations = {
    pt = {
        instakill="BOWSER: GOLPE MORTAL", shockwaves="BOWSER: ONDAS PARALISANTES",
        violet_fire="BOWSER: FOGO VIOLETA DIVIDIDO", rage="BOWSER: FÚRIA",
        meteor_rain="BOWSER: CHUVA DE METEOROS", fire_ring="BOWSER: ANEL DE FOGO",
        bomb_barrage="BOWSER: BOMBARDEIO", arena_quake="BOWSER: TERREMOTO DA ARENA",
        teleport="BOWSER: ONDA DE TELEPORTE", double_wave="BOWSER: ONDA DUPLA",
        hunter_fire="BOWSER: FOGO CAÇADOR", desperate="BOWSER: FASE DESESPERADA",
    },
    fr = {
        instakill="BOWSER : COUP MORTEL", shockwaves="BOWSER : ONDES PARALYSANTES",
        violet_fire="BOWSER : FEU VIOLET DIVISÉ", rage="BOWSER : RAGE",
        meteor_rain="BOWSER : PLUIE DE MÉTÉORES", fire_ring="BOWSER : ANNEAU DE FEU",
        bomb_barrage="BOWSER : BOMBARDEMENT", arena_quake="BOWSER : SÉISME DE L'ARÈNE",
        teleport="BOWSER : VAGUE DE TÉLÉPORTATION", double_wave="BOWSER : DOUBLE VAGUE",
        hunter_fire="BOWSER : FEU CHASSEUR", desperate="BOWSER : PHASE DÉSESPÉRÉE",
    },
    de = {
        instakill="BOWSER: TÖDLICHER TREFFER", shockwaves="BOWSER: LÄHMENDE WELLEN",
        violet_fire="BOWSER: GETEILTES VIOLETTES FEUER", rage="BOWSER: RASEREI",
        meteor_rain="BOWSER: METEORREGEN", fire_ring="BOWSER: FEUERRING",
        bomb_barrage="BOWSER: BOMBENHAGEL", arena_quake="BOWSER: ARENA-BEBEN",
        teleport="BOWSER: TELEPORTWELLE", double_wave="BOWSER: DOPPELWELLE",
        hunter_fire="BOWSER: JAGDFEUER", desperate="BOWSER: VERZWEIFELTE PHASE",
    },
    it = {
        instakill="BOWSER: COLPO MORTALE", shockwaves="BOWSER: ONDE PARALIZZANTI",
        violet_fire="BOWSER: FUOCO VIOLA DIVISO", rage="BOWSER: FURIA",
        meteor_rain="BOWSER: PIOGGIA DI METEORE", fire_ring="BOWSER: ANELLO DI FUOCO",
        bomb_barrage="BOWSER: BOMBARDAMENTO", arena_quake="BOWSER: TERREMOTO ARENA",
        teleport="BOWSER: ONDA TELETRASPORTO", double_wave="BOWSER: DOPPIA ONDA",
        hunter_fire="BOWSER: FUOCO CACCIATORE", desperate="BOWSER: FASE DISPERATA",
    },
}

local function translated(en, es)
    if SH.language == 1 then return es end
    local code = SH.language_codes[SH.language + 1]
    local dictionary = code ~= nil and SH.ui_translations[code] or nil
    return dictionary ~= nil and dictionary[en] or en
end

return { translated = translated }
