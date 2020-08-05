local path = require "Tilua.utils.path"
local getmtime = path.getmtime

---@class view
local view = {}

function view:get(name)
    if not name then
        return self.context
    end
    return self.context[name] or false
end

function view:precompile(view_file)
    local viewCacheFile = self.ctx.view_engine.view_cache_abs_path .. view_file
    view_file = path.join('view', view_file)
    self.ctx.logger:debug(view_file, ' precompile to ', viewCacheFile)
    self.ctx.view_engine.template.precompile(view_file, viewCacheFile, '', false)
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

function view:render(view_file, context)
    assert(view_file, "[view.render] Template view file must been specified")
    if path.extension(view_file) == '' then
        view_file = view_file .. '.html'
    end

    local enabled = self.ctx.view_engine.template.caching()
    if enabled then
        view_file = path.join('view', view_file)
    else
        local view_cache_abs_path = self.ctx.view_engine.view_cache_abs_path .. view_file
        local view_cache_mtime = getmtime(view_cache_abs_path) or -1
        if not path.exists(path.dirname(view_cache_abs_path)) then
            path.mkdir(path.dirname(view_cache_abs_path))
        end

        local view_abs_path = path.join(self.ctx.path, 'view', view_file)
        local view_mtime = getmtime(view_abs_path)
        assert(view_mtime, "[view.render] Template file named " .. view_abs_path .. " not exists!")
        if view_cache_mtime < view_mtime then
            self.ctx.logger:debug("template cache expired need update ", view_file)
            self:precompile(view_file)
        end
    end
    self.context = context or self.context
    local content = self:fetch(view_file)
    return (content)
end

function view:mount_context(name, value)
    self.mounted_context[name] = value
    return self
end

function view:fetch(view_file)
    setmetatable(self.context, {
        __index = self.mounted_context
    })
    local cache_key_prefix = self.ctx.view_engine.cache_key_prefix
    local cache_key = "no-cache"
    local enabled = self.ctx.view_engine.template.caching()
    if not enabled then
        view_file = self.ctx.view_engine.view_cache_path .. view_file
    else
        cache_key = path.join(cache_key_prefix, view_file)
    end
    return self.ctx.view_engine.template.process(view_file, self.context, cache_key, false)
end

local function new(self,ctx, context)
    local instance = {
        ctx = ctx,
        context = context or {},
        mounted_context = {}
    }
    setmetatable(instance, { __index = self })
    return instance
end

setmetatable(view,{
    __call = new
})

return view

