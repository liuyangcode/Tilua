local class = require "pl.class"
local template = require "resty.template"
local path = require "pl.path"
local dirname = path.dirname
local getmtime = path.getmtime

local makepath = require "pl.dir".makepath
local path_exists = path.exists

---@class view
local view = class()
local _template = nil
function view:_init(ctx,context)
    ---@type app
    self.app = ctx
    self.context = context or {}
    self.template = nil
end

function view:get(name)
    if not name then
        return self.context
    end
    return self.context[name] or false
end

function view:get_template()
    if _template then
        return _template
    end
    _template = template.new({
        root = self:get_template_path()
    })
    _template.caching(false)
    return _template
end

function view:precompile(view, cache)
    local viewCacheFile = self:get_template_cache_file_path(view)
    if not path_exists(dirname(viewCacheFile)) then
        local _, err = makepath(dirname(viewCacheFile))
        assert(not err, 'dir ' .. dirname(viewCacheFile) .. ' write ' .. err)
    end
    self:get_template().precompile(view, viewCacheFile)
end

function view:assign(name, value)
    if type(name) == 'string' then
        self.context[name] = value
    elseif type(name) == 'table' then
        for k, v in pairs(name) do
            self:assign(k, v)
        end
    end
end

function view:get_template_cache_file_path(view)
    return self:get_template_cache_path() .. view
end

function view:get_template_cache_path()
    local view_cache_path = self.app.app_path .. table.concat({
        'cache',
        'view',
        ''
    }, '/')
    if not path_exists(view_cache_path) then
        local _, err = makepath(view_cache_path)
        assert(not err, 'dir ' .. view_cache_path .. ' write ' .. err)
    end
    return view_cache_path
end

function view:render(view,context)
    if (getmtime(self:get_template_cache_file_path(view)) or 0) < getmtime(self:get_template_path() .. view) then
        self.app.logger.record(ngx.ERR, "template cache expired need update")
        self:precompile(view)
    end
    self.context = context or self.context
    local content = self:fetch(view)
    return (content)
end

function view:fetch(view)
    self:precompile(view)
    return self:get_template().process(self:get_template_cache_path_relative() .. view, self.context, nil, false)
end

function view:get_template_cache_path_relative()
    return '../' .. table.concat({
        'cache',
        'view',
        ''
    }, '/')
end

function view:get_template_path()
    local view_path = self.app.app_path .. table.concat({
        'view',
        ''
    }, '/')
    return view_path
end

return view

