--- Tilua.core.container
--- A Laravel-inspired IoC / service container (pragmatic subset).
---
--- Registration
---   bind(name, factory)      – new instance on every resolve
---   singleton(name, factory) – one instance per owning container (worker scope)
---   scoped(name, factory)    – one instance per request scope, released by flush()
---   instance(name, value)    – register an already-built object
---   value(name, value)       – register a plain value (never called as a factory)
---   alias(name, alias)       – second name for an abstract (chains supported)
---   extend(name, decorator)  – decorate an existing binding
---
--- Resolution
---   make(name[, params])     – resolve; also accepts {"Class", {params}, "Conv"}
---   bound(name) / has(name)  – is it registered?
---   call(fn, args)           – call fn, resolving "$name" string arguments
---
--- Lifecycle
---   flush([closer])          – release scoped instances (calls :close() by default)
---   defer(fn)                – run fn at scope end (LIFO)
---   forget(name)             – drop a binding and its cached instance
---   scoped_instances()       – names of live scoped services
---
--- Composition
---   Container.define()       – derive a class; further `.define()` works
---
--- ---------------------------------------------------------------------------
--- Two invariants that matter, both learned the hard way:
---
--- 1. INTERNAL STATE IS READ WITH rawget.  Derived containers install an
---    `__index` that falls back to `resolve_property`, so reading a *missing*
---    internal field (`inst._parent`) would re-enter resolution and recurse
---    until the stack overflows.
---
--- 2. THE CLASS TABLE DOES NOT RESOLVE BINDINGS BY PROPERTY.  On a class,
---    `_bindings[name]` holds the *factory function*, so returning it as the
---    service is wrong.  Only real instances resolve properties; class-level
---    access goes through make().
--- ---------------------------------------------------------------------------

local Container = {}
Container.__index = Container

local unpack = table.unpack or unpack

-----------------------------------------------------------------------
-- tiny helpers
-----------------------------------------------------------------------

local function is_callable(v)
    if type(v) == "function" then
        return true
    end
    if type(v) == "table" or type(v) == "userdata" then
        local mt = getmetatable(v)
        return mt ~= nil and type(mt.__call) == "function"
    end
    return false
end

local function normalize(name)
    if type(name) ~= "string" or name == "" then
        error("container: service name must be a non-empty string, got " .. type(name), 3)
    end
    return name
end

--- Internal state accessors.  See invariant 1 above.
local function inst_of(c)
    return rawget(c, "_instances")
end

local function scoped_of(c)
    return rawget(c, "_scoped")
end

local function bindings_of(c)
    return rawget(c, "_bindings")
end

local function aliases_of(c)
    return rawget(c, "_aliases")
end

local function parent_of(c)
    return rawget(c, "_parent")
end

local function loader_of(c)
    return rawget(c, "_loader")
end

--- Walk a container and its ancestors, guarding against a cyclic `_parent`.
local function walk_parents(self, fn)
    local seen = {}
    local c = self
    while c ~= nil and not seen[c] do
        seen[c] = true
        local stop, result = fn(c)
        if stop then
            return result
        end
        c = parent_of(c)
    end
    return nil
end

local function find_binding(self, name)
    return walk_parents(self, function(c)
        local b = bindings_of(c)
        if b and b[name] ~= nil then
            return true, b[name]
        end
        return false
    end)
end

--- Find an already-built instance.  Singletons live on the container that owns
--- the binding, which is what makes worker-scoped services shared by requests.
local function find_instance(self, name)
    local own = inst_of(self)
    if own and own[name] ~= nil then
        return own[name]
    end
    local sc = scoped_of(self)
    if sc and sc[name] ~= nil then
        return sc[name]
    end
    return walk_parents(parent_of(self), function(c)
        local anc = inst_of(c)
        if anc and anc[name] ~= nil then
            return true, anc[name]
        end
        return false
    end)
end

local function resolve_alias(self, name)
    local aliases = aliases_of(self)
    if aliases == nil then
        return name
    end
    local seen = {}
    while aliases[name] do
        if seen[name] then
            error("container: alias cycle detected at '" .. name .. "'", 3)
        end
        seen[name] = true
        name = aliases[name]
    end
    return name
end

--- Load a module through the registered loader, falling back to an ancestor's.
--- A subclass (`App.define()`) may not have its own loader, so walking up is
--- required for class-level boot to work.
--- Deliberately loud: silent `pcall(require)` failures are what let this
--- framework ship broken require paths for several releases.
local function load_module(self, name)
    local loader = loader_of(self)
    if loader == nil then
        loader = walk_parents(parent_of(self), function(c)
            local l = loader_of(c)
            if l ~= nil then
                return true, l
            end
            return false
        end)
    end
    if not loader then
        return nil, "container: no loader registered, cannot resolve '" .. name .. "'"
    end
    local ok, mod = pcall(loader, name)
    if not ok then
        return nil, "container: loading '" .. name .. "' failed: " .. tostring(mod)
    end
    if mod == nil then
        return nil, "container: module '" .. name .. "' not found"
    end
    return mod
end

--- Instantiate a class-like module.
local function build(self, mod, params)
    local args = {}
    for i = 1, #params do
        args[i] = params[i]
    end
    if is_callable(mod) then
        return mod(unpack(args))
    end
    if type(mod) == "table" then
        if type(mod.new) == "function" then
            return mod.new(unpack(args))
        end
        if type(mod._construct) == "function" then
            local instance = setmetatable({}, { __index = mod })
            mod._construct(instance, unpack(args))
            return instance
        end
    end
    return mod
end

--- Split the table abstract form { "Class", {params}, "Convention" }.
local function split_abstract(abstract)
    if type(abstract) ~= "table" then
        error("container: build abstract must be a table like {'Service', {}, 'App'}", 3)
    end
    local name   = abstract[1]
    local params = abstract[2] or {}
    local where  = abstract[3]
    if type(name) ~= "string" or name == "" then
        error("container: build abstract needs a class name at index 1", 3)
    end
    if where == nil or where == "" then
        where = "Tilua"
    end
    return tostring(where) .. "." .. name, params
end

-----------------------------------------------------------------------
-- registration
-----------------------------------------------------------------------

--- Register an already-built shared instance.
function Container:instance(name, value)
    name = normalize(name)
    local own = inst_of(self)
    if own == nil then
        own = {}
        rawset(self, "_instances", own)
    end
    own[name] = value
    local b = bindings_of(self)
    if b then
        b[name] = nil
    end
    local sc = scoped_of(self)
    if sc then
        sc[name] = nil
    end
    return value
end

--- Register a binding.  `shared == true` makes it a singleton.
function Container:bind(name, factory, shared)
    name = normalize(name)
    if factory ~= nil and not is_callable(factory) then
        error("container: bind('" .. name .. "') expects a callable or nil", 2)
    end
    local b = bindings_of(self)
    if b == nil then
        b = {}
        rawset(self, "_bindings", b)
    end
    b[name] = { factory = factory, shared = shared == true }
    local own = inst_of(self)
    if own then
        own[name] = nil
    end
    local sc = scoped_of(self)
    if sc then
        sc[name] = nil
    end
    return self
end

--- Resolved once per owning container (worker scope).
function Container:singleton(name, factory)
    return self:bind(name, factory, true)
end

--- Resolved once per request scope; released by flush().
function Container:scoped(name, factory)
    name = normalize(name)
    if factory ~= nil and not is_callable(factory) then
        error("container: scoped('" .. name .. "') expects a callable or nil", 2)
    end
    local b = bindings_of(self)
    if b == nil then
        b = {}
        rawset(self, "_bindings", b)
    end
    b[name] = { factory = factory, shared = false, scoped = true }
    local own = inst_of(self)
    if own then
        own[name] = nil
    end
    local sc = scoped_of(self)
    if sc then
        sc[name] = nil
    end
    return self
end

--- Register a plain value (never treated as a factory).
function Container:value(name, value)
    name = normalize(name)
    return self:bind(name, function()
        return value
    end, true)
end

--- Give an abstract a second name.
function Container:alias(name, alias)
    name  = normalize(name)
    alias = normalize(alias)
    if alias == name then
        error("container: cannot alias '" .. name .. "' to itself", 2)
    end
    local a = aliases_of(self)
    if a == nil then
        a = {}
        rawset(self, "_aliases", a)
    end
    if a[alias] ~= nil and a[alias] ~= name then
        error("container: alias '" .. alias .. "' is already registered", 2)
    end
    a[alias] = name
    return self
end

--- Which abstract does this alias point to?  (nil when not an alias)
function Container:alias_of(name)
    if type(name) ~= "string" then
        return nil
    end
    local a = aliases_of(self)
    return a and a[name] or nil
end

--- Decorate an existing binding.
function Container:extend(name, decorator)
    name = normalize(name)
    if type(decorator) ~= "function" then
        error("container: extend('" .. name .. "') expects a function", 2)
    end

    local own_inst = inst_of(self) or {}
    local own_sc  = scoped_of(self) or {}
    local prev_instance = own_inst[name]
    local prev_scoped   = own_sc[name]
    local prev          = find_binding(self, name)
    local shared        = (prev and prev.shared) or (prev_instance ~= nil)
    local scoped_flag   = (prev and prev.scoped) or (prev_scoped ~= nil)

    local function factory(c, n)
        local resolved
        if prev_instance ~= nil then
            resolved = prev_instance
        elseif prev_scoped ~= nil then
            resolved = prev_scoped
        elseif prev and prev.factory then
            resolved = prev.factory(c, n)
        else
            local mod, err = load_module(c, n)
            if mod == nil then
                error(err, 0)
            end
            resolved = build(c, mod, {})
        end
        return decorator(resolved, c, n)
    end

    local b = bindings_of(self)
    if b == nil then
        b = {}
        rawset(self, "_bindings", b)
    end
    b[name] = { factory = factory, shared = shared, scoped = scoped_flag }
    if own_inst then
        own_inst[name] = nil
    end
    if own_sc then
        own_sc[name] = nil
    end
    return self
end

-----------------------------------------------------------------------
-- resolution
-----------------------------------------------------------------------

--- Is anything bound to this abstract (after alias resolution)?
function Container:bound(name)
    if type(name) ~= "string" then
        return false
    end
    name = resolve_alias(self, name)
    local own = inst_of(self)
    local sc = scoped_of(self)
    if (own and own[name] ~= nil) or (sc and sc[name] ~= nil) then
        return true
    end
    return find_binding(self, name) ~= nil
end

--- Readability alias for bound().
function Container:has(name)
    return self:bound(name)
end

--- Resolve an abstract, or nil when nothing is bound to it.
--- Uses raw access only: going through the metatable here would re-enter
--- `__index` and recurse.
function Container:resolve_property(name)
    if type(name) ~= "string" then
        return nil
    end
    name = resolve_alias(self, name)
    local cached = find_instance(self, name)
    if cached ~= nil then
        return cached
    end
    if find_binding(self, name) ~= nil then
        return self:make(name)
    end
    return nil
end

--- Resolve an abstract.
--- @param name string|table  name, or { "Class", {params}, "Convention" }
--- @param params table|nil   extra constructor params (class-like path only)
function Container:make(name, params)
    if type(name) == "table" then
        local fq, ctor_params = split_abstract(name)
        local mod, err = load_module(self, fq)
        if mod == nil then
            error(err, 2)
        end
        return build(self, mod, ctor_params)
    end

    name = resolve_alias(self, normalize(name))

    local cached = find_instance(self, name)
    if cached ~= nil then
        return cached
    end

    local binding = find_binding(self, name)

    if binding then
        local ok, result
        if binding.factory then
            ok, result = pcall(binding.factory, self, name)
        else
            ok, result = pcall(function()
                local mod, err = load_module(self, name)
                if mod == nil then
                    error(err, 0)
                end
                return build(self, mod, {})
            end)
        end
        if not ok then
            error("container: resolving '" .. name .. "' failed: " .. tostring(result), 2)
        end
        if result == nil then
            error("container: factory for '" .. name .. "' returned nil", 2)
        end

        if binding.scoped then
            local sc = scoped_of(self)
            if sc == nil then
                sc = {}
                rawset(self, "_scoped", sc)
            end
            sc[name] = result
        elseif binding.shared then
            local owner = walk_parents(self, function(c)
                local b = bindings_of(c)
                if b and b[name] ~= nil then
                    return true, c
                end
                return false
            end) or self
            local own = inst_of(owner)
            if own == nil then
                own = {}
                rawset(owner, "_instances", own)
            end
            own[name] = result
        end
        return result
    end

    local mod, err = load_module(self, name)
    if mod == nil then
        error(err, 2)
    end
    return build(self, mod, params or {})
end

--- Resolve a callable, injecting `"$name"` string arguments.
function Container:call(fn, args)
    if not is_callable(fn) then
        error("container: call() expects a callable, got " .. type(fn), 2)
    end
    args = args or {}
    local resolved = {}
    for i = 1, #args do
        local a = args[i]
        if type(a) == "string" and a:sub(1, 1) == "$" then
            resolved[i] = self:make(a:sub(2))
        else
            resolved[i] = a
        end
    end
    return fn(unpack(resolved))
end

-----------------------------------------------------------------------
-- scope lifecycle
-----------------------------------------------------------------------

--- Drop a single binding and its cached instance.
function Container:forget(name)
    name = resolve_alias(self, normalize(name))
    local own = inst_of(self)
    local sc  = scoped_of(self)
    local b   = bindings_of(self)
    if own then own[name] = nil end
    if sc  then sc[name]  = nil end
    if b   then b[name]   = nil end
    return self
end

--- Register a cleanup callback for the end of the current scope (LIFO).
function Container:defer(fn)
    if type(fn) ~= "function" then
        error("container: defer() expects a function", 2)
    end
    local d = rawget(self, "_deferred")
    if d == nil then
        d = {}
        rawset(self, "_deferred", d)
    end
    d[#d + 1] = fn
    return fn
end

--- Release every request-scoped instance, calling `closer` when available.
--- @return number released, string|nil errors
function Container:flush(closer)
    closer = closer or "close"
    local released = 0
    local errors = {}

    local scoped = scoped_of(self) or {}
    rawset(self, "_scoped", {})

    for name, value in pairs(scoped) do
        released = released + 1
        local t = type(value)
        if t == "table" or t == "userdata" then
            local fn = value[closer]
            if type(fn) == "function" then
                local ok, err = pcall(fn, value)
                if not ok then
                    errors[#errors + 1] = name .. ":" .. closer .. " -> " .. tostring(err)
                end
            end
        end
    end

    local deferred = rawget(self, "_deferred") or {}
    rawset(self, "_deferred", {})
    for i = #deferred, 1, -1 do
        local ok, err = pcall(deferred[i])
        if not ok then
            errors[#errors + 1] = "defer -> " .. tostring(err)
        end
    end

    if #errors > 0 then
        return released, table.concat(errors, "; ")
    end
    return released
end

--- Names of currently live scoped instances (diagnostics / tests).
function Container:scoped_instances()
    local names = {}
    local sc = scoped_of(self) or {}
    for name in pairs(sc) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-----------------------------------------------------------------------
-- construction
-----------------------------------------------------------------------

--- Shared setup for `Container.new()` and class-based composition.
function Container:initialize(opts)
    opts = opts or {}
    rawset(self, "_bindings",  {})
    rawset(self, "_instances", {})
    rawset(self, "_scoped",    {})
    rawset(self, "_aliases",   {})
    rawset(self, "_deferred",  {})
    rawset(self, "_loader",    opts.loader)
    rawset(self, "_parent",    opts.parent)
    return self
end

--- Container-aware constructor hook.  Derived classes may define a
--- `_boot_container(self)` for their own wiring.
function Container:_construct(opts)
    self:initialize(opts)
    local boot = self._boot_container
    if type(boot) == "function" then
        boot(self)
    end
    return self
end

--- Derive a class from this container.
---
--- Tilua's class system models a class as a table that is *itself* the parent
--- for further derivation.  This builds a proper class table whose parent is
--- the receiver, with the lookup chain
---     instance -> child -> parent -> container bindings
---
---   local App   = Container.define()   -- parent = Container
---   local MyApp = App.define()         -- parent = App
---
--- NOTE: the receiver MUST be declared as a parameter.  Lua does not bind
--- `self` in a parameterless function, so `function Container.define()` would
--- silently ignore `App.define(...)`'s receiver and derive from Container.
function Container.define(self)
    self = self or Container
    local parent = self
    local child = { __parent = parent }

    setmetatable(child, {
        __index = parent,
        __call = function(t, ...)
            local instance = {}
            setmetatable(instance, {
                __index = function(inst, name)
                    local v = rawget(child, name)
                    if v ~= nil then
                        return v
                    end
                    if parent ~= child then
                        v = rawget(parent, name)
                        if v ~= nil then
                            return v
                        end
                    end
                    -- container methods (make/bind/flush/…) live on Container
                    v = rawget(Container, name)
                    if v ~= nil then
                        return v
                    end
                    -- Only instances resolve bindings by property (invariant 2).
                    if inst ~= child then
                        return Container.resolve_property(inst, name)
                    end
                    return nil
                end,
                __newindex = function(inst, name, value)
                    local setter = rawget(parent, "set_" .. name)
                    if type(setter) == "function" then
                        return setter(inst, value)
                    end
                    rawset(inst, name, value)
                end,
            })

            Container._construct(instance, ...)
            local own = rawget(t, "_construct")
            if own and own ~= Container._construct then
                own(instance, ...)
            end
            return instance
        end,
    })

    -- Bound so `SomeClass.define()` derives from SomeClass, not Container.
    child.define = function()
        return Container.define(child)
    end

    return child
end

--- @param opts table|nil { loader = function(name), parent = Container|nil }
function Container.new(opts)
    return Container:initialize(opts)
end

setmetatable(Container, {
    __call = function(_, opts)
        return Container.new(opts)
    end,
})

return Container
