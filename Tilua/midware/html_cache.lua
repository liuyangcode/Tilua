local html_cache = require("Tilua.midware").derive()
local path = require("pl.path")
local parse_rule = require("Tilua.route").parse_rule
local parse_path_to_regex = require("Tilua.route").parse_path_to_regex
local string_lower = string.lower
local json_encode = require("Tilua.util").json_encode
local combine = require("Tilua.util").combine
local string_sub = string.sub
local re_match = ngx.re.match
local re_gsub = ngx.re.gsub
local tablex = require('pl.tablex')

local rules = {}
local caches = {}
function html_cache:_init(ctx, config)
    self:super(ctx)
    self.ctx = ctx
    self.config = tablex.update({
        type = 'memory',
        enable = false,
        lifetime = 3600,
        rules = {}
    },config or {})

    if not rules[self.ctx.name] then
        rules[self.ctx.name] = {}
        for rule, re_path in pairs(self.config.rules) do
            local method, matcher, _rule, validation = parse_rule(rule)
            local _, regex_path, params = parse_path_to_regex(_rule)
            table.insert(rules[self.ctx.name], {
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
    if not caches[self.ctx.name] and self.config.type == 'memory' then
        caches[self.ctx.name] = {}
    end
end
function html_cache:match_rule()
    local cur_rules = rules[self.ctx.name]
    local method = string_lower(self.ctx.request.method)
    local pathinfo = self.ctx.request.path_info
    for _, rule in ipairs(cur_rules) do
        if tablex.find(rule.method, method) or tablex.find(rule.method, '*') then
            local mat = re_match(pathinfo, rule.path.regex_path, 'jo')
            local trule = type(rule.path.rule)
            if mat then
                local params = combine(rule.path.params, mat)
                if trule == 'string' then
                    local newpath, _, _ = re_gsub(rule.path.rule, '(\\$[a-z0-9A-Z]+)', function(m)
                        local index = tablex.find(rule.path.params, m[1]) or tablex.find(rule.path.params, string_sub(m[1], 2))
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