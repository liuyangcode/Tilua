local ngx = ngx

local re_sub = ngx.re.sub
local re_gsub = ngx.re.gsub

local string, table, require = string, table, require
local string_sub = string.sub
local string_find = string.find
local re_match = ngx.re.match
local stringx = require('pl.stringx')
local tablex = require('pl.tablex')
local strip = stringx.strip
local split = require('pl.utils').split
local unpack = require('pl.utils').unpack
local pretty = require("pl.pretty")
local string_lower, type, pairs, select, table_insert, ipairs, table_unpack, setmetatable = string.lower, type, pairs, select, table.insert, ipairs, table.unpack, setmetatable
local lw_util = require('Tilua.utils.util')
local midware_manager = require("Tilua.midware")

---@class route
local route = {
    cur_app = "",
    rules = {},
    rule_caches = {}
}
local group_midwares = nil
local verbstack = {}
local parsed_paths_to_regex = {}
function route.set_app_name(name)
    route.cur_app = name
    route.rules[name] = {}
    route.rule_caches[name] = {}
    --route.path_midwares[name] = {}
end

function route.init_rule_caches(config_rules)
    lw_util.extend(route.rules[route.cur_app], config_rules)
    for location, result in pairs(route.rules[route.cur_app]) do
        local method, matcher, url, validation = route.parse_rule(location)
        local router = route.to_router(result, url)
        router.matcher = matcher
        router.method = method

        if matcher == '~' then
            local _, regex, args = route.parse_path_to_regex(url)
            router.regex = regex
            router.args = args
        end

        router.validation = validation
        table_insert(route.rule_caches[route.cur_app], router)
    end
end

function route.add_route_rule(cur_app, router)
    --route.rule_caches[cur_app][verbs] = route.rule_caches[cur_app][verbs] or route.get_init_route_rule()
    --table_insert(route.rule_caches[cur_app][verbs][matchers], router)
    table_insert(route.rule_caches[cur_app], router)
end

function route.clear_route_rule(cur_app)
    route.rule_caches[cur_app] = {}
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
        { 'get', '$', 'index', '~' },
        { 'get', '/new$', 'new', '~' },
        { 'get', '/{id}$ id:neq,new', 'show', '~' },
        { 'get', '/{id}/edit$', 'edit', '~' },
        { 'post', '', 'create', '~' },
        { 'put', '/{id}$', 'update', '~' },
        { 'delete', '/{id}$', 'destroy', '~' }
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
    return tablex.deepcopy(route.rule_caches[app])
end

function route.find_matched_route(app, method, path)
    local route_caches = route.get_route_caches(app)
    method = string_lower(method)
    local mathced_route = {}
    for _, rule in ipairs(route_caches) do
        if tablex.find(rule.method, '*') or tablex.find(rule.method, method) then
            if rule.matcher == '~' then
                local iterator, _ = ngx.re.gmatch(path, rule.regex, "i")
                local m, err = iterator()
                if m then
                    m[0] = nil
                    rule.vals = m
                    rule.extra_path = strip(ngx.re.sub(path, rule.regex,''),'/')
                    table_insert(mathced_route, rule)
                end
            elseif rule.matcher == '=' and rule.path == path then
                table_insert(mathced_route, rule)
            elseif rule.matcher == '*' then
                local start_pos, end_pos = string_find(path, rule.path, 1, true)
                if start_pos then
                    rule.matched_len = end_pos
                    rule.extra_path = string_sub(path, end_pos + 1)
                    table_insert(mathced_route, rule)
                end
            end
        end
    end
    return mathced_route
end

local matched_rule_caches = {}
local function get_matched_rules(app, method, pathinfo)
    return tablex.deepcopy(matched_rule_caches[app .. method .. pathinfo])
end

function route.run(ctx)
    local request = ctx.request
    local request_method = request.method
    ---@type log
    local log = ctx.logger
    local pathinfo = request.path_info
    local matched = get_matched_rules(ctx.name, request_method, pathinfo)
    if not matched then
        matched = route.find_matched_route(ctx.name, request_method, pathinfo)
        matched_rule_caches[ctx.name .. request_method .. pathinfo] = matched
    end
    local best_match
    local longest_match_len = 0
    for i = #matched, 1, -1 do
        local rule = matched[i]
        if rule.matcher == '=' and route.validate(ctx, rule.validation) then
            best_match = rule
            break
        end
        if rule.matcher == '~' then
            local path_params = lw_util.combine(rule.args, rule.vals)
            if route.validate(setmetatable(path_params, { __index = ctx })) then
                best_match = rule
                if type(best_match.responser) == 'string' then
                    best_match.responser = string.gsub(best_match.responser, "%$(%d+)", function(var)
                        return path_params['$' .. var]
                    end)
                end
                break
            end
        end
        if rule.matcher == '*' and rule.matched_len > longest_match_len and route.validate(ctx, rule.validation) then
            best_match = rule
        end
    end
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
