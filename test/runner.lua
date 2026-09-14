-- Small test runner: suites, assertions, and a non-zero exit on failure.

local runner = { suites = {} }

function runner.suite(name)
    local suite = { name = name, tests = {} }
    function suite.test(title, fn)
        suite.tests[#suite.tests + 1] = { title = title, fn = fn }
    end
    runner.suites[#runner.suites + 1] = suite
    return suite
end

-- assertions ----------------------------------------------------------------

local function describe(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "table" then
        local parts = {}
        for i, v in ipairs(value) do parts[i] = tostring(v) end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end

function runner.fail(msg)
    error({ starhunt_assert = true, message = msg }, 2)
end

function runner.ok(condition, msg)
    if not condition then
        error({ starhunt_assert = true, message = msg or "expected a truthy value" }, 2)
    end
end

function runner.eq(actual, expected, msg)
    if actual ~= expected then
        error({ starhunt_assert = true, message = string.format("%sexpected %s, got %s",
            msg and (msg .. ": ") or "", describe(expected), describe(actual)) }, 2)
    end
end

function runner.ne(actual, unexpected, msg)
    if actual == unexpected then
        error({ starhunt_assert = true, message = string.format("%sexpected anything but %s",
            msg and (msg .. ": ") or "", describe(unexpected)) }, 2)
    end
end

function runner.near(actual, expected, tolerance, msg)
    if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
        error({ starhunt_assert = true, message = string.format("%sexpected %s +/- %s, got %s",
            msg and (msg .. ": ") or "", tostring(expected), tostring(tolerance),
            describe(actual)) }, 2)
    end
end

function runner.is_nil(actual, msg)
    if actual ~= nil then
        error({ starhunt_assert = true, message = string.format("%sexpected nil, got %s",
            msg and (msg .. ": ") or "", describe(actual)) }, 2)
    end
end

-- execution ------------------------------------------------------------------

function runner.run()
    local passed, failed, failures = 0, 0, {}
    local started = os.clock()

    for _, suite in ipairs(runner.suites) do
        io.write(suite.name, "\n")
        for _, t in ipairs(suite.tests) do
            local ok, err = pcall(t.fn)
            if ok then
                passed = passed + 1
                io.write("  ok    ", t.title, "\n")
            else
                failed = failed + 1
                local message
                if type(err) == "table" and err.starhunt_assert then
                    message = err.message
                else
                    message = "error: " .. tostring(err)
                end
                io.write("  FAIL  ", t.title, "\n          ", message, "\n")
                failures[#failures + 1] = suite.name .. " / " .. t.title .. "\n    " .. message
            end
        end
    end

    io.write(string.format("\n%d passed, %d failed  (%.2fs)\n", passed, failed,
        os.clock() - started))
    if failed > 0 then
        io.write("\nfailures:\n")
        for _, f in ipairs(failures) do io.write("  ", f, "\n") end
        return false
    end
    return true
end

return runner
