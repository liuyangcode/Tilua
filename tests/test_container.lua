--- Smoke tests for Tilua.core.container (pure Lua, no ngx required).
--- Run:  resty -I <repo-root> tests/test_container.lua
--- or:   docker run --rm -v <repo>:/app -w /app openresty/openresty:alpine \
---            resty tests/test_container.lua

local package = package

package.path = "./?.lua;./?/init.lua;" .. (package.path or "")

local Container = require("Tilua.core.container")

local failures = 0
local checks = 0

local function ok(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

local function eq(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        failures = failures + 1
        io.stderr:write(string.format(
            "FAIL: %s\n  expected: %s\n  actual:   %s\n",
            label, tostring(expected), tostring(actual)))
    end
end

local function contains(list, value, label)
    checks = checks + 1
    local found = false
    for _, v in ipairs(list) do
        if v == value then
            found = true
            break
        end
    end
    if not found then
        failures = failures + 1
        io.stderr:write(string.format("FAIL: %s (missing %s in [%s])\n",
            label, tostring(value), table.concat(list, ",")))
    end
end

---------------------------------------------------------------
-- a fake loader so we never touch the filesystem
---------------------------------------------------------------
local loaded = {}
local function fake_loader(name)
    loaded[name] = (loaded[name] or 0) + 1
    if name == "App.Thing" then
        return function(prefix)
            return { kind = "Thing", prefix = prefix, n = loaded[name] }
        end
    end
    if name == "App.WithNew" then
        return {
            new = function(a)
                return { kind = "WithNew", a = a }
            end,
        }
    end
    if name == "App.Missing" then
        return nil
    end
    return nil
end

local function fresh()
    return Container.new({ loader = fake_loader })
end

---------------------------------------------------------------
-- 1. bind: new instance every resolve
---------------------------------------------------------------
do
    local c = fresh()
    local n = 0
    c:bind("counter", function()
        n = n + 1
        return { n = n }
    end)

    local a = c:make("counter")
    local b = c:make("counter")
    eq(a.n, 1, "bind() first resolve")
    eq(b.n, 2, "bind() second resolve creates a new instance")
    ok(a ~= b, "bind() must not cache")
    ok(c:bound("counter"), "bound() true after bind")
    ok(not c:bound("nope"), "bound() false for unknown name")
end

---------------------------------------------------------------
-- 2. singleton: resolved once
---------------------------------------------------------------
do
    local c = fresh()
    local n = 0
    c:singleton("single", function()
        n = n + 1
        return { n = n }
    end)

    local a = c:make("single")
    local b = c:make("single")
    eq(n, 1, "singleton factory runs once")
    ok(a == b, "singleton returns the same instance")
end

---------------------------------------------------------------
-- 3. instance: pre-built value wins
---------------------------------------------------------------
do
    local c = fresh()
    local obj = { tag = "given" }
    local returned = c:instance("given", obj)
    ok(returned == obj, "instance() returns the value")
    ok(c:make("given") == obj, "make() returns registered instance")
    ok(c:has("given"), "has() true for instance")
end

---------------------------------------------------------------
-- 4. alias (including a chain)
---------------------------------------------------------------
do
    local c = fresh()
    c:singleton("db.conn", function()
        return { tag = "db" }
    end)
    c:alias("db.conn", "db")        -- "db" is now another name for "db.conn"
    c:alias("db", "database")       -- chain: database -> db -> db.conn

    eq(c:alias_of("database"), "db", "alias_of reports direct target")
    ok(c:make("db") == c:make("db.conn"), "alias resolves to same instance")
    ok(c:make("database") == c:make("db"), "alias chain resolves transitively")
    ok(c:has("database"), "has() works through alias")
end

---------------------------------------------------------------
-- 5. scoped + flush lifecycle
---------------------------------------------------------------
do
    local c = fresh()
    local built, closed = 0, 0

    c:scoped("request", function()
        built = built + 1
        return {
            n = built,
            close = function(self)
                closed = closed + 1
            end,
        }
    end)

    local a = c:make("request")
    local b = c:make("request")
    eq(built, 1, "scoped resolves once per scope")
    ok(a == b, "scoped returns same instance within scope")
    eq(a.n, 1, "scoped instance identity")

    contains(c:scoped_instances(), "request", "scoped_instances lists scoped names")

    local released, err = c:flush()
    eq(released, 1, "flush releases one scoped instance")
    eq(err, nil, "flush reports no errors")
    eq(closed, 1, "flush called close() on the scoped instance")
    eq(#c:scoped_instances(), 0, "scoped_instances empty after flush")

    -- a new scope builds a fresh instance
    local d = c:make("request")
    eq(built, 2, "scoped rebuilds after flush")
    eq(d.n, 2, "rebuilt scoped instance is new")
end

---------------------------------------------------------------
-- 6. flush tolerates a broken close() and still releases others
---------------------------------------------------------------
do
    local c = fresh()
    local good_closed = false
    c:scoped("bad", function()
        return {
            close = function()
                error("boom")
            end,
        }
    end)
    c:scoped("good", function()
        return {
            close = function()
                good_closed = true
            end,
        }
    end)

    c:make("bad")
    c:make("good")

    local released, err = c:flush()
    eq(released, 2, "flush releases both scoped instances")
    ok(good_closed, "flush keeps going after a failing close()")
    ok(err ~= nil and err:find("bad", 1, true) ~= nil, "flush reports the failing service")
    eq(#c:scoped_instances(), 0, "flush clears scope even on error")
end

---------------------------------------------------------------
-- 7. defer runs LIFO and is flushed too
---------------------------------------------------------------
do
    local c = fresh()
    local order = {}
    c:defer(function() order[#order + 1] = "first" end)
    c:defer(function() order[#order + 1] = "second" end)

    c:flush()
    eq(#order, 2, "both deferred callbacks ran")
    eq(order[1], "second", "defer is LIFO (second registered runs first)")
    eq(order[2], "first", "defer is LIFO")

    c:flush()
    eq(#order, 2, "deferred callbacks do not run twice")
end

---------------------------------------------------------------
-- 8. class-like loading via the loader, with declared params
---------------------------------------------------------------
do
    local c = fresh()
    local t = c:make("App.Thing", { "px" })
    eq(t.kind, "Thing", "class-like module built")
    eq(t.prefix, "px", "constructor params are forwarded")

    -- table abstract form: { "Class", {params}, "Convention" }
    local t2 = c:make({ "Thing", { "yy" }, "App" })
    eq(t2.kind, "Thing", "table abstract built")
    eq(t2.prefix, "yy", "table abstract forwards params")

    -- new() style module
    local w = c:make({ "WithNew", { 42 }, "App" })
    eq(w.kind, "WithNew", "module with new() is instantiated")
    eq(w.a, 42, "new() receives params")
end

---------------------------------------------------------------
-- 9. missing module must raise loudly (never silently nil)
---------------------------------------------------------------
do
    local c = fresh()
    local okc, err = pcall(function()
        return c:make("App.Missing")
    end)
    ok(not okc, "make() on a missing module raises")
    ok(tostring(err):find("App.Missing", 1, true) ~= nil,
        "error message names the missing module")
end

---------------------------------------------------------------
-- 10. factory returning nil is an error, not a silent nil
---------------------------------------------------------------
do
    local c = fresh()
    c:bind("nothing", function() return nil end)
    local okc, err = pcall(function()
        return c:make("nothing")
    end)
    ok(not okc, "factory returning nil raises")
    ok(tostring(err):find("returned nil", 1, true) ~= nil, "error explains nil factory")
end

---------------------------------------------------------------
-- 11. extend decorates an existing binding
---------------------------------------------------------------
do
    local c = fresh()
    c:singleton("svc", function()
        return { tags = { "base" } }
    end)
    c:extend("svc", function(service)
        service.tags[#service.tags + 1] = "decorated"
        return service
    end)

    local s = c:make("svc")
    eq(#s.tags, 2, "extend decorator applied")
    eq(s.tags[2], "decorated", "extend ran the decorator")
end

---------------------------------------------------------------
-- 12. call() injects "$name" arguments
---------------------------------------------------------------
do
    local c = fresh()
    c:instance("db", { tag = "db" })
    c:instance("log", { tag = "log" })

    local got
    c:call(function(db, log, plain)
        got = { db.tag, log.tag, plain }
    end, { "$db", "$log", "literal" })

    eq(got[1], "db", "call injected first service")
    eq(got[2], "log", "call injected second service")
    eq(got[3], "literal", "call left plain arguments alone")
end

---------------------------------------------------------------
-- 13. forget clears both binding and cache
---------------------------------------------------------------
do
    local c = fresh()
    c:singleton("tmp", function()
        return { kind = "tmp" }
    end)
    local first = c:make("tmp")
    c:forget("tmp")
    ok(not c:has("tmp"), "forget removes the binding")
    c:singleton("tmp", function()
        return { kind = "tmp2" }
    end)
    local second = c:make("tmp")
    ok(first ~= second, "forget cleared the cached singleton")
    eq(second.kind, "tmp2", "re-binding takes effect")
end

---------------------------------------------------------------
-- 14. binding can resolve another binding (declared injection)
---------------------------------------------------------------
do
    local c = fresh()
    c:singleton("config", function()
        return { name = "Tilua" }
    end)
    c:singleton("greeter", function(container)
        return {
            greet = function()
                return "hi " .. container:make("config").name
            end,
        }
    end)
    eq(c:make("greeter"):greet(), "hi Tilua", "one binding may resolve another")
end

---------------------------------------------------------------
-- 15. value() is never treated as a factory
---------------------------------------------------------------
do
    local c = fresh()
    c:value("flag", false)          -- falsy value must survive
    eq(c:make("flag"), false, "value() keeps false")
end

---------------------------------------------------------------
-- 16. alias cycle is detected instead of hanging
---------------------------------------------------------------
do
    local c = fresh()
    c._aliases["a"] = "b"
    c._aliases["b"] = "a"
    local okc = pcall(function()
        return c:make("a")
    end)
    ok(not okc, "alias cycle raises instead of looping forever")
end

---------------------------------------------------------------
-- 17. table abstract with a convention prefix
---------------------------------------------------------------
do
    local c = fresh()
    local t = c:make({ "Thing", {}, "App" })
    eq(t.kind, "Thing", "empty params table is accepted")
    eq(t.prefix, nil, "no params forwarded when params table is empty")
end

---------------------------------------------------------------
print(string.format("container tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("container smoke tests passed")
