-- StarHunt speaks six languages, and translation is the one part of the mod
-- with no other safety net: nothing else in the suite reads a translated
-- string, so a broken dictionary is invisible everywhere else.
--
-- This suite was added when modules/i18n.lua was split out of main.lua. The
-- extraction was verified byte-for-byte, but making translated() always return
-- English still left the whole run green, which is exactly the gap this closes.
--
-- Team.language is an INDEX into Team.language_codes, not a code: 0 is English
-- and 1 is Spanish, and those two are special. English is the identity (the key
-- is already English) and Spanish comes from translated()'s second argument
-- rather than from a dictionary, so neither has a ui_translations entry.

return function(t, harness)
    local s = t.suite("i18n")

    s.test("the six languages line up with their names", function()
        local api = harness.load()
        t.eq(#api.language_codes, 6, "expected six language codes")
        t.eq(#api.language_names, 6, "expected one name per language code")
        t.eq(api.language_codes[1], "en", "English must stay first: it is index 0")
        t.eq(api.language_codes[2], "es", "Spanish must stay second: it is index 1")
    end)

    s.test("the stored language is restored, and defaults to Spanish", function()
        -- Team.language is clamped to 0..5 so a corrupt or out-of-range stored
        -- value cannot put the mod into a language that does not exist.
        local cases = {
            { stored = nil, want = 1, why = "no stored value falls back to Spanish" },
            { stored = "0", want = 0, why = "English" },
            { stored = "5", want = 5, why = "Italian" },
            { stored = "9", want = 5, why = "out of range clamps to the last language" },
            { stored = "-3", want = 0, why = "negative clamps to the first language" },
            { stored = "junk", want = 1, why = "unparseable falls back to Spanish" },
        }
        for _, case in ipairs(cases) do
            local api = harness.load(function(ctl)
                ctl.storage["starhunt_v11_language"] = case.stored
            end)
            -- read it back through translated(): index 1 is the Spanish path
            local got = api.translated("START!", "COMENZAR!")
            local expected = case.want == 1 and "COMENZAR!"
                or (api.ui_translations[api.language_codes[case.want + 1]] or {})["START!"]
                or "START!"
            t.eq(got, expected, string.format("stored %q (%s)", tostring(case.stored), case.why))
        end
    end)

    s.test("a language stored by an older version is migrated forward", function()
        -- The key has changed with almost every release. A player's choice has
        -- to survive an upgrade from any of them, so each older key is read in
        -- turn and the newest one present wins.
        for _, key in ipairs({ "starhunt_v11_language", "starhunt_v10_language",
                               "starhunt_v09_language", "starhunt_v08_language",
                               "starhunt_v07_language", "starhunt_v06_language" }) do
            local api = harness.load(function(ctl) ctl.storage[key] = "0" end)
            t.eq(api.translated("START!", "COMENZAR!"), "START!",
                key .. ": stored English was not carried forward")
        end
    end)

    s.test("English is the identity and Spanish takes the second argument", function()
        local api = harness.load()
        api.set_language(0)
        t.eq(api.translated("START!", "COMENZAR!"), "START!", "English returns the key")
        api.set_language(1)
        t.eq(api.translated("START!", "COMENZAR!"), "COMENZAR!", "Spanish returns the es argument")
    end)

    s.test("every other language resolves through its own dictionary", function()
        local api = harness.load()
        for index = 2, 5 do
            local code = api.language_codes[index + 1]
            local dictionary = api.ui_translations[code]
            t.ok(dictionary ~= nil, "no ui_translations entry for " .. tostring(code))
            local checked = 0
            for key, value in pairs(dictionary) do
                api.set_language(index)
                t.eq(api.translated(key, "unused"), value, string.format(
                    "%s: key %q", code, key))
                checked = checked + 1
            end
            t.ok(checked > 0, code .. ": dictionary is empty")
        end
    end)

    s.test("an unknown key falls back to English in every language", function()
        local api = harness.load()
        for index = 0, 5 do
            api.set_language(index)
            t.eq(api.translated("NO SUCH KEY", "NI ESA CLAVE"),
                index == 1 and "NI ESA CLAVE" or "NO SUCH KEY",
                "language index " .. index .. " fallback")
        end
    end)

    s.test("no dictionary entry is empty or non-textual", function()
        local api = harness.load()
        local tables = {
            ui_translations = api.ui_translations,
            modifier_translations = api.modifier_translations,
            boss_modifier_translations = api.boss_modifier_translations,
        }
        for name, per_code in pairs(tables) do
            for code, dictionary in pairs(per_code) do
                for key, value in pairs(dictionary) do
                    t.eq(type(value), "string", string.format(
                        "%s.%s[%q] is not a string", name, code, tostring(key)))
                    t.ne(value, "", string.format(
                        "%s.%s[%q] is empty", name, code, tostring(key)))
                end
            end
        end
    end)

    s.test("the menu lock label covers all six languages", function()
        local api = harness.load()
        t.eq(#api.menu_lock_labels, 6, "one locked-menu label per language")
        for index = 0, 5 do
            local label = api.menu_lock_labels[index + 1]
            t.eq(type(label), "string", "menu lock label for index " .. index)
            t.ne(label, "", "menu lock label " .. index .. " is empty")
        end
    end)

    s.test("a translation keeps the colon count of its English key", function()
        -- FONT_HUD draws ':' as an 'X', so colon-bearing text has to go through
        -- draw_hud_text, which splits at each colon and draws two dots instead.
        -- Colons in a translation are therefore fine -- several English keys
        -- already contain one -- but adding or dropping one relative to the key
        -- changes how the string is split and is a translation bug. All 180
        -- entries match today.
        local api = harness.load()
        local function colons(text) return select(2, text:gsub(":", "")) end
        for code, dictionary in pairs(api.ui_translations) do
            for key, value in pairs(dictionary) do
                t.eq(colons(value), colons(key), string.format(
                    "ui_translations.%s[%q] = %q: colon count differs from the key",
                    code, tostring(key), value))
            end
        end
    end)
end
