--- Action annotations: `@route` / `@middleware` / `@phases`.
---
--- An action's HTTP method and middleware can be declared in the comment block
--- immediately above it.  An annotated action uses the annotation; an
--- unannotated one keeps the `GET /<controller>/<action>` default, so adding
--- annotations never changes the routes you did not touch.
---
--- Run: luajit tests/support/lua_stub.lua tests/test_annotations.lua

package.path = "./tests/fixtures/?.lua;./tests/fixtures/?/init.lua;"
            .. "./?.lua;./?/init.lua;" .. (package.path or "")

local failures, checks = 0, 0

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
        io.stderr:write(string.format("FAIL: %s\n  expected: %s\n  actual:   %s\n",
            label, tostring(expected), tostring(actual)))
    end
end

local discovery = require("Tilua.core.discovery")

local function methods_of(entry)
    if not entry or not entry.routes then return "-" end
    local out = {}
    for _, r in ipairs(entry.routes) do
        out[#out + 1] = table.concat(r.methods, ",")
    end
    return table.concat(out, "|")
end

local function paths_of(entry)
    if not entry or not entry.routes then return "-" end
    local out = {}
    for _, r in ipairs(entry.routes) do
        out[#out + 1] = tostring(r.path)
    end
    return table.concat(out, "|")
end

local function middleware_names(entry)
    if not entry or not entry.middleware then return "-" end
    local out = {}
    for _, m in ipairs(entry.middleware) do out[#out + 1] = tostring(m[1]) end
    return table.concat(out, ",")
end

----------------------------------------------------------------------
-- 1. the parser, on a synthetic source
----------------------------------------------------------------------
do
    local src = [[
local controller = require("Tilua.controller")
local C = controller.define()

--- @route GET /a/{id}
--- @route POST /a
--- @middleware auth
--- @middleware rate_limit, { limit = 10 }
--- @phases access = admin_guard
function C:one(id) end

--- @route PUT /b
function C:two() end

function C:three() end
]]

    local ann, errs = discovery.parse_annotations(src)
    eq(#errs, 0, "a clean source parses without errors")

    ok(ann.one ~= nil, "action 'one' has annotations")
    eq(methods_of(ann.one), "GET|POST",
        "each @route directive is kept as its own record")
    eq(paths_of(ann.one), "/a/{id}|/a",
        "each @route keeps its OWN path (they may differ)")
    eq(middleware_names(ann.one), "auth,rate_limit", "@middleware accumulates")
    eq(ann.one.middleware[2][2].limit, 10,
        "a middleware config table is parsed, not stringified")
    ok(ann.one.phases ~= nil and ann.one.phases.access ~= nil,
        "@phases records the phase")
    eq(ann.one.phases.access[1][1], "admin_guard", "@phases keeps the middleware name")

    eq(methods_of(ann.two), "PUT", "a single @route with an explicit path")
    eq(paths_of(ann.two), "/b", "the path is recorded")

    eq(ann.three, nil, "an unannotated action has no entry")
end

----------------------------------------------------------------------
-- 1b. the short form: a bare lowercase verb is the directive
----------------------------------------------------------------------
do
    local src = [[
--- @get /short/one
--- @post /short/two
--- @put
--- @delete /short/four
function C:verbs() end
]]

    local ann, errs = discovery.parse_annotations(src)
    eq(#errs, 0, "the short form parses without errors")

    eq(methods_of(ann.verbs), "GET|POST|PUT|DELETE",
        "each bare verb is its own route record")
    eq(paths_of(ann.verbs), "/short/one|/short/two|nil|/short/four",
        "a bare verb without a path falls back to the convention path")

    -- every verb is accepted
    local all = [[
--- @get
--- @post
--- @put
--- @delete
--- @patch
--- @head
--- @options
function C:all() end
]]
    local ann_all, errs_all = discovery.parse_annotations(all)
    eq(#errs_all, 0, "every supported verb is accepted")
    eq(methods_of(ann_all.all), "GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS",
        "all seven verbs parse")

    -- a missing leading slash is normalised, or the route key would be
    -- unreachable
    local ann_slash = discovery.parse_annotations([[
--- @get users/{id}
function C:slash() end
]])
    eq(paths_of(ann_slash.slash), "/users/{id}",
        "a path without a leading slash is normalised")

    -- the short form and the long form mix freely
    local mixed = discovery.parse_annotations([[
--- @get /mixed/a
--- @route post /mixed/b
function C:mixed() end
]])
    eq(methods_of(mixed.mixed), "GET|POST",
        "the short and long forms combine in declaration order")
    eq(paths_of(mixed.mixed), "/mixed/a|/mixed/b", "paths follow declaration order")
end

----------------------------------------------------------------------
-- 1c. `@GET` is not a directive (case matters)
----------------------------------------------------------------------
do
    local _, errs = discovery.parse_annotations([[
--- @GET /upper
function C:upper() end
]])
    ok(#errs > 0, "an uppercase verb is reported, not silently accepted")
    ok(errs[1] and errs[1]:find("GET", 1, true) ~= nil,
        "the error names the offending directive")
end

----------------------------------------------------------------------
-- 2. `@route METHOD` without a path keeps the convention path
----------------------------------------------------------------------
do
    local src = [[
--- @route DELETE
function C:remove() end
]]
    local ann = discovery.parse_annotations(src)
    eq(methods_of(ann.remove), "DELETE", "a bare method is accepted")
    eq(paths_of(ann.remove), "nil", "no path means 'use the default'")
end

----------------------------------------------------------------------
-- 3. method lists, case, and bad methods
----------------------------------------------------------------------
do
    local ann = discovery.parse_annotations([[
--- @route get,post /pair
function C:pair() end
]])
    eq(methods_of(ann.pair), "GET,POST", "a comma-separated method list is uppercased")

    local _, errs = discovery.parse_annotations([[
--- @route WRONG /bad
function C:bad() end
]])
    ok(#errs > 0, "an unknown HTTP method is reported")
    ok(errs[1] and errs[1]:find("WRONG", 1, true) ~= nil,
        "the error names the offending method")
end

----------------------------------------------------------------------
-- 4. unknown directives are reported, not ignored
----------------------------------------------------------------------
do
    local _, errs = discovery.parse_annotations([[
--- @route GET /x
--- @nonsense value
function C:x() end
]])
    ok(#errs > 0, "an unknown annotation is reported")
    ok(errs[1] and errs[1]:find("nonsense", 1, true) ~= nil,
        "the error names the unknown directive")
end

----------------------------------------------------------------------
-- 5. block comments and blank-line separation do not leak annotations
----------------------------------------------------------------------
do
    local ann = discovery.parse_annotations([=[
--[[
--- @route POST /should-not-apply
]]
function C:blockdoc() end
]=])
    eq(ann.blockdoc, nil,
        "a --[[ ]] block comment is documentation, not an annotation")

    local ann2 = discovery.parse_annotations([=[
--- @route POST /separated

function C:separated() end
]=])
    eq(ann2.separated, nil,
        "a blank line breaks the annotation block")
end

----------------------------------------------------------------------
-- 6. the whole thing end to end over the fixture controller
----------------------------------------------------------------------
do
    package.loaded["Tilua.http.router"] = nil
    local router = require("Tilua.http.router")
    router.set_app_name("TestApp")

    local report = discovery.scan(
        { name = "TestApp", path = "./tests/fixtures/TestApp" }, router,
        { dir = "./tests/fixtures/TestApp/controller" })

    ok(#report.errors == 2,
        "exactly the two deliberate annotation errors are reported (got "
        .. #report.errors .. ": " .. table.concat(report.errors, " | ") .. ")")

    local by_path = {}
    for _, r in ipairs(router.get_route_caches("TestApp") or {}) do
        local m = type(r.method) == "table" and table.concat(r.method, ",") or tostring(r.method)
        by_path[m .. " " .. tostring(r.path)] = r
    end

    local function has(key) return by_path[key] ~= nil end

    -- (a) unannotated action keeps the default
    ok(has("GET /annotated/plain"), "an unannotated action keeps GET /<c>/<a>")

    -- (b) one rule per @route method, each with its own path
    ok(has("GET /ann/read/{id}"), "@route GET with a path is registered")
    ok(has("POST /ann/create"), "the second @route is registered separately")

    -- (c) bare method keeps the convention path
    ok(has("PUT /annotated/limited"), "@route PUT without a path uses the default path")

    -- (d) method list expands to one rule per method
    ok(has("GET /ann/pair"), "a method list registers GET")
    ok(has("POST /ann/pair"), "a method list registers POST")

    -- (e) @phases becomes phase middleware
    local guarded = by_path["DELETE /ann/remove/{id}"]
    ok(guarded ~= nil, "@route is honoured together with @phases")
    if guarded then
        eq(type(guarded.phases), "table", "@phases is attached to the rule")
        if type(guarded.phases) == "table" and guarded.phases.access then
            eq(guarded.phases.access[1][1], "admin_guard",
                "the access-phase middleware is recorded")
        end
    end

    -- (f) @middleware becomes the content-phase middleware list
    local multi = by_path["GET /ann/read/{id}"]
    if multi then
        ok(type(multi.midware) == "table" and #multi.midware == 1,
            "@middleware is attached to the rule")
        if type(multi.midware) == "table" and multi.midware[1] then
            eq(multi.midware[1][1], "auth", "the middleware name is recorded")
        end
    end

    -- (g) @middleware and @phases together populate both slots
    local both = by_path["GET /ann/both"]
    if both then
        ok(type(both.midware) == "table", "@middleware and @phases coexist")
        ok(type(both.phases) == "table", "the phase config coexists with middleware")
    else
        ok(false, "the action annotated with both is registered")
    end

    -- (h) every discovered rule stays marked scanned (explicit still wins)
    if multi then
        eq(multi.source, "scanned", "annotated routes are still 'scanned'")
    end

    -- (i) an invalid method did not register a route under the bogus verb
    ok(not has("WRONG /ann/bad"), "a bad method registers nothing")

    -- (j) block-comment and blank-line annotations did not apply
    ok(has("GET /annotated/blockdoc"),
        "the block-comment action keeps its default route")
    ok(not has("POST /ann/should-not-apply"),
        "an annotation inside a block comment is ignored")
    ok(has("GET /annotated/separated"),
        "a blank-line-separated annotation does not apply")

    -- (k) private actions are not registered even when annotated
    ok(not has("GET /ann/private"), "a private action with an annotation is skipped")
end

----------------------------------------------------------------------
-- 7. the `unannotated` switch
----------------------------------------------------------------------
do
    local function fresh_router()
        package.loaded["Tilua.http.router"] = nil
        local router = require("Tilua.http.router")
        router.set_app_name("TestApp")
        return router
    end

    local function paths_of_router(router)
        local out = {}
        for _, r in ipairs(router.get_route_caches("TestApp") or {}) do
            local m = type(r.method) == "table" and table.concat(r.method, ",") or tostring(r.method)
            out[m .. " " .. tostring(r.path)] = true
        end
        return out
    end

    local header = { name = "TestApp", path = "./tests/fixtures/TestApp" }
    local dir = "./tests/fixtures/TestApp/controller"

    -- (a) default is TRUE: an unannotated action keeps its convention route
    local r1 = fresh_router()
    local rep1 = discovery.scan(header, r1, { dir = dir })
    ok(paths_of_router(r1)["GET /annotated/plain"],
        "with the default, an unannotated action is registered")
    eq(rep1.unannotated_skipped, nil, "nothing is reported as skipped by default")

    -- (b) default is TRUE even when unannotated is passed as nil explicitly
    local r1b = fresh_router()
    discovery.scan(header, r1b, { dir = dir, unannotated = nil })
    ok(paths_of_router(r1b)["GET /annotated/plain"],
        "an explicit nil keeps the default of true")

    -- (c) unannotated = false: only annotated actions are registered
    local r2 = fresh_router()
    local rep2 = discovery.scan(header, r2, { dir = dir, unannotated = false })
    local p2 = paths_of_router(r2)

    ok(not p2["GET /annotated/plain"],
        "with unannotated = false, an unannotated action is NOT registered")
    ok(p2["GET /ann/read/{id}"], "an annotated action is still registered")
    ok(p2["POST /ann/create"], "every annotation of that action is registered")
    ok(p2["PUT /annotated/limited"],
        "a bare-verb annotation is registered even without a path")
    ok(not p2["GET /annotated/widget"],
        "widget.lua's unannotated actions are not registered either")

    -- (d) the omission is reported, not silent
    ok((rep2.unannotated_skipped or 0) > 0,
        "skipped unannotated actions are counted")
    local msg = table.concat(rep2.skipped, " | ")
    ok(msg:find("plain", 1, true) ~= nil,
        "the skip names the action so it can be found: " .. msg)
    ok(msg:find("no route annotation", 1, true) ~= nil,
        "the skip explains why")

    -- (e) annotated-only mode does not turn a skip into an error
    eq(#rep2.errors, 2,
        "only the two deliberate annotation errors are reported (got "
        .. #rep2.errors .. ")")

    -- (f) Explicit routes are unaffected by the switch
    package.loaded["Tilua.http.router"] = nil
    local r3 = require("Tilua.http.router")
    r3.set_app_name("TestApp")
    local explicit = function() return "E" end
    r3.get("/annotated/plain", explicit)
    r3.init_rule_caches({})
    discovery.scan(header, r3, { dir = dir, unannotated = false })
    local rule = r3.match("TestApp", "get", "/annotated/plain")
    ok(rule ~= nil, "an explicitly registered route survives unannotated = false")
    eq(rule and rule.responser, explicit, "and it is still the explicit handler")
end

----------------------------------------------------------------------
print(string.format("annotation tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("annotation tests passed")
