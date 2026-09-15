--- Tilua.middleware
--- New canonical name for the middleware manager.
--- The old Tilua.midware remains as a compatibility alias.

local ngx = ngx
local lw_util = require("Tilua.utils.util")
local import  = lw_util.import
local helpers = require("Tilua.core.helpers")
local split = helpers.split
local map = helpers.map


local manager = {
    midwares = {},
    alias = {},
    midware_group = {},
    phases = {},
}

--- OpenResty phases a middleware chain can be assigned to, in execution order.
local PHASES = { rewrite = true, access = true, content = true }
local PHASE_ORDER = { "rewrite", "access", "content" }

local midware_group_parsed = {}

function manager.is_group(val)
    -- "[name]" group marker. Long brackets cannot be used here: the pattern
    -- ends with `]]`, which would close the literal early.
    local mat = ngx.re.match(val, "\\[[a-zA-Z_0-9]+\\]")
    return mat ~= nil
end

local function get_shortname(name)
    return (name:gsub("%.", "_"))
end

--- Resolve a middleware reference to a module.
---
--- Accepted forms, in order:
---   1. an alias from `middleware_alias` (e.g. `session` -> "Tilua.middleware.session")
---   2. a fully-qualified module name containing a dot ("MyApp.middleware.auth")
---   3. a bare short name, resolved against the app's own middleware namespace
---      ("admin_guard" -> "MyApp.middleware.admin_guard"), mirroring how the
---      model and service managers resolve `MyApp.model.X` / `MyApp.service.X`
---   4. the name as-is (framework-provided or global module)
---
--- Only form 2 used to be supported, so a phase entry written as a short name
--- silently resolved to nothing and the whole phase was skipped.
local function resolve_middleware_module(ctx, ref)
    if manager.alias[ref] then
        return manager.alias[ref], get_shortname(manager.alias[ref])
    end

    if type(ref) ~= "string" or ref == "" then
        return nil
    end

    -- fully-qualified
    if ref:find(".", 1, true) then
        return ref, get_shortname(ref)
    end

    -- app-local namespace
    local appname = ctx and ctx.name
    if appname and appname ~= "" then
        local candidate = appname .. ".middleware." .. ref
        if pcall(require, candidate) then
            return candidate, ref
        end
    end

    return ref, ref
end

function manager.instance(self, midware)
    local hash = lw_util.get_hash and lw_util.get_hash(midware) or table.concat(midware, "|")
    if self.midwares[hash] then
        return self.midwares[hash]
    end

    local midware_class, alias_name = resolve_middleware_module(self.ctx, midware[1])

    local mid_class = midware_class and import(midware_class)
    if not mid_class then
        error("middleware '" .. tostring(midware[1]) .. "' not found"
            .. " (tried '" .. tostring(midware_class) .. "')")
    end

    local mid = mid_class(self.ctx, midware[2])
    if not mid.handle then
        error("middleware '" .. tostring(midware[1]) .. "' must implement handle()")
    end

    self.midwares[hash] = mid
    return mid
end

function manager.load(config)
    config = config or {}
    manager.midware_group = config.midware_group or config.middleware_group or {}
    manager.alias         = config.midware_alias or config.middleware_alias or {}
    manager.phases        = config.middleware_phases or config.midware_phases or {}

    -- Invalidate parsed caches: groups may have changed.
    for k in pairs(midware_group_parsed) do
        midware_group_parsed[k] = nil
    end
    manager._phase_cache = nil
    return manager
end

local PHASES = { rewrite = true, access = true, content = true }

--- Middleware names declared for a phase, normalised to entries.
--- A name may be a plain string ("auth"), a group reference ("[api]"), or an
--- explicit { name, config } pair.  Groups expand recursively.  Anything not
--- declared under `middleware_phases` belongs to `content`, so existing
--- configurations keep their behaviour.
--- Normalise one chain entry to { name, config }.
--- `manager.parse` is documented to return entries in that shape, but a plain
--- name can survive as a bare string — and `instance()` then does `midware[1]`
--- on it, yielding nil and an "middleware named 'nil' not found" error.
local function normalize_entry(entry)
    if type(entry) == "string" then
        return { entry }
    end
    if type(entry) == "table" then
        -- A bare list of names would itself be a table; make sure index 1 is a
        -- name string, otherwise treat the whole thing as a name-less entry.
        if type(entry[1]) == "string" then
            return entry
        end
    end
    return entry
end

function manager.phase_list(phase)
    if not PHASES[phase] then
        return {}
    end
    local cache = manager._phase_cache
    if cache == nil then
        cache = {}
        for p in pairs(PHASES) do
            cache[p] = {}
        end
        for p, names in pairs(manager.phases or {}) do
            if PHASES[p] then
                local parsed = manager.parse(names)
                for i, entry in ipairs(parsed) do
                    parsed[i] = normalize_entry(entry)
                end
                cache[p] = parsed
            end
        end
        manager._phase_cache = cache
    end
    return cache[phase] or {}
end

--- All phases that declare middleware, in execution order.
function manager.phase_names()
    local order, seen = {}, {}
    for _, p in ipairs({ "rewrite", "access", "content" }) do
        if #manager.phase_list(p) > 0 then
            order[#order + 1] = p
            seen[p] = true
        end
    end
    return order
end

function manager.get_group(name)
    if manager.is_group(name) then
        name = name:sub(2, #name - 1)
    end
    if midware_group_parsed[name] then
        return midware_group_parsed[name]
    end
    local parsed = manager.parse(manager.midware_group[name])
    -- `parse` returns a table unchanged, so a group written as a list of plain
    -- names would stay as bare strings.  Normalise each entry to { name }.
    for i, entry in ipairs(parsed) do
        if type(entry) == "string" then
            parsed[i] = { entry }
        end
    end
    midware_group_parsed[name] = parsed
    return parsed
end

function manager.group(name, midwares)
    if lw_util.is_string(midwares) then
        midwares = manager.parse(midwares)
    elseif lw_util.is_array(midwares) then
        midwares = map(function(v)
            return manager.parse(v)
        end, midwares)
    end
    manager.midware_group[name] = midwares
end

function manager.parse(val)
    if type(val) == "table" then
        return val
    end
    if type(val) ~= "string" then
        return {}
    end

    -- support "a|b|c" or "a,b,c"
    local parts = split(val, "[|,]")
    local result = {}
    for _, p in ipairs(parts) do
        p = (p:match("^%s*(.-)%s*$")) or p
        if p ~= "" then
            if manager.is_group(p) then
                local group = manager.get_group(p)
                for _, g in ipairs(group) do
                    table.insert(result, g)
                end
            else
                table.insert(result, { p })
            end
        end
    end
    return result
end

-- constructor used by app
local function new(app)
    local m = setmetatable({
        ctx      = app,
        midwares = {},
    }, { __index = manager })
    return m
end

return setmetatable(manager, {
    __call = function(_, app)
        return new(app)
    end,
})
