local ngx = ngx

local re_sub = ngx.re.sub
local string_sub = string.sub
local string_find = string.find
local re_match = ngx.re.match
local stringx = require('pl.stringx')
local tablex = require('pl.tablex')
local strip = stringx.strip
local split = require('pl.utils').split
local unpack = require('pl.utils').unpack

local lw_util = require('Tilua.util')
local midware_manager = require("Tilua.midware.manager")

---@class route
local route = {
    cur_app = "",
    rules = {},
    rule_caches = {},
    path_midwares = {}
}
local group_midwares = nil
function route.set_app_name(name)
    route.cur_app = name
    route.rules[name] = {}
    route.rule_caches[name] = {}
    route.path_midwares[name] = {}
end

function route.init_rule_caches(config_rules)
    lw_util.extend(route.rules[route.cur_app], config_rules)
    for location, result in pairs(route.rules[route.cur_app]) do
        local method, matchers, url, validation = route.parse_rule(location)
        for _, v in ipairs(method) do
            route.rule_caches[route.cur_app][v] = route.rule_caches[route.cur_app][v] or route.get_init_route_rule()
            route.rule_caches[route.cur_app][v][matchers][url] = { route.to_router(result, location), validation }
        end
    end
end

function route.add_route_rule(cur_app,verbs,matchers,path,router)
    route.rule_caches[cur_app][verbs] = route.rule_caches[cur_app][verbs] or route.get_init_route_rule()
    route.rule_caches[cur_app][verbs][matchers][path] = router
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
        route.rules[route.cur_app][verbs .. ' ' .. path] = {
            responser = handler,
            midware = midware
        }
    else
        local responser = path
        local route_rule = verbs
        if lw_util.is_string(responser) then
            add_route('', route_rule, responser, {})
        elseif lw_util.callable(responser) then
            add_route('', route_rule, responser, {})
        elseif lw_util.is_array(responser) then
            lw_util.foreach(responser, function(hanlder, verb)
                if verb == '*' then
                    add_route('', route_rule, hanlder, {})
                else
                    verb = split(verb, ',')
                    lw_util.foreach(verb, function(v)
                        add_route(v, route_rule, hanlder, {})
                    end)
                end
            end)
        end
    end
end

function route.add_route(cur_app,verbs, path, handler, ...)
    route.cur_app = cur_app
    add_route(verbs, path, handler, ...)
end

---分组添加中间件
function route.group(func, ...)
    group_midwares = { ... }
    func(route)
    group_midwares = nil
end
---get
function route.get(...)
    add_route('get', ...)
end
---post
function route.post(...)
    add_route('post', ...)
end
--delete
function route.delete(...)
    add_route('delete', ...)
end
---put
function route.put(...)
    add_route('put', ...)
end

function route.prefix(path, ...)
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
    route.path_midwares[route.cur_app][path] = midware_manager.parse(midware)
end

local function get_prefix_matched_midwares(cur_app, path)
    local longest_match = ''
    for prefix, midwares in pairs(route.path_midwares[cur_app]) do
        local find, end_pos = string_find(path, prefix, 1, true)
        if find and #prefix > #longest_match then
            longest_match = prefix
        end
    end
    if longest_match ~= '' then
        return route.path_midwares[cur_app][longest_match]
    end
    return nil
end
local function combine_prefix_midware(cur_app, path, midwares)
    local prefix_midwares = get_prefix_matched_midwares(cur_app, path)
    if prefix_midwares then
        for _, midware in ipairs(prefix_midwares) do
            table.insert(midwares, midware)
        end
    end
    return midwares
end
---rest
---@param path string
---@param handler any
function route.rest(path, handler, ...)
    local rest = {
        { 'get', '', 'index', '' },
        { 'get', '/new', 'new', '=' },
        { 'get', '/{id}', 'show', '~' },
        { 'get', '/{id}/edit', 'edit', '~' },
        { 'post', '', 'create', '' },
        { 'put', '/{id}', 'update', '~' },
        { 'delete', '/{id}', 'destroy', '~' }
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
        standard_handler.responser = router.responser
        router.midware = router.midware or {}
        if lw_util.is_string(router.midware) then
            router.midware = midware_manager.parse(router.midware)
        elseif lw_util.is_array(router.midware) then
            router.midware = midware_manager.parse(router.midware)
        end
        standard_handler.midware = router.midware
    elseif lw_util.callable(router) then
        standard_handler.responser = router
    end
    return standard_handler
end

function route.get_init_route_rule()
    return { ['='] = {}, ['*'] = {}, ['~'] = {} }
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
---@param validation string
function route.parse_validation(validation)
    if not validation then
        return {}
    end
    local validation_parsed = {}
    validation = split(stringx.strip(validation), ';')
    tablex.foreach(validation, function(val)
        local param, regex = unpack(split(val, ':'))
        validation_parsed[param] = regex
    end)
    return validation_parsed
end

function route.parse_path_to_regex(url)
    local regex = url
    local params = {}
    local iterator, err = ngx.re.gmatch(url, '{([a-zA-z_]+)}', "jo")
    if not iterator then
        return url, url, {}
    end
    local m
    while true do
        m, err = iterator()
        if not m then
            break
        else
            regex = stringx.replace(regex, m[0], '([a-zA-Z0-9._]+)', 1)
            params[#params + 1] = m[1]
        end
    end
    return url, regex, params
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
function route.bind_params_for_responser(params, values)
    local path_params = {}
    for i = 1, #params do
        path_params[params[i]] = values[i]
    end

    path_params.args = tablex.sub(values, 1, #values) --用于传递给responser
    return path_params
end

---get_routes
---@param cur_app string
---@param flag string
---@param method string
function route.get_routes(cur_app, flag, method)
    local rule_caches = nil
    method = string.lower(method)
    rule_caches = route.rule_caches[cur_app][method] or route.get_init_route_rule()
    lw_util.extend(rule_caches[flag], route.rule_caches[cur_app]['*'] and route.rule_caches[cur_app]['*'][flag] or {})
    return tablex.deepcopy(rule_caches[flag])
end
---验证路径变量
---@param params table
---@param validation table
function route.validate_path_params(params, validation)
    local result = true
    tablex.foreach(validation, function(v, k)
        if params[k] then
            local m, _ = re_match(params[k], v)
            result = result and not lw_util.empty(m)
        else
            result = false
        end
    end)
    return result
end
---run
function route.run(ctx)
    local request = ctx.request
    local request_method = request.method
    ---@type log
    local log = ctx.logger
    local pathinfo = request.path_info
    log:debug('route:start route pathinfo:' , pathinfo )

    local rule_caches = route.get_routes(ctx.name, '=', request_method)
    if rule_caches then
        for location, router in pairs(rule_caches) do
            if location == pathinfo then
                router, _ = unpack(router)
                return {
                    router.responser,
                    {},
                    combine_prefix_midware(ctx.name, pathinfo, tablex.copy(router.midware)),
                    router
                }
            end
        end
    end

    local matched_path = ''
    local longest_match = 0
    local matched_params
    local matched_router = nil
    local matched_midware = {}

    rule_caches = route.get_routes(ctx.name, '~', request_method)
    --正则匹配
    for location, router in pairs(rule_caches) do
        local url, parsed_regex, params = route.parse_path_to_regex(location)
        local path_params = {}
        local validation
        local newpath, n, _ = re_sub(pathinfo, parsed_regex, function(m)
            path_params = route.bind_params_for_responser(params, m)
            router, validation = unpack(router)
            if lw_util.callable(router.responser) then
                return ''
            elseif lw_util.is_string(router.responser) then
                return router.responser
            end
            return url
        end, 'jox')
        if n > 0 and #location > longest_match and route.validate_path_params(path_params, validation) then
            longest_match = #location
            matched_params = path_params
            matched_path = lw_util.is_string(router.responser) and newpath or router.responser
            matched_midware = tablex.copy(router.midware)
            matched_router = router
        end
    end

    if not lw_util.empty(matched_path) then
        request.routed_uri = matched_path
        request.params = matched_params
        return {
            matched_path,
            matched_params.args,
            combine_prefix_midware(ctx.name, pathinfo, matched_midware),
            matched_router
        }
    end
    longest_match = 0
    --从路径开头匹配 最长匹配
    rule_caches = route.get_routes(ctx.name, '*', request_method)

    for location, router in pairs(rule_caches) do
        local start_pos, end_pos = string_find(pathinfo, location, 1, true)
        router = router[1]
        if start_pos == 1 and end_pos > longest_match then
            longest_match = end_pos
            matched_params = route.bind_params_for_responser({}, { string_sub(pathinfo, end_pos + 1) })
            matched_path = router.responser
            matched_midware = tablex.copy(router.midware)
            matched_router = router
        end
    end

    if not lw_util.empty(matched_path) then
        request.routed_uri = pathinfo
        return {
            matched_path,
            matched_params,
            combine_prefix_midware(ctx.name, pathinfo, matched_midware),
            matched_router
        }
    end
    return pathinfo
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
