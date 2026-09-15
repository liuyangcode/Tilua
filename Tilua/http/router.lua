local ngx = ngx

local re_sub = ngx.re.sub
local re_gsub = ngx.re.gsub

local string, table, require = string, table, require
local string_sub = string.sub
local string_find = string.find
local re_match = ngx.re.match

-- Prefer pure helpers (Phase 3); soft-fallback to Penlight when present
local helpers = require("Tilua.core.helpers")
local strip = helpers.strip
local split = helpers.split
local unpack = table.unpack or unpack
local tablex = {
    find = helpers.find,
    sub = helpers.sub,
    insertvalues = helpers.insertvalues,
    deepcopy = helpers.deepcopy,
    move = function(dst, src, ...)
        -- append group middlewares to the front of per-route list
        if type(src) == "table" then
            for i = #src, 1, -1 do
                table.insert(dst, 1, src[i])
            end
        end
        return dst
    end,
}
local stringx = { strip = strip, split = function(s, sep) return split(s, sep or ",", true) end }
local string_lower, type, pairs, select, table_insert, ipairs, table_unpack, setmetatable = string.lower, type, pairs, select, table.insert, ipairs, table.unpack, setmetatable
local lw_util = require('Tilua.utils.util')
local midware_manager = require("Tilua.middleware")


---@class route
local route = {
    cur_app = "",
    rules = {},
    rule_caches = {},
    -- Fast lookup indexes per app (rebuilt when rules change)
    indexes = {},
}
-- path-level candidate cache + best-match cache
local matched_rule_caches = {}
local best_match_caches = {}
local MATCH_CACHE_MAX = 2048
local match_cache_size = 0
local group_midwares = nil
local verbstack = {}
local parsed_paths_to_regex = {}

local function method_set(methods)
    local s = {}
    if type(methods) ~= "table" then
        s[string_lower(tostring(methods or "*"))] = true
        return s
    end
    for _, m in ipairs(methods) do
        s[string_lower(tostring(m))] = true
    end
    return s
end

local function accepts_method(rule, method)
    local ms = rule._method_set
    if not ms then
        return true
    end
    return ms["*"] or ms[method]
end

local function clear_match_caches()
    matched_rule_caches = {}
    best_match_caches = {}
    match_cache_size = 0
end

--- Build O(1)/O(k) indexes: exact map, sorted prefixes, regex lists per method
function route.rebuild_index(app)
    local list = route.rule_caches[app] or {}
    local idx = {
        exact = {},   -- [method][path] = rule
        prefix = {},  -- [method] = { {path, rule, len}, ... } sorted desc by len
        regex = {},   -- [method] = { rule, ... }
    }

    local function bucket(method)
        if not idx.exact[method] then
            idx.exact[method] = {}
            idx.prefix[method] = {}
            idx.regex[method] = {}
        end
    end

    for _, rule in ipairs(list) do
        rule._method_set = method_set(rule.method)
        local methods = rule.method
        if type(methods) ~= "table" then
            methods = { methods or "*" }
        end
        for _, m in ipairs(methods) do
            m = string_lower(tostring(m))
            bucket(m)
            if rule.matcher == "=" then
                idx.exact[m][rule.path] = rule
            elseif rule.matcher == "*" then
                local len = #(rule.path or "")
                table_insert(idx.prefix[m], { path = rule.path, rule = rule, len = len })
            elseif rule.matcher == "~" then
                table_insert(idx.regex[m], rule)
            end
        end
    end

    -- longest prefix first
    for _, arr in pairs(idx.prefix) do
        table.sort(arr, function(a, b)
            return a.len > b.len
        end)
    end

    route.indexes[app] = idx
    clear_match_caches()
    return idx
end

local function get_index(app)
    local idx = route.indexes[app]
    if not idx then
        idx = route.rebuild_index(app)
    end
    return idx
end

function route.set_app_name(name)
    route.cur_app = name
    route.rules[name] = {}
    route.rule_caches[name] = {}
    route.indexes[name] = nil
end

function route.init_rule_caches(config_rules)
    lw_util.extend(route.rules[route.cur_app], config_rules)
    for location, result in pairs(route.rules[route.cur_app]) do
        local method, matcher, url, validation = route.parse_rule(location)
        local router = route.to_router(result, url)
        router.matcher = matcher
        router.method = method
        router._method_set = method_set(method)

        if matcher == "~" then
            local _, regex, args = route.parse_path_to_regex(url)
            router.regex = regex
            router.args = args
        end

        router.validation = validation
        table_insert(route.rule_caches[route.cur_app], router)
    end
    route.rebuild_index(route.cur_app)
end

function route.add_route_rule(cur_app, router)
    if router and not router._method_set then
        router._method_set = method_set(router.method)
    end
    table_insert(route.rule_caches[cur_app], router)
    route.rebuild_index(cur_app)
end

--- remove rule caches defined by gateway
---@param cur_app string app name
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
    route.rebuild_index(cur_app)
end


local function add_route(verbs, path, handler, ...)
    if handler then
        local midware
        local fmidware = select(1, ...)
        local tfmidware = type(fmidware)
        if tfmidware == 'table' then
            midware = fmidware
        elseif tfmidware == 'string' then
            midware = { ... }
        else
            midware = {}
        end
        if group_midwares then
            tablex.move(midware, group_midwares, #midware + 1, 1)
        end
        if #midware > 0 then
            route.rules[route.cur_app][verbs .. ' ' .. path] = {
                responser = handler,
                path = path,
                midware = midware
            }
        else
            route.rules[route.cur_app][verbs .. ' ' .. path] = handler
        end
    else
        local responser = path
        local route_rule = verbs
        if lw_util.is_string(responser) then
            add_route('', route_rule, responser)
        elseif lw_util.callable(responser) then
            add_route('', route_rule, responser)
        elseif lw_util.is_array(responser) then
            if responser.res or responser.responser then
                local mid = responser.mid or responser.midware or nil
                add_route('', verbs, responser.responser or responser.res, mid)
            else
                lw_util.foreach(responser, function(hanlder, verb)
                    if verb == '*' then
                        add_route('', route_rule, hanlder)
                    else
                        verb = split(verb, ',')
                        lw_util.foreach(verb, function(v)
                            add_route(v, route_rule, hanlder)
                        end)
                    end
                end)
            end
        end
    end
end

function route.add_route(cur_app, verbs, path, handler, ...)
    route.cur_app = cur_app
    add_route(verbs, path, handler, ...)
end

---分组添加中间件
function route.group(func, ...)
    local mid = select(1, ...)
    if type(mid) == 'table' then
        group_midwares = mid
    else
        group_midwares = { ... }
    end
    func(route)
    group_midwares = nil
end

for _, ver in ipairs({
    'get', 'post', 'delete', 'put'
}) do
    route[ver] = function(...)
        if not select(1, ...) then
            table_insert(verbstack, ver)
            return route
        end
        table_insert(verbstack, ver)
        for _, v in ipairs(verbstack) do
            add_route(v, ...)
        end
        verbstack = {}
        return route
    end
end

---rest
---@param path string
---@param handler any
function route.rest(path, handler, ...)
    local rest = {
        { 'get', '/?$', 'index', '~' },
        { 'get', '/new/?$', 'new', '~' },
        { 'get', '/{id}/?$ id:neq,new', 'show', '~' },
        { 'get', '/{id}/edit$', 'edit', '~' },
        { 'post', '/?$', 'create', '~' },
        { 'put', '/{id}/?$', 'update', '~' },
        { 'delete', '/{id}/?$', 'destroy', '~' }
    }
    for _, v in ipairs(rest) do
        if lw_util.is_string(handler) then
            route[v[1]](v[4] .. path .. v[2], handler .. '@' .. v[3], ...)
        else
            route[v[1]](v[4] .. path .. v[2], handler[v[3]], ...)
        end
    end
end
---to_router
---@param router any
---@param path string 路径用于索引function
function route.to_router(router, path)
    local standard_handler = {
        midware = {
        },
        responser = nil
    }
    if lw_util.is_string(router) then
        standard_handler.responser, standard_handler.midware = route.parse_handler_midware(router)
    elseif lw_util.is_array(router) then
        -- 标准路由响应者
        standard_handler.responser = router.responser or router.res
        router.midware = router.midware or {}
        if lw_util.is_string(router.midware) then
            router.midware = midware_manager.parse(router.midware or router.mid)
        elseif lw_util.is_array(router.midware) then
            router.midware = midware_manager.parse(router.midware or router.mid)
        end
        standard_handler.midware = router.midware
    elseif lw_util.callable(router) then
        standard_handler.responser = router
    end
    standard_handler.path = path
    return standard_handler
end

---解析路由规则
---例如get =/welcome/{id} id=1&a=1
---@param location string
function route.parse_rule(location)
    location = strip(location, ' ')
    location = ngx.re.gsub(location, "%s+", ' ', 'jo')
    local method, route_url, validation = unpack(split(location, '%s+'))
    if not route_url then
        route_url = method
        method = '*'
    end
    local matchers = string_sub(route_url, 1, 1)
    local matchers_map = {
        ['='] = '=',
        ['~'] = '~',
        ['*'] = '*'
    }
    if not matchers_map[matchers] then
        matchers = '*'
    else
        route_url = string.sub(route_url, 2)
    end
    --正则匹配支持参数验证
    if matchers == '~' then
        validation = route.parse_validation(validation)
    end
    method = stringx.split(method, ',')
    return method, matchers, route_url, validation
end
---路径变量验证
---@param validation string like uid:reg,[0-9]+
function route.parse_validation(validation)
    if not validation then
        return {}
    end
    local validation_parsed = {}
    local validations = {}
    validation_parsed = lw_util.parse_expression(validation, ';', ':', ',')
    for k, v in pairs(validation_parsed) do
        local tv = type(v)
        if tv == 'table' then
            local matchers = string.lower(v[1])
            if matchers == 'reg' or matchers == 'eq' or matchers == 'neq' then
                validations[k] = {
                    matchers,
                    v[2]
                }
            elseif matchers == 'in' or matchers == 'notin' then
                validations[k] = {
                    matchers,
                    tablex.sub(v, 2, #v)
                }
            else
                validations[k] = {
                    'in',
                    v
                }
            end
        elseif tv ~= 'nil' then
            validations[k] = {
                'eq',
                v
            }
        end
    end
    return validations
end

function route.parse_path_to_regex(url)
    if parsed_paths_to_regex[url] then
        return unpack(parsed_paths_to_regex[url])
    end
    local params = {}
    local anonymous_arg_cnt = 0
    local re_url = string.gsub(url, '\\/', '__SLASH__')
    re_url = split(re_url, '/', true)
    for i, v in ipairs(re_url) do
        if re_match(v, '[(][^)]+[)]') then
            repeat
                anonymous_arg_cnt = anonymous_arg_cnt + 1
                table_insert(params, '$' .. anonymous_arg_cnt)
                v = re_sub(v, '[(][^)]+[)]', '')
            until not re_match(v, '[(][^)]+[)]')
            re_url[i] = string.gsub(re_url[i], '__SLASH__', '\\/')
        elseif re_match(v, '{[^}]+?}') then
            re_url[i] = re_gsub(v, '({[^}]+?})', function(m)
                table_insert(params, string_sub(m[1], 2, -2))
                return '([^\\/]+)'
            end, 'jox')
        end
    end
    parsed_paths_to_regex[url] = { url, table.concat(re_url, '/'), params }
    return url, table.concat(re_url, '/'), params
end

function route.parse_handler_midware(responser)
    responser = strip(responser, ' ')
    responser = ngx.re.gsub(responser, "%s+", ' ', 'jo')
    local midware
    midware, responser = unpack(split(responser, '%s+'))
    if not responser then
        -- 没有中间件
        return midware, {}
    end
    midware = midware_manager.parse(midware)
    return responser, midware
end

---解析路径变量
---@param params table
---@param values table
function route.parse_path_params(params, values, extra_path)
    values = values or {}
    extra_path = strip(extra_path, '/')
    tablex.insertvalues(values, split(extra_path, '/'))
    local path_params = {}
    for i, v in ipairs(values) do
        path_params['$' .. i] = v
    end
    for i = 1, #params do
        path_params[params[i]] = values[i]
    end
    path_params.args = tablex.sub(values, 1, #values) --用于传递给responser
    path_params.params = params
    return path_params
end

---get_routes
---@param cur_app string
---@param flag string
---@param method string
function route.get_routes(cur_app, flag, method)
    local rule_caches = nil
    method = string_lower(method)
    rule_caches = route.rule_caches[cur_app][method] or route.get_init_route_rule()
    for _, v in ipairs(route.rule_caches[cur_app]['*'] and route.rule_caches[cur_app]['*'][flag] or {}) do
        table_insert(rule_caches[flag], v)
    end
    return tablex.deepcopy(rule_caches[flag])
end

---验证路由是否匹配
---@param ctx table
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
            local exp, values = table_unpack(validation)
            exp = string_lower(exp)
            if (exp == 'in' and not tablex.find(values, value)) or (exp == 'notin' and tablex.find(values, value)) then
                return false
            elseif (exp == 'eq' and value ~= values) or (exp == 'neq' and value == values) then
                return false
            elseif exp == 'reg' and not re_match(value, values) then
                return false
            end
        end
    end
    return true
end

function route.get_route_caches(app)
    return route.rule_caches[app] or {}
end

local function shallow_rule(rule)
    local r = {}
    for k, v in pairs(rule) do
        r[k] = v
    end
    return r
end

local function cache_key(app, method, path)
    return app .. "\0" .. method .. "\0" .. path
end

local function store_match_cache(key, value)
    if match_cache_size >= MATCH_CACHE_MAX then
        clear_match_caches()
    end
    matched_rule_caches[key] = value
    match_cache_size = match_cache_size + 1
end

--- Collect candidate matches using indexes (exact → regex → prefix)
function route.find_matched_route(app, method, path)
    method = string_lower(method or "get")
    local key = cache_key(app, method, path)
    local cached = matched_rule_caches[key]
    if cached then
        return cached
    end

    local idx = get_index(app)
    local matched_route = {}

    local function try_exact(m)
        local map = idx.exact[m]
        if map then
            local rule = map[path]
            if rule then
                matched_route[#matched_route + 1] = rule
            end
        end
    end

    local function try_regex(m)
        local list = idx.regex[m]
        if not list then
            return
        end
        for i = 1, #list do
            local rule = list[i]
            -- "jo" = JIT + once; faster than gmatch for single match
            local mres = ngx.re.match(path, rule.regex, "jo")
            if mres then
                mres[0] = nil
                local copy = shallow_rule(rule)
                copy.vals = mres
                local rest = ngx.re.sub(path, rule.regex, "", "jo")
                copy.extra_path = strip(rest or "", "/")
                matched_route[#matched_route + 1] = copy
            end
        end
    end

    local function try_prefix(m)
        local list = idx.prefix[m]
        if not list then
            return
        end
        for i = 1, #list do
            local item = list[i]
            local p = item.path
            -- plain find from start only
            if path == p or (string_find(path, p, 1, true) == 1) then
                local copy = shallow_rule(item.rule)
                copy.matched_len = #p
                copy.extra_path = string_sub(path, #p + 1)
                matched_route[#matched_route + 1] = copy
            end
        end
    end

    -- specific method then wildcard method rules
    try_exact(method)
    try_exact("*")
    try_regex(method)
    try_regex("*")
    try_prefix(method)
    try_prefix("*")

    store_match_cache(key, matched_route)
    return matched_route
end

--- Select best match with priority: exact > regex > longest prefix
function route.select_best_match(ctx, matched)
    local best_match
    local longest_match_len = 0

    -- prefer exact
    for i = 1, #matched do
        local rule = matched[i]
        if rule.matcher == "=" and route.validate(ctx, rule.validation) then
            return rule
        end
    end

    for i = 1, #matched do
        local rule = matched[i]
        if rule.matcher == "~" then
            local path_params = lw_util.combine(rule.args or {}, rule.vals or {})
            if route.validate(setmetatable(path_params, { __index = ctx }), rule.validation) then
                if type(rule.responser) == "string" then
                    local copy = shallow_rule(rule)
                    copy.responser = string.gsub(rule.responser, "%$(%d+)", function(var)
                        return path_params["$" .. var] or ""
                    end)
                    return copy
                end
                return rule
            end
        end
    end

    for i = 1, #matched do
        local rule = matched[i]
        if rule.matcher == "*" then
            local len = rule.matched_len or 0
            if len > longest_match_len and route.validate(ctx, rule.validation) then
                longest_match_len = len
                best_match = rule
            end
        end
    end
    return best_match
end

function route.run(ctx)
    local request = ctx.request
    local request_method = string_lower(request.method or ngx.var.request_method or "get")
    local pathinfo = request.path_info or ngx.var.uri or "/"

    local bkey = cache_key(ctx.name, request_method, pathinfo)
    local cached_best = best_match_caches[bkey]
    if cached_best ~= nil then
        if cached_best == false then
            return false, pathinfo
        end
        return true, cached_best
    end

    local matched = route.find_matched_route(ctx.name, request_method, pathinfo)
    local best_match = route.select_best_match(ctx, matched)

    if match_cache_size >= MATCH_CACHE_MAX then
        clear_match_caches()
    end
    best_match_caches[bkey] = best_match or false
    match_cache_size = match_cache_size + 1

    if best_match then
        return true, best_match
    end
    return false, pathinfo
end


return setmetatable(route, {
    __newindex = function(_, route_rule, responser)
        add_route(route_rule, responser)
    end,
    __call = function(_, ...)
        local rule = select(1, ...)
        if lw_util.is_array(rule) then
            lw_util.foreach(rule, function(responser, route_rule)
                add_route(route_rule, responser)
            end)
        end
    end
})
