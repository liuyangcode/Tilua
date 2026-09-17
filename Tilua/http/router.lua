--- Tilua.http.router
--- Trie-based HTTP router.
---
--- Matching model
---   * Static segments are matched through a segment trie: O(number of path
---     segments), independent of how many routes are registered.
---   * `{name}` captures exactly one segment.
---   * `*` matches all remaining segments (anonymous); `{name*}` names it.
---   * `~ <pattern>` regex routes are kept in a flat fallback list.  Arbitrary
---     regular expressions cannot live in a trie, and a trie killed the class of
---     bugs where a pattern silently matched far more than intended.
---
--- Precedence, per segment: static > `{name}` > `*`.
--- Static wins outright, which is what makes `/user/new` beat `/user/{id}`
--- without any registration-order dependence.
---
--- Wildcards are terminal by design.  A `*`/`{name*}` node is only considered
--- once the whole path is consumed, so `/files/*` cannot shadow `/files/a/b`
--- and `/files/c` in a surprising way — the specific route still wins.
---
--- This replaces a matcher that defaulted to `*` (prefix) for every rule, which
--- meant `/nope` matched the `/` rule and `{name}` routes never compiled to a
--- regex at all.

local ngx = ngx
if not ngx then
    -- Pure-Lua harnesses (tests/support/lua_stub.lua) provide ngx already; this
    -- branch only guards direct requires.
    ngx = { re = {} }
end

local string, table = string, table
local string_sub = string.sub
local string_find = string.find
local string_lower = string.lower
local string_gsub = string.gsub
local table_insert = table.insert
local table_concat = table.concat
local unpack = table.unpack or unpack

local helpers = require("Tilua.core.helpers")
local strip = helpers.strip
local split = helpers.split
local lw_util = require("Tilua.utils.util")
local midware_manager = require("Tilua.middleware")

local stringx = {
    strip = strip,
    split = function(s, sep) return split(s, sep or ",", true) end,
}

--- tablex-compatible shim (append group middleware to the front of a list)
local tablex = {
    find = helpers.find,
    sub = helpers.sub,
    insertvalues = helpers.insertvalues,
    deepcopy = helpers.deepcopy,
    move = function(dst, src)
        if type(src) == "table" then
            for i = #src, 1, -1 do
                table.insert(dst, 1, src[i])
            end
        end
        return dst
    end,
}

-----------------------------------------------------------------------
-- path utilities
-----------------------------------------------------------------------

--- Split a path into non-empty segments.
--- "/user/ada/" -> { "user", "ada" }
local function path_segments(path)
    local out = {}
    if type(path) ~= "string" or path == "" then
        return out
    end
    for seg in string.gmatch(path, "[^/]+") do
        out[#out + 1] = seg
    end
    return out
end

--- Normalise a path for matching: collapse duplicate slashes and drop the
--- trailing slash, so "/user/ada/" and "/user/ada" are the same route.
local function normalize_path(path)
    path = tostring(path or "/")
    if path == "" then
        path = "/"
    end
    path = string_gsub(path, "/+", "/")
    if #path > 1 and string_sub(path, -1) == "/" then
        path = string_sub(path, 1, -2)
    end
    return path
end

--- Classify one route-path segment.
--- @return string kind  "static" | "param" | "wildcard"
--- @return string value  literal text, or the parameter name
local function classify_segment(seg)
    local first = string_sub(seg, 1, 1)

    if first == "{" and string_sub(seg, -1) == "}" then
        local inner = string_sub(seg, 2, -2)
        local name, star = inner:match("^([%w_]*)(%*?)$")
        if star == "*" then
            return "wildcard", (name ~= "" and name or "splat")
        end
        return "param", (name ~= "" and name or "param")
    end

    if seg == "*" then
        return "wildcard", "splat"
    end

    return "static", seg
end

--- Compile a route path into trie segments.
--- @return table segments  { { kind=..., value=... }, ... }
--- @return table args      ordered parameter names (plus "splat" for a wildcard)
local function compile_path(path)
    local segments, args = {}, {}
    for _, seg in ipairs(path_segments(path)) do
        local kind, value = classify_segment(seg)
        segments[#segments + 1] = { kind = kind, value = value }
        if kind == "param" or kind == "wildcard" then
            args[#args + 1] = value
        end
    end
    return segments, args
end

-----------------------------------------------------------------------
-- trie
-----------------------------------------------------------------------

local function new_node()
    return {
        static   = nil,   -- [literal] = node
        param    = nil,   -- { name, node }
        wildcard = nil,   -- { name, node }  (node holds its rules)
        rules    = nil,   -- array of terminal rules (one per method)
    }
end

local function new_trie()
    return { root = new_node() }
end

--- Insert a rule at the given compiled segments.
--- If a dynamic position already exists with a different name, the existing
--- name wins so that `/user/{id}` and `/user/{name}` cannot silently capture
--- under two names.
local function trie_insert(trie, segments, args, rule)
    local node = trie.root

    for _, seg in ipairs(segments) do
        if seg.kind == "static" then
            node.static = node.static or {}
            if not node.static[seg.value] then
                node.static[seg.value] = new_node()
            end
            node = node.static[seg.value]

        elseif seg.kind == "param" then
            if not node.param then
                node.param = { name = seg.value, node = new_node() }
            end
            node = node.param.node

        else -- wildcard: terminal
            if not node.wildcard then
                node.wildcard = { name = seg.value, node = new_node() }
            end
            node = node.wildcard.node
            node.rules = node.rules or {}
            node.rules[#node.rules + 1] = rule
            return rule
        end
    end

    node.rules = node.rules or {}
    node.rules[#node.rules + 1] = rule
    return rule
end

--- Pick the rule at `node` that accepts `method`.
--- Several methods commonly share one path, so a node holds a list.
local function pick_rule(node, method, accepts)
    local rules = node and node.rules
    if not rules then
        return nil
    end
    for _, r in ipairs(rules) do
        if accepts(r, method) then
            return r
        end
    end
    return nil
end

--- Match `segs` (array of path segments) against the trie.
---
--- Captures are keyed by the parameter names **on the matched path**, not by the
--- names declared on the rule.  A trie stores one `param` slot per node, so
--- `/user/{id}` and `/user/{name}` share a node and the first registered name
--- would otherwise be applied to every rule: the second route was silently
--- unreachable (`rule.args` said `name`, the traverse captured `id`, and the
--- dispatcher bound `nil`).  Walks accumulate an ordered name list instead.
---
--- @param method string already lowercased
--- @param accepts function(rule, method) -> boolean
--- @return table|nil rule, table captures
local function trie_match(trie, segs, method, accepts)
    local function walk(node, i, names, values)
        -- Whole path consumed: accept a terminal rule, else a wildcard that
        -- matches the empty remainder.
        if i > #segs then
            local hit = pick_rule(node, method, accepts)
            if hit then
                return hit, names, values
            end
            local wc = node.wildcard
            if wc then
                local wh = pick_rule(wc.node, method, accepts)
                if wh then
                    local n2, v2 = {}, {}
                    for k = 1, #names do n2[k], v2[k] = names[k], values[k] end
                    n2[#n2 + 1], v2[#v2 + 1] = wc.name, ""
                    return wh, n2, v2
                end
            end
            return nil
        end

        local seg = segs[i]

        -- 1. static (highest precedence)
        local child = node.static and node.static[seg]
        if child then
            local rule, n, v = walk(child, i + 1, names, values)
            if rule then
                return rule, n, v
            end
        end

        -- 2. `{name}` single-segment parameter
        if node.param then
            names[#names + 1] = node.param.name
            values[#values + 1] = seg
            local rule, n, v = walk(node.param.node, i + 1, names, values)
            if rule then
                return rule, n, v
            end
            -- backtrack
            names[#names] = nil
            values[#values] = nil
        end

        -- 3. `*` / `{name*}` swallows the remainder
        if node.wildcard then
            local wh = pick_rule(node.wildcard.node, method, accepts)
            if wh then
                local n2, v2 = {}, {}
                for k = 1, #names do n2[k], v2[k] = names[k], values[k] end
                n2[#n2 + 1] = node.wildcard.name
                v2[#v2 + 1] = table_concat(segs, "/", i)
                return wh, n2, v2
            end
        end

        return nil
    end

    local rule, names, values = walk(trie.root, 1, {}, {})
    if not rule then
        return nil
    end

    local captures = {}
    for i = 1, #names do
        captures[names[i]] = values[i]
    end

    -- A rule may also declare argument names that differ from the registered
    -- path's (e.g. `/user/{id}` registered while the rule says `name`).  Expose
    -- those too, positionally, so neither naming style reads as nil.
    for i, name in ipairs(rule.args or {}) do
        if captures[name] == nil and values[i] ~= nil then
            captures[name] = values[i]
        end
    end

    return rule, captures
end

-----------------------------------------------------------------------
-- per-app index
-----------------------------------------------------------------------

local route = {
    cur_app = "",
    rules = {},        -- [app] = { ["get /path"] = { handler, path, midware } }
    rule_caches = {},  -- [app] = array of compiled rule objects
    indexes = {},      -- [app] = { trie, regex }
}

--- Mutable runtime state that must NOT be written as `route.X = ...`.
---
--- The module metatable defines `__newindex` to implement the
--- `route["GET /x"] = handler` shorthand, and that hook fires for EVERY
--- assignment to a key the table does not already own — including internal
--- bookkeeping.  So `route.cur_app = name` and `route._group_midwares = mw`
--- were silently converted into route registrations instead of being stored,
--- which broke `set_app_name` and `route.group` middleware inheritance.
---
--- Group state lives here because this table already exists.
---
--- `_rule_seq` records the declaration index of each declarative rule key, and
--- `_next_rule_seq` hands out the next one.  They must be pre-created here so
--- that assigning to them later is a plain store rather than a `__newindex`
--- call that would register a bogus route.
route._rule_seq = {}
route._next_rule_seq = 0
route._group = { midwares = nil }

-----------------------------------------------------------------------
-- method helpers
-----------------------------------------------------------------------

function route.method_set(methods)
    local s = {}
    if type(methods) ~= "table" then
        methods = { methods or "*" }
    end
    for _, m in ipairs(methods) do
        s[string_lower(tostring(m))] = true
    end
    return s
end

--- Does a rule accept this (already lowercased) method?
local function accepts_method(rule, method)
    local ms = rule._method_set
    if not ms then
        ms = route.method_set(rule.method)
        rule._method_set = ms
    end
    return ms["*"] == true or ms[method] == true
end

--- Build (or rebuild) the index for an app from `rule_caches`.
local function build_index(app)
    local list = route.rule_caches[app] or {}
    local trie = new_trie()
    local regex = {}

    for _, rule in ipairs(list) do
        local matcher = rule.matcher

        if matcher == "~" then
            -- Parameterised paths keep the "~" matcher (for the validation DSL)
            -- but are still trie-matched; only true regex patterns fall back.
            local segs, args = compile_path(rule.path)
            local parameterised = false
            for _, s in ipairs(segs) do
                if s.kind ~= "static" then
                    parameterised = true
                    break
                end
            end

            if parameterised then
                rule.args = args
                trie_insert(trie, segs, args, rule)
            else
                -- A `~` rule with no parameter segments is a genuine regex
                -- pattern and cannot live in a trie.  Compile it before adding
                -- it to the fallback list: `route.match` calls
                -- `ngx.re.match(path, rule.regex)` and would otherwise pass nil.
                if rule.regex == nil then
                    local _, regex = route.parse_path_to_regex(rule.path)
                    rule.regex = regex
                end
                if rule.args == nil then
                    rule.args = args
                end
                regex[#regex + 1] = rule
            end

        elseif matcher == "*" then
            -- Prefix route, e.g. "* /api". Compiled as a trailing wildcard so
            -- it still participates in the trie with correct precedence.
            local segs, args = compile_path(rule.path)
            segs[#segs + 1] = { kind = "wildcard", value = "splat" }
            args[#args + 1] = "splat"
            rule.args = args
            rule.prefix = normalize_path(rule.path)
            trie_insert(trie, segs, args, rule)

        else -- "=" exact (also `{name}` paths)
            local segs, args = compile_path(rule.path)
            rule.args = args
            trie_insert(trie, segs, args, rule)
        end
    end

    route.indexes[app] = { trie = trie, regex = regex }
    return route.indexes[app]
end

local function get_index(app)
    return route.indexes[app] or build_index(app)
end

function route.set_app_name(name)
    -- rawset: a plain assignment would be swallowed by __newindex
    rawset(route, "cur_app", name)
    route.rules[name] = {}
    route.rule_caches[name] = {}
    route.indexes[name] = nil
    -- A new app starts a fresh declaration sequence so its rules compile in
    -- the order the app declared them.
    route._rule_seq = {}
    route._next_rule_seq = 0
end

--- Compile `route.rules[app]` (the declarative `{ ["get /path"] = handler }`
--- shape) into rule objects.
---
--- Registration order is explicit and deterministic.  `route.rules[app]` is a
--- hash table, so iterating it with `pairs` produced a different rule order in
--- every process — and when two routes share a trie shape but differ in
--- parameter name or validation (`/user/{id}` vs `/user/{name}`), the
--- per-process order decided which one was reachable and which validation ran.
--- Rules are therefore collected with their declaration index and sorted.
function route.init_rule_caches(config_rules)
    local app = route.cur_app
    lw_util.extend(route.rules[app], config_rules or {})

    local pending = {}
    for location, result in pairs(route.rules[app]) do
        pending[#pending + 1] = { location, result, route._next_rule_seq }
        route._next_rule_seq = route._next_rule_seq + 1
    end
    table.sort(pending, function(a, b)
        if route._rule_seq[a[1]] ~= route._rule_seq[b[1]] then
            return route._rule_seq[a[1]] < route._rule_seq[b[1]]
        end
        return a[1] < b[1]
    end)

    for _, entry in ipairs(pending) do
        local location, result = entry[1], entry[2]
        local method, matcher, url, validation = route.parse_rule(location)
        local rule = route.to_router(result, url)
        rule.matcher = matcher
        rule.method = method
        rule._method_set = route.method_set(method)
        rule.validation = validation
        table_insert(route.rule_caches[app], rule)
    end

    build_index(app)
    return route.indexes[app]
end

function route.add_route_rule(cur_app, rule)
    if rule and not rule._method_set then
        rule._method_set = route.method_set(rule.method)
    end
    table_insert(route.rule_caches[cur_app], rule)
    build_index(cur_app)
end

--- Remove rules flagged as `api` (gateway-provided) and rebuild.
function route.clear_route_rule(cur_app)
    local rules = route.rule_caches[cur_app]
    if not rules then
        return
    end
    local kept = {}
    for _, v in ipairs(rules) do
        if not v.api then
            kept[#kept + 1] = v
        end
    end
    route.rule_caches[cur_app] = kept
    build_index(cur_app)
end

function route.get_route_caches(app)
    return route.rule_caches[app] or {}
end

function route.rebuild_index(app)
    return build_index(app or route.cur_app)
end

-----------------------------------------------------------------------
-- rule DSL parsing
-----------------------------------------------------------------------

function route.parse_rule(location)
    location = strip(location, ' ')
    if ngx.re and ngx.re.gsub then
        location = ngx.re.gsub(location, "%s+", ' ', 'jo')
    else
        location = string_gsub(location, "%s+", ' ')
    end

    local parts = split(location, '%s+')
    local a1, a2, a3 = parts[1], parts[2], parts[3]

    local method, route_url, validation
    local bare_matcher = nil

    -- Two accepted shapes:
    --   "<method> <path> [validation]"       e.g. "get /x", "get ~/x/(%d+)"
    --   "<matcher> [path] [validation]"      e.g. "* /api", "~ /re", "/x"
    -- The second form starts with a bare matcher symbol.
    if a1 == '*' or a1 == '~' or a1 == '=' then
        bare_matcher = a1
        method = '*'
        route_url = a2 or "/"
        validation = a3
    else
        method = a1
        route_url = a2
        validation = a3
        if not route_url then
            route_url = method
            method = '*'
        end
    end

    -- Optional matcher prefix: "=" exact, "*" prefix, "~" regex.
    -- Also: any `{name}`/`{name*}` segment makes the rule parameterised, which
    -- uses the "~" matcher so the per-parameter validation DSL
    -- (`id:reg,[0-9]+`) keeps working — the trie still matches structurally.
    local matchers_map = { ['='] = '=', ['~'] = '~', ['*'] = '*' }
    local first = string_sub(route_url, 1, 1)
    local matchers

    if matchers_map[first] then
        matchers = matchers_map[first]
        route_url = string_sub(route_url, 2)
    else
        matchers = bare_matcher or '='
    end

    if matchers == '~' or matchers == '=' then
        -- A declared parameter makes this a parameterised route.
        local _, param_args = compile_path(route_url)
        if #param_args > 0 then
            matchers = '~'
        end
    end

    if matchers == '~' then
        validation = route.parse_validation(validation)
    end
    method = stringx.split(method, ',')
    return method, matchers, route_url, validation
end

---@param validation string like uid:reg,[0-9]+
function route.parse_validation(validation)
    if not validation then
        return nil
    end
    local validation_parsed = lw_util.parse_expression(validation, ';', ':', ',')
    local validations = {}
    for k, v in pairs(validation_parsed) do
        if type(v) == "table" then
            local matchers = string_lower(v[1])
            if matchers == 'reg' or matchers == 'eq' or matchers == 'neq' then
                validations[k] = { matchers, v[2] }
            elseif matchers == 'in' or matchers == 'notin' then
                validations[k] = { matchers, v[2] }
            else
                validations[k] = { 'eq', v[1] }
            end
        else
            validations[k] = { 'eq', v }
        end
    end
    return validations
end

--- Kept for compatibility: `html_cache` uses this to build cache keys from
--- declared rules.  The trie does not depend on it.
function route.parse_path_to_regex(url)
    -- `_parsed_paths` may not exist yet; creating it via a plain assignment
    -- would be intercepted by __newindex, so use rawset.
    local parsed_paths_to_regex = rawget(route, "_parsed_paths")
    if parsed_paths_to_regex == nil then
        parsed_paths_to_regex = {}
        rawset(route, "_parsed_paths", parsed_paths_to_regex)
    end

    if parsed_paths_to_regex[url] then
        return unpack(parsed_paths_to_regex[url])
    end

    local re_url, params = {}, {}
    for _, seg in ipairs(path_segments(url)) do
        local kind, value = classify_segment(seg)
        if kind == "static" then
            re_url[#re_url + 1] = ngx.re and ngx.re.escape
                and ngx.re.escape(value) or value:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        elseif kind == "param" then
            re_url[#re_url + 1] = "([^/]+)"
            params[#params + 1] = value
        else
            re_url[#re_url + 1] = "(.*)"
            params[#params + 1] = value
        end
    end

    local result = { url, "^/" .. table_concat(re_url, '/') .. "$", params }
    parsed_paths_to_regex[url] = result
    return unpack(result)
end

--- "auth mvc:index" -> "mvc:index", { "auth" }
function route.parse_handler_midware(responser)
    if type(responser) ~= "string" then
        return responser, {}
    end
    local midware, rest = unpack(split(responser, '%s+'))
    if not rest then
        return midware, {}
    end
    return rest, midware_manager.parse(midware)
end

--- Kept for compatibility.
function route.parse_path_params(params, values, extra_path)
    local out = {}
    for i, name in ipairs(params or {}) do
        out[name] = values and values[i]
    end
    if extra_path and extra_path ~= "" then
        out.splat = extra_path
    end
    return out
end

function route.to_router(handler, path)
    if type(handler) == "table" then
        local rule = {}
        for k, v in pairs(handler) do
            rule[k] = v
        end
        rule.path = rule.path or path
        if rule.midware and type(rule.midware) == "string" then
            rule.midware = midware_manager.parse(rule.midware)
        end
        rule.responser = rule.responser or rule.handler
        return rule
    end

    local responser, midware = route.parse_handler_midware(handler)
    return { path = path, responser = responser, midware = midware }
end

-----------------------------------------------------------------------
-- validation
-----------------------------------------------------------------------

---@param validations table
function route.validate(ctx, validations)
    if not validations then
        return true
    end
    if type(validations) == 'function' then
        return validations(ctx)
    end
    for k, validation in pairs(validations) do
        local value = lw_util.index_value(ctx, k)
        local tvalidation = type(validation)
        if tvalidation ~= 'table' then
            if value ~= validation then
                return false
            end
        else
            local exp, expected = table_unpack_safe(validation)
            local matchers = string_lower(tostring(exp))
            if matchers == 'reg' then
                if not ngx.re or not ngx.re.find then
                    return true
                end
                if not ngx.re.find(value, expected, 'jo') then
                    return false
                end
            elseif matchers == 'eq' then
                if value ~= expected then return false end
            elseif matchers == 'neq' then
                if value == expected then return false end
            elseif matchers == 'in' then
                if not helpers.find(
                    type(expected) == "table" and expected or split(expected, ",", true),
                    value) then
                    return false
                end
            elseif matchers == 'notin' then
                if helpers.find(
                    type(expected) == "table" and expected or split(expected, ",", true),
                    value) then
                    return false
                end
            end
        end
    end
    return true
end

function table_unpack_safe(t)
    return t[1], t[2]
end

-----------------------------------------------------------------------
-- matching
-----------------------------------------------------------------------

--- Find the best rule for a method + path.
--- @return table|nil rule  the matched rule
--- @return table captures  path parameters + splat
function route.match(app, method, path)
    method = string_lower(method or "get")
    path = normalize_path(path)
    local idx = get_index(app)
    local segs = path_segments(path)

    -- 1. trie (static > param > wildcard, per segment)
    local rule, captures = trie_match(idx.trie, segs, method, accepts_method)
    if rule then
        return rule, captures or {}
    end

    -- 2. regex fallback
    for _, r in ipairs(idx.regex or {}) do
        if accepts_method(r, method) then
            local mres = ngx.re.match(path, r.regex, "jo")
            if mres then
                mres[0] = nil
                local caps = {}
                for i, name in ipairs(r.args or {}) do
                    caps[name] = mres[i]
                end
                return r, caps
            end
        end
    end

    return nil
end

--- Compatibility wrapper: the pre-trie two-stage API.
--- Returns the matched rule (or nil); the second return value is kept for the
--- old call shape but is no longer a candidate array.
function route.find_matched_route(app, method, path)
    return route.match(app, method, path)
end

--- Compatibility wrapper.  With a trie there is no candidate list to reduce;
--- precedence is structural.  When handed a candidate array (old call shape)
--- the first accepted entry is returned.
function route.select_best_match(ctx, matched)
    if type(matched) == "table" and matched.path then
        -- already a rule
        return route.validate(ctx, matched.validation) and matched or nil
    end
    if type(matched) ~= "table" then
        return nil
    end
    for _, rule in ipairs(matched) do
        if route.validate(ctx, rule.validation) then
            return rule
        end
    end
    return nil
end

--- Resolve the request against the router.
--- @return boolean matched, table|string rule_or_path
function route.run(ctx)
    local request = ctx:make("request")
    local method = string_lower(request.method or (ngx.var and ngx.var.request_method) or "get")
    local path = request.path_info or (ngx.var and ngx.var.uri) or "/"

    local rule, captures = route.match(ctx.name, method, path)
    if not rule then
        return false, normalize_path(path)
    end

    -- Path parameters are visible to validation and to the dispatcher.
    local context = setmetatable(captures or {}, { __index = ctx })
    if not route.validate(context, rule.validation) then
        return false, normalize_path(path)
    end

    -- Hand the captures to the dispatcher via a shallow copy so per-request
    -- state never mutates the shared rule object.
    local out = {}
    for k, v in pairs(rule) do
        out[k] = v
    end
    out.vals = captures or {}
    out.extra_path = (captures and captures.splat) or ""
    return true, out
end

-----------------------------------------------------------------------
-- registration
-----------------------------------------------------------------------

--- Group routes under shared middleware.
---   route.group(function() route.get("/a", h) end, { "auth" })
--- The group middleware is PREPENDED to each route declared inside `func`.
function route.group(func, ...)
    local previous = route._group.midwares
    local args = { ... }
    local mid
    if type(args[1]) == "table" then
        mid = args[1]
    else
        mid = args
    end
    route._group.midwares = mid
    local ok, err = pcall(func)
    route._group.midwares = previous
    if not ok then
        error(err, 0)
    end
end

--- Register a route.
--- Two call shapes:
---   add_route("GET", "/x", handler, [midware])   -- from route.get() etc.
---   add_route("GET /x", handler)                 -- from route[key] = handler
local function add_route(verbs, path, handler, ...)
    local midargs = { ... }

    -- route["GET /x"] = handler  ->  add_route("GET /x", handler)
    if handler == nil and type(path) == "function" then
        handler = path
        path = nil
    end

    if not handler then
        return
    end

    local key
    if path == nil or path == "" then
        key = tostring(verbs)
    else
        key = tostring(verbs) .. ' ' .. tostring(path)
    end

    local midware
    local phases
    local first = midargs[1]
    if type(first) == 'table' then
        midware = first
    elseif type(first) == 'string' then
        midware = midargs
    else
        midware = {}
    end

    -- Normalise entries to { name, config }: a bare name string is accepted
    -- anywhere a middleware may be listed, matching the phase-list behaviour.
    for i, m in ipairs(midware) do
        if type(m) == 'string' then
            midware[i] = { m }
        end
    end

    -- An extra `{ phases = { access = {...} } }` argument declares middleware
    -- for a non-content OpenResty phase (e.g. auth in the access phase).
    for i = 1, #midargs do
        local a = midargs[i]
        if type(a) == 'table' and a.phases ~= nil then
            phases = a.phases
            if midware == a then
                midware = {}
            end
        end
    end

    if route._group.midwares then
        tablex.move(midware, route._group.midwares)
    end

    -- Group middleware may also be listed as bare names.
    for i, m in ipairs(midware) do
        if type(m) == 'string' then
            midware[i] = { m }
        end
    end

    -- Record declaration order for this key unless it was already declared;
    -- `init_rule_caches` replays the rules in it (see there for why).
    if rawget(route, "_rule_seq")[key] == nil then
        route._rule_seq[key] = route._next_rule_seq
        route._next_rule_seq = route._next_rule_seq + 1
    end

    route.rules[route.cur_app][key] = {
        responser = handler,
        path      = path,
        midware   = #midware > 0 and midware or nil,
        phases    = phases,
    }
end

function route.add_route(cur_app, verbs, path, handler, ...)
    rawset(route, "cur_app", cur_app)
    add_route(verbs, path, handler, ...)
end

function route.get(verbs, path, handler, ...)
    if handler == nil then
        -- route.get(path, handler)
        handler, path = path, verbs
        verbs = "GET"
    end
    add_route(verbs, path, handler, ...)
end

function route.post(verbs, path, handler, ...)
    if handler == nil then
        handler, path = path, verbs
        verbs = "POST"
    end
    add_route(verbs, path, handler, ...)
end

function route.put(verbs, path, handler, ...)
    if handler == nil then
        handler, path = path, verbs
        verbs = "PUT"
    end
    add_route(verbs, path, handler, ...)
end

function route.delete(verbs, path, handler, ...)
    if handler == nil then
        handler, path = path, verbs
        verbs = "DELETE"
    end
    add_route(verbs, path, handler, ...)
end

function route.patch(verbs, path, handler, ...)
    if handler == nil then
        handler, path = path, verbs
        verbs = "PATCH"
    end
    add_route(verbs, path, handler, ...)
end

function route.head(verbs, path, handler, ...)
    if handler == nil then
        handler, path = path, verbs
        verbs = "HEAD"
    end
    add_route(verbs, path, handler, ...)
end

function route.options(verbs, path, handler, ...)
    if handler == nil then
        handler, path = path, verbs
        verbs = "OPTIONS"
    end
    add_route(verbs, path, handler, ...)
end

--- RESTful resource shorthand.
---
--- `handler` is the controller base name; each route is bound to the matching
--- MVC action on it (`"post" -> "post.index"`, `"post.index"` is accepted too).
---
--- The action map is deliberately conventional (index / store / create / show /
--- update / destroy / edit).  The previous version concatenated the method and
--- the path onto the base name, producing module names such as
--- `post.GET/new` and `post.DELETE/{id}`, which no require() can ever resolve —
--- every generated route 404'd.
function route.rest(path, name, ...)
    local base = normalize_path(path)
    if type(name) ~= "string" then
        error("route.rest(path, controller_name): controller name must be a string", 2)
    end

    -- Accept either "post" or "post.index"; only the base name is used.
    local controller = name:match("^([^.]+)") or name

    local map = {
        { "GET",    "",         "index"   },
        { "POST",   "",         "store"   },
        { "GET",    "/new",     "create"  },
        { "GET",    "/{id}",    "show"    },
        { "PUT",    "/{id}",    "update"  },
        { "DELETE", "/{id}",    "destroy" },
        { "GET",    "/{id}/edit", "edit"  },
    }
    for _, m in ipairs(map) do
        local full = base .. m[2]
        if full == "" then
            full = "/"
        end
        add_route(m[1], full, controller .. "." .. m[3], ...)
    end
end

function route.get_routes(cur_app, _flag, _method)
    return route.rule_caches[cur_app] or {}
end

--- Middleware declared for a phase.
---
--- Route-scoped `phases` let a route opt into the access phase (auth before the
--- content phase) without gating every route.  Because the access phase runs
--- *before* routing in the normal OpenResty flow, callers that already know the
--- matched rule should pass `only` so that only that route's middleware runs —
--- otherwise `admin_guard` declared on `/admin` would gate the whole app.
---
--- @param app string app name
--- @param phase string "rewrite" | "access"
--- @param only table|false|nil a matched rule, `false` for "no route matched",
---        or nil for "no route filter" (collect from every route)
--- @return table list of entries in registration order
function route.phase_middleware(app, phase, only)
    local seen, out = {}, {}

    local function collect(rule)
        local phases = rule.phases
        if type(phases) ~= "table" then
            return
        end
        for _, entry in ipairs(phases[phase] or {}) do
            if type(entry) == "string" then
                entry = { entry }
            end
            local key = tostring(entry[1])
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = entry
            end
        end
    end

    if only == false then
        -- A route filter was applied and nothing matched: no route-scoped
        -- middleware may run for this request.
        return out
    end

    if only ~= nil then
        collect(only)
        return out
    end

    for _, rule in ipairs(route.rule_caches[app or route.cur_app] or {}) do
        collect(rule)
    end
    return out
end

return setmetatable(route, {
    __newindex = function(_, route_rule, responser)
        add_route(route_rule, responser)
    end,
    __call = function(_, ...)
        local rule = select(1, ...)
        if lw_util.is_array(rule) then
            lw_util.foreach(rule, function(responser, route_key)
                add_route(route_key, responser)
            end)
        end
    end,
})
