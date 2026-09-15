
local path = require("Tilua.utils.path")
local parse_rule = require("Tilua.http.router").parse_rule
local parse_path_to_regex = require("Tilua.http.router").parse_path_to_regex
local string_lower = string.lower
local combine = require("Tilua.utils.util").combine
local helpers = require("Tilua.core.helpers")
local string_sub = string.sub
local re_match = ngx.re.match
local re_gsub = ngx.re.gsub

local base = require("Tilua.middleware.base")
---@class html_cache
local html_cache = (type(base.define) == "function" and base.define()) or base
local rules = {}
local caches = {}

function html_cache:_construct(ctx, config)
    local defaults = {
        type = "memory",
        enable = false,
        lifetime = 3600,
        rules = {},
    }
    local merged = helpers.extend({}, defaults)
    if config then
        helpers.extend(merged, config)
    end
    local instance = {
        ctx = ctx,
        config = merged,
    }

    if not rules[instance.ctx.name] then
        rules[instance.ctx.name] = {}
        for rule, re_path in pairs(instance.config.rules) do
            local method, matcher, _rule, validation = parse_rule(rule)
            local _, regex_path, params = parse_path_to_regex(_rule)
            table.insert(rules[instance.ctx.name], {
                method = method,
                matcher = matcher,
                path = {
                    rule = re_path,
                    regex_path = regex_path,
                    params = params
                },
                validation = validation
            })
        end
    end
    if not caches[instance.ctx.name] and instance.config.type == 'memory' then
        caches[instance.ctx.name] = {}
    end
end

function html_cache:match_rule()
    local cur_rules = rules[self.ctx.name]
    local method = string_lower(self.ctx.request.method)
    local pathinfo = self.ctx.request.path_info
    for _, rule in ipairs(cur_rules) do
        if helpers.find(rule.method, method) or helpers.find(rule.method, '*') then
            local mat = re_match(pathinfo, rule.path.regex_path, 'jo')
            local trule = type(rule.path.rule)
            if mat then
                local params = combine(rule.path.params, mat)
                if trule == 'string' then
                    local newpath, _, _ = re_gsub(rule.path.rule, '(\\$[a-z0-9A-Z]+)', function(m)
                        local index = helpers.find(rule.path.params, m[1]) or helpers.find(rule.path.params, string_sub(m[1], 2))
                        return mat[index] or ''
                    end, 'jox')
                    return newpath, rule
                elseif trule == 'function' then
                    return rule.path.rule(setmetatable(params, { __index = self.ctx }))
                end
            end
        end
    end
end

function html_cache:get_hash_key()
    local key, _ = self:match_rule()
    if not key then
        return nil
    end
    if self.config.type == 'file' then
        return path.join(self.ctx.view_engine.html_cache_path, '', self.config.suffix)
    else
        return key
    end
end

function html_cache:exists(key)
    if self.config.type == 'memory' then
        return caches[self.ctx.name][key]
    elseif self.config.type == 'redis' then
        return self.ctx.cache.exists(key)
    end
end

function html_cache:get(key)
    if self.config.type == 'memory' then
        return caches[self.ctx.name][key]
    elseif self.config.type == 'redis' then
        return self.ctx.cache.get(key)
    end
end

function html_cache:set(key, data)
    if self.config.type == 'memory' then
        caches[self.ctx.name][key] = data
    elseif self.config.type == 'redis' then
        self.ctx.cache.set(key, data,self.config.lifetime)
    end
end

function html_cache:handle(next, ...)
    local key = self:get_hash_key()
    if key then
        local res = self:get(key)
        local response
        if res then
            self.ctx.logger:debug(self.ctx.request.path_info," hit cache ")
            response = self.ctx.response
            response.body = res
        else
            ---@type response
            response = self.ctx.dispatcher:prepare_response(next(...))
            if response.status == 200 or response.status == 0 then
                self:set(key, response.body)
            end
        end
        return response
    else
        return next(...)
    end
end



return html_cache