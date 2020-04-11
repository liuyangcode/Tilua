

local class = require "pl.class"
local func = require "pl.func"
local curry = func.curry
local split = require "pl.stringx".split
local ngx_var = ngx.var
local path = require "pl.path"
local dirname = path.dirname
local makepath = require "pl.dir".makepath
local path_exists = path.exists
local isfile = path.isfile
local getmtime = path.getmtime
local re_sub = ngx.re.gsub
local app = ngx.ctx.app_context
---@class page
class.page()

function page:_init(ctx)
    self.app = ctx
end

function page:cache(content)
    if self.file then
        local file = io.open(self.file, "w+")
        file:write(content)
        -- 关闭打开的文件
        file:close()
    end
end

function page:init()
    local rules = self.app:C('html_cache_rules') or {}
    local rule
    local controller = app:get_controller()
    local action = app:get_action()
    if rules[controller .. '*' .. action] then
        rule = rules[controller .. '*' .. action]
    elseif rules[controller .. '*'] then
        rule = rules[controller .. '*']
    elseif rules['*' .. action] then
        rule = rules['*' .. action]
    elseif rules['*'] then
        rule = rules['*']
    end
    if rule then
        local lifetime = app:C('html_cache_time')
        if type(rule) == 'table' then
            lifetime = rule[2]
            rule = rule[1]
        end
        local context = {
            controller = controller,
            request = app.request,
            module = app:get_module(),
            action = app:get_action(),
        }
        if type(rule) == 'string' then
            local callback = function(context, mt)
                local path = split(mt[1], '.')

                if #path == 1 then
                    return context[mt[1]]
                elseif #path == 2 and path[1] ~= 'var' then
                    return context[path[1]][path[2]]
                elseif #path == 2 and path[1] == 'var' then
                    return ngx_var[path[1]][path[2]]
                end
            end
            rule = re_sub(rule, "{([\\w\\.]+)}", curry(callback, context), "xjo")
        elseif type(rule) == 'function' then
            rule = rule(context, self.app)
        end
        self.file = app.app_path .. app:C('html_cache_path') .. '/' .. context.module .. '/' .. rule .. app:C('html_cache_file_ext')
        if not path_exists(dirname(self.file)) then
            makepath(dirname(self.file))
        end
        return lifetime
    end
end

function page:checkHTMLCache(lifetime)
    if not isfile(self.file) then
        return false
    elseif lifetime > 0 and getmtime(self.file) + lifetime > ngx.now() then
        return true
    end
    return false
end

function page:intercept()
    local lifetime = self:init()
    if self.file and self:checkHTMLCache(lifetime) then
        ngx.log(ngx.ERR, 'cache Bingo' .. self.file)
        local file = io.open(self.file)
        ngx.say(file:read("*a"))
        file:close()
        ngx.exit(200)
    end
end

return page