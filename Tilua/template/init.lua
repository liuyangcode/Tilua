--- Tilua.template
--- A small, dependency-free template engine used by Tilua.view.
---
--- Replaces the external `lua-resty-template` requirement: everything here
--- is plain Lua (works under LuaJIT/OpenResty and under stock Lua, e.g. in
--- unit tests with no nginx running at all).
---
--- Syntax
---   {{ expr }}     HTML-escaped output of a Lua expression
---   {{{ expr }}}   raw / unescaped output
---   {% lua %}      arbitrary Lua statements (if / for / while / local ...)
---   {# comment #}  removed at compile time, produces no output
---
--- Inside a template, `include(view, extra_context)` renders another view
--- (relative to the engine root) and inlines the result; `extra_context`
--- falls back to the current context for anything it doesn't override.
---
--- Public surface deliberately mirrors what `Tilua.view` / `Tilua.core.
--- lifecycle` call, so it is a drop-in replacement:
---   new(opts) -> engine
---   engine:caching(flag)
---   engine:compile(view) -> function(context) -> string
---   engine:compile_string(str) -> function(context) -> string
---   engine:render(view, context) -> string
---   engine:process(view, context, cache_key, no_print) -> string
---   engine:precompile(view, out, layout, no_render) -> true

local path_util = require("Tilua.utils.path")

local M = {}
M.__index = M

-----------------------------------------------------------------------
-- escaping
-----------------------------------------------------------------------

local ESCAPE_MAP = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
}

local function html_escape(v)
    if v == nil then
        return ""
    end
    return (tostring(v):gsub("[&<>\"']", ESCAPE_MAP))
end

-----------------------------------------------------------------------
-- compiler: template source -> Lua source
-----------------------------------------------------------------------

--- Translate template markup into a Lua program that builds the rendered
--- string into a buffer and returns it. Kept as text (not directly loaded)
--- so `precompile` can persist it to a cache file.
local function to_lua_source(tpl_src)
    local out = { "local _b = {}\n" }
    local i, n = 1, #tpl_src

    local function emit_literal(s)
        if s ~= "" then
            out[#out + 1] = ("_b[#_b + 1] = %q\n"):format(s)
        end
    end

    while i <= n do
        local cs = tpl_src:find("{[{%%#]", i)
        if not cs then
            emit_literal(tpl_src:sub(i))
            break
        end
        emit_literal(tpl_src:sub(i, cs - 1))

        local two = tpl_src:sub(cs, cs + 1)
        if two == "{#" then
            local close = tpl_src:find("#}", cs + 2, true)
            assert(close, "Tilua.template: unterminated {# comment #}")
            i = close + 2
        elseif two == "{%" then
            local close = tpl_src:find("%}", cs + 2, true)
            assert(close, "Tilua.template: unterminated {% ... %}")
            out[#out + 1] = tpl_src:sub(cs + 2, close - 1) .. "\n"
            i = close + 2
        else -- "{{" or "{{{"
            local raw = tpl_src:sub(cs, cs + 2) == "{{{"
            local open_len = raw and 3 or 2
            local close_tag = raw and "}}}" or "}}"
            local close = tpl_src:find(close_tag, cs + open_len, true)
            assert(close, "Tilua.template: unterminated {{ ... }}")
            local expr = tpl_src:sub(cs + open_len, close - 1)
            if raw then
                out[#out + 1] = ("_b[#_b + 1] = tostring(%s)\n"):format(expr)
            else
                out[#out + 1] = ("_b[#_b + 1] = _escape(%s)\n"):format(expr)
            end
            i = close + #close_tag
        end
    end

    out[#out + 1] = "return table.concat(_b)\n"
    return table.concat(out)
end

-----------------------------------------------------------------------
-- execution environment
-----------------------------------------------------------------------

local load_lua = loadstring or load -- LuaJIT/5.1 has loadstring; 5.2+ falls back to load

local function build_env(engine, context)
    context = context or {}
    return setmetatable({}, {
        __index = function(_, k)
            if k == "_escape" then
                return html_escape
            end
            if k == "include" then
                return function(view, extra)
                    local merged = context
                    if extra then
                        merged = setmetatable(extra, { __index = context })
                    end
                    return engine:render(view, merged)
                end
            end
            local v = context[k]
            if v ~= nil then
                return v
            end
            return _G[k]
        end,
    })
end

--- Load a Lua source string into a callable chunk bound to `env`.
local function load_chunk(lua_source, env)
    local chunk, err
    if setfenv then
        chunk, err = load_lua(lua_source, "=(tilua template)")
        if chunk then
            setfenv(chunk, env)
        end
    else
        chunk, err = load(lua_source, "=(tilua template)", "t", env)
    end
    if not chunk then
        error("Tilua.template: compile error: " .. tostring(err), 0)
    end
    return chunk
end

local function read_file(p)
    local f, err = io.open(p, "r")
    if not f then
        return nil, err
    end
    local data = f:read("*a")
    f:close()
    return data
end

-----------------------------------------------------------------------
-- engine
-----------------------------------------------------------------------

--- opts.root: base directory view paths are resolved against.
function M.new(opts)
    opts = opts or {}
    return setmetatable({
        root = opts.root or "",
        _caching = false,
    }, M)
end

--- Get/set the "trust the filesystem" flag. This engine always reads from
--- disk on every call (templates are small; parsing them is cheap compared
--- to the rest of a request) so caching only affects *precompilation*
--- behaviour driven by Tilua.view — see docs/VIEW.md.
function M:caching(flag)
    if flag ~= nil then
        self._caching = flag and true or false
    end
    return self._caching
end

function M:resolve(view)
    return path_util.join(self.root, view)
end

--- Compile a template *file* (raw markup) into a render function.
function M:compile(view)
    local abs = self:resolve(view)
    local src, err = read_file(abs)
    assert(src, "Tilua.template: not found: " .. abs .. " (" .. tostring(err) .. ")")
    local lua_src = to_lua_source(src)
    local engine = self
    return function(context)
        return load_chunk(lua_src, build_env(engine, context))()
    end
end

--- Compile a template *string* (no file I/O) into a render function.
function M:compile_string(str)
    local lua_src = to_lua_source(str or "")
    local engine = self
    return function(context)
        return load_chunk(lua_src, build_env(engine, context))()
    end
end

function M:render(view, context)
    return self:compile(view)(context)
end

--- lua-resty-template-compatible entry point used by Tilua.view:
---   process(view, context, cache_key, no_print)
--- `view` may be raw template markup OR an already-precompiled cache file
--- written by `precompile` below — both are handled transparently: a
--- precompiled file is valid Lua on its own, so it is tried first, and only
--- markup that fails to parse as Lua is run through the template compiler.
--- `cache_key` / `no_print` are accepted for signature compatibility and are
--- currently unused (this engine never prints to the response directly).
function M:process(view, context, cache_key, no_print)
    local abs = self:resolve(view)
    local content, err = read_file(abs)
    assert(content, "Tilua.template: not found: " .. abs .. " (" .. tostring(err) .. ")")

    local lua_src = content
    if not load_lua(content, "=(tilua precompiled probe)") then
        lua_src = to_lua_source(content)
    end

    return load_chunk(lua_src, build_env(self, context))()
end

--- Precompile `view` (raw markup, resolved against root) into a ready-to-run
--- Lua source file at `out` (an absolute path). `layout` / `no_render` are
--- accepted for signature compatibility with the old call site and are
--- currently unused.
function M:precompile(view, out, layout, no_render)
    local abs = self:resolve(view)
    local src, err = read_file(abs)
    assert(src, "Tilua.template: not found: " .. abs .. " (" .. tostring(err) .. ")")
    local lua_src = to_lua_source(src)

    local dir = out:match("^(.*)[/\\][^/\\]+$")
    if dir and not path_util.isdir(dir) then
        -- mkdir -p, not path_util.mkdir: the cache path can be several
        -- levels deep and lfs.mkdir only creates one level at a time.
        os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
    end

    local f, ferr = io.open(out, "w")
    assert(f, "Tilua.template: cannot write " .. out .. " (" .. tostring(ferr) .. ")")
    f:write(lua_src)
    f:close()
    return true
end

return M
