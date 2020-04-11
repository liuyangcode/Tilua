

local ngx = ngx
local class = require "pl.class"
local re_gsub = ngx.re.gsub
local string_sub = string.sub
local var = ngx.var
local re_match = ngx.re.match
local log = require('Tilua.log')
local stringx = require('pl.stringx')
local tablex = require('pl.tablex')
local strip = stringx.strip
local parse_agrs = ngx.decode_args
local split = require('pl.utils').split
local lw_util = require('Tilua.util')

local rules = {}
---@class route
class.route()
function route:_init(_rules)
    self.rules = _rules or {}
end

function route:check()
    self.rule_caches = {}
    tablex.update(self.rules, rules)
    for location, result in pairs(self.rules) do
        local method, matchers, url, validation = self:parse_rule(location)
        for i, v in ipairs(method) do
            self.rule_caches[v] = self.rule_caches[v] or self:get_init_route_rule()
            self.rule_caches[v][matchers][url] = { self:to_router(result, location), validation }
        end
    end

end

function route.get(path, handler, midware)
    rules['get ' .. path] = {
        responser = handler,
        aftermidware = midware and midware.aftermidware or {},
        beforemidware = midware and midware.beforemidware or {}
    }
end
---to_router
---@param router any
---@param path string 路径用于索引function
function route:to_router(router, path)
    local standard_handler = {
        midware = {
            beforemidware = {},
            aftermidware = {}
        },
        responser = nil
    }
    if lw_util.is_string(router) then
        standard_handler.responser, standard_handler.midware = self:parse_midware(router)
    elseif lw_util.is_array(router) then
        -- 标准路由响应者
        --standard_handler.responser = lw_util.callable(router.responser) and '#' .. path or router.responser
        standard_handler.responser = router.responser
        router.aftermidware = router.aftermidware or {}
        router.beforemidware = router.beforemidware or ''
        if lw_util.is_string(router.aftermidware) then
            router.aftermidware = split(router.aftermidware, ',')
        end
        if lw_util.is_string(router.beforemidware) then
            router.beforemidware = split(router.beforemidware, ',')
        end
        standard_handler.midware = {
            aftermidware = router.aftermidware,
            beforemidware = router.beforemidware
        }
    elseif lw_util.callable(router) then
        standard_handler.responser = router
    end
    return standard_handler
end

function route:get_init_route_rule()
    return { ['='] = {}, ['*'] = {}, ['~'] = {} }
end
---解析路由规则
---例如get =/welcome/{id} id=1&a=1
---@param location string
function route:parse_rule(location)
    location = strip(location, ' ')
    location = ngx.re.gsub(location, "%s+", ' ', 'jo')
    local method, route_url, validation = table.unpack(split(location, '%s+'))
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
        validation = self:parse_validation(validation)
    end
    method = stringx.split(method, ',')
    return method, matchers, route_url, validation
end
---路径变量验证
---@param validation string
function route:parse_validation(validation)
    if not validation then
        return {}
    end
    local validation_parsed = {}
    validation = split(stringx.strip(validation), ';')
    tablex.foreach(validation, function(val)
        local param, regex = table.unpack(split(val, ':'))
        validation_parsed[param] = regex
    end)
    return validation_parsed
end

function route:parse_path_to_regex(url)
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

function route:parse_midware(responser)
    local midware = {
        beforemidware = {},
        aftermidware = {}
    }
    responser = strip(responser, ' ')
    responser = ngx.re.gsub(responser, "%s+", ' ', 'jo')
    local beforemidware, responser, aftermidware = table.unpack(split(responser, '%s+'))
    if not responser then
        -- 没有中间件
        return beforemidware, midware
    end
    midware.beforemidware = split(beforemidware, ',')
    midware.aftermidware = aftermidware and split(aftermidware, ',') or {}
    return responser, midware
end

---解析路径变量
---@param params table
---@param values table
function route:bind_params_for_responser(params, values, request)
    local path_params = {}
    for i = 1, #params do
        path_params[params[i]] = values[i]
    end

    path_params.args = tablex.sub(values, 1, #values) --用于传递给responser
    table.insert(path_params.args, 1, request)
    return path_params
end

function route:get_rule_caches()
    return self.rule_caches
end

function route:get_routes(method)
    local rule_caches = self:get_rule_caches()
    method = string.lower(method or var.request_method)
    rule_caches = rule_caches[method] or self:get_init_route_rule()
    return rule_caches
end
---验证路径变量
---@param params table
---@param validation table
function route:validate_path_params(params, validation)
    --return true
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
---@param request request
function route:run(request)
    local pathinfo = request:get_path_info()

    log.record(ngx.ERR, 'start match url ', pathinfo)
    self:check()
    local rule_caches = self:get_routes()

    --精确匹配
    lw_util.extend(rule_caches['='], self.rule_caches['*'] and self.rule_caches['*']['='] or {})
    if rule_caches['='] then
        for location, router in pairs(rule_caches['=']) do
            if location == pathinfo then
                router, _ = table.unpack(router)
                return {
                    router.responser,
                    self:bind_params_for_responser({}, {}, request),
                    router.midware
                }
            end
        end
    end

    local longest_match_path = ''
    local longest_match = 0
    local longest_match_params
    local longest_match_midware = {}

    lw_util.extend(rule_caches['~'], self.rule_caches['*'] and self.rule_caches['*']['~'] or {})

    --正则匹配
    for location, router in pairs(rule_caches['~']) do
        local url, parsed_regex, params = self:parse_path_to_regex(location)
        local path_params = {}
        local midware, parsed_route, validation
        local newpath, n, err = re_gsub(pathinfo, parsed_regex, function(m)
            path_params = self:bind_params_for_responser(params, m, request)
            router, validation = table.unpack(router)
            if lw_util.callable(router.responser) then
                return ''
            elseif lw_util.is_string(router.responser) then
                return router.responser
            end
            return url
        end, 'jox')
        if n > 0 and n > longest_match and self:validate_path_params(path_params, validation) then
            longest_match = n
            longest_match_params = path_params
            longest_match_path = lw_util.is_string(router.responser) and newpath or router.responser
            longest_match_midware = router.midware
        end
    end
    if not lw_util.empty(longest_match_path) then
        request:set_routed_uri(longest_match_path)
        return {
            longest_match_path,
            longest_match_params,
            longest_match_midware
        }
    end
    --从路径开头匹配 最长匹配
    lw_util.extend(rule_caches['*'], self.rule_caches['*'] and self.rule_caches['*']['*'] or {})
    for location, router in pairs(rule_caches['*']) do
        local find, end_pos = string.find(pathinfo, location)
        router = router[1]
        if find and #location > longest_match then
            longest_match = #location
            longest_match_params = self:bind_params_for_responser({}, { string_sub(pathinfo, end_pos + 1) }, request)
            longest_match_path = router.responser
            longest_match_midware = router.midware
        end
    end
    if not lw_util.empty(longest_match_path) then
        request:set_routed_uri(longest_match_path)
        return {
            longest_match_path,
            longest_match_params,
            longest_match_midware
        }
    end
    return pathinfo
end

return route

