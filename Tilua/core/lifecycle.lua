--- Tilua.core.lifecycle
--- OpenResty phase handlers.
---
--- Phase map (see docs/LIFECYCLE.md for the measurements behind it):
---
---   init_by_lua        (master)  config + route rules, validated up front
---   init_worker_by_lua (worker)  view engine, middleware config, plugins
---   rewrite_by_lua               request scope + rewrite-phase middleware
---   access_by_lua                access-phase middleware (may short-circuit)
---   content_by_lua               content middleware + dispatch + response output
---   log_by_lua                   release the request scope
---
--- `set_by_lua` is deliberately not used: that phase exists to set nginx
--- variables, has a restricted API, and must return a string/number.  It was
--- previously (mis)used as the request entry point.

local path        = require("Tilua.utils.path")
local lw_utils    = require("Tilua.utils.util")
local import      = lw_utils.import
local bind1       = lw_utils.bind1
local RequestCtx  = require("Tilua.core.request")

local path_join   = path.join
local path_exists = path.isdir
local string_lower = string.lower

local M = {}

local MIDDLEWARE_PHASES = { "rewrite", "access", "content" }

-----------------------------------------------------------------------
-- view engine bootstrap
-----------------------------------------------------------------------

--- Create a directory if missing.
---
--- `os.execute` reports success differently across Lua versions (0 on
--- 5.1/LuaJIT raw status, true/1 on 5.2+), so its return value is NOT a
--- reliable success signal — the previous `ret ~= 0 and ret ~= true` test
--- wrongly treated a successful mkdir as failure.  Verify by re-checking the
--- filesystem instead, and surface the shell error when that really fails.
---
--- `mkdir -p` is the only implementation: an earlier version tried
--- `pl.dir.makepath` first, but Penlight is not installed in a stock OpenResty,
--- so that branch never ran (and `-p` already handles nested paths).
local function ensure_dir(p)
    if path_exists(p) then
        return true
    end

    local output = os.execute("mkdir -p " .. p:gsub("'", "'\\''") .. " 2>&1")
    if not path_exists(p) then
        error(string.format("cannot create directory %s (mkdir said: %s)",
            p, tostring(output)))
    end
    return true
end

local function init_view_engine(root)
    local template = require("Tilua.template")

    local view_path       = path_join(root, "view", "")
    local cache_path      = path_join(root, "cache", "")
    local view_cache_path = path_join(cache_path, "view", "")
    local html_cache_path = path_join(cache_path, "html", "")

    for _, p in ipairs({ cache_path, view_cache_path, html_cache_path }) do
        ensure_dir(p)
    end

    local view_engine = template.new({ root = root })
    return {
        template            = view_engine,
        view                = view_path,
        root                = root,
        cache_key_prefix    = view_path,
        -- `view_cache_path` is the *relative* path the template engine uses
        -- for its own cache-key lookups; `view_cache_abs_path` is the
        -- filesystem prefix `view.lua` passes to `getmtime`/`mkdir`, so it
        -- must be absolute.  The two used to hold the same relative value,
        -- which made the mtime check resolve against the nginx prefix
        -- instead of the app root.
        view_cache_path     = path_join("cache", "view", ""),
        view_cache_abs_path = path_join(cache_path, "view", ""),
        html_cache_path     = html_cache_path,
    }
end

M.init_view_engine = init_view_engine

-----------------------------------------------------------------------
-- phase middleware helpers
-----------------------------------------------------------------------

local function middleware_manager(app)
    local ok, mw = pcall(function()
        return app:make("middleware")
    end)
    if not ok or mw == nil then
        return nil
    end
    return mw
end

--- Is any middleware declared for this phase?
local function phase_has_middleware(app, phase)
    local mw = middleware_manager(app)
    if not mw or type(mw.phase_list) ~= "function" then
        return false
    end
    local ok, list = pcall(mw.phase_list, phase)
    return ok and type(list) == "table" and #list > 0
end

--- Middleware for a phase.
---
--- The global `middleware_phases` config applies to every request.  Route-scoped
--- declarations (`route.get(path, h, mid, { phases = { access = {...} } })`)
--- only apply when that route matched, so `only` is passed when the caller has
--- already resolved the route — otherwise a guard declared on `/admin` would
--- gate the entire application.
local function phase_middleware(app, phase, only)
    local out, seen = {}, {}

    local function add_all(list)
        for _, entry in ipairs(list or {}) do
            if type(entry) == "string" then
                entry = { entry }
            end
            local key = tostring(entry[1])
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = entry
            end
        end
    end

    local mw = middleware_manager(app)
    if mw and type(mw.phase_list) == "function" then
        local ok, list = pcall(mw.phase_list, phase)
        if ok and type(list) == "table" then
            add_all(list)
        end
    end

    if phase == "rewrite" or phase == "access" then
        local ok, router = pcall(function()
            return app:make("router")
        end)
        if ok and router and type(router.phase_middleware) == "function" then
            local ok2, route_list = pcall(router.phase_middleware, app.name, phase, only)
            if ok2 and type(route_list) == "table" then
                add_all(route_list)
            end
        end
    end

    return out
end

--- Match the current request once and remember the result for later phases.
--- Returns the rule, or false when the path matched nothing.  `nil` is never
--- returned, because `phase_middleware` uses nil to mean "no route filter" and
--- would then apply every route's phase middleware.
local function match_route(app, ctx)
    local req = ctx:make("request")
    local method = string_lower(
        req.method or (ngx.var and ngx.var.request_method) or "get")
    local path = req.path_info or (ngx.var and ngx.var.uri) or "/"

    -- NOTE: `router.match` returns (rule, captures); pcall captures only its
    -- first result, so the call must be wrapped to keep both or the rule would
    -- always read as nil.
    local ok, rule = pcall(function()
        local matched = app:make("router").match(app.name, method, path)
        return matched
    end)

    if ok and rule then
        rawset(ctx, "_matched_route", rule)
        return rule
    end
    rawset(ctx, "_matched_route", false)
    return false
end

-----------------------------------------------------------------------
-- response output
-----------------------------------------------------------------------

local function wants_json(ctx)
    if ctx.config and ctx.config.enable_json_errors then
        return true
    end
    local req = ctx:make("request")
    if req and type(req.wants_json) == "function" then
        local ok, v = pcall(req.wants_json, req)
        return ok and v or false
    end
    return false
end

--- Emit a response object to the client.
--- OpenResty does NOT send the return value of content_by_lua, so this is the
--- only thing that actually writes a body.
--- @return boolean emitted
function M.emit(response)
    if response == nil then
        return false
    end
    if type(response.send) == "function" then
        response:send()
        return true
    end
    -- Not a Tilua response object (e.g. a stub channel returned a string).
    if type(response) == "string" and ngx and ngx.print then
        ngx.print(response)
        return true
    end
    return false
end

--- Build a response for a terminal error and emit it.
local function emit_error(app, ctx, err, layer)
    local Exception = require("Tilua.core.exception")
    local ex = Exception.is(err) and err or Exception.wrap(err, layer or "app")
    Exception.log(ctx, ex)
    local resp = ctx:make("response")
    Exception.render(resp, ex, ctx)
    M.emit(resp)
    return resp
end

-----------------------------------------------------------------------
-- init_by_lua (master process)
-----------------------------------------------------------------------

--- Worker/app boot detection.  `pid` is set at the end of init_worker_by_lua,
--- so it is the reliable marker that worker state is ready.
function M.is_inited_by_lua(app)
    return (app.pid or 0) > 0
end

--- Master-phase setup: configuration and route rules only.
--- Anything needing the filesystem or per-worker state belongs in the worker
--- phase; keeping this narrow means a bad config fails `nginx -t` / reload
--- instead of the first request.
function M.init_by_lua(app)
    if app._master_booted then
        return true
    end

    app:ensure_config()
    app:register_routes()

    if type(app.on_init_by_lua) == "function" then
        app:on_init_by_lua()
    end

    app._master_booted = true
    return true
end

-----------------------------------------------------------------------
-- init_worker_by_lua
-----------------------------------------------------------------------

function M.init_worker_by_lua(app)
    app:boot_worker()

    if type(app.on_init_worker) == "function" then
        app:on_init_worker()
    end

    -- Defer warming work so it never blocks the worker's first request.
    if type(app.warming_up) == "function" then
        local ok, err = pcall(function()
            ngx.timer.at(0, function(premature)
                if premature then
                    return
                end
                local ok2, werr = pcall(app.warming_up, app)
                if not ok2 and app.logger and app.logger.error then
                    pcall(function()
                        app.logger:error("warming_up failed: ", tostring(werr))
                    end)
                end
            end)
        end)
        if not ok and app.logger and app.logger.error then
            pcall(function()
                app.logger:error("warming_up timer failed: ", tostring(err))
            end)
        end
    end

    app.pid = ngx.worker.pid()
    return true
end

-----------------------------------------------------------------------
-- rewrite_by_lua : create the request scope
-----------------------------------------------------------------------

function M.rewrite_by_lua(app)
    if not app._master_booted then
        M.init_by_lua(app)
    end
    if not app._worker_booted then
        M.init_worker_by_lua(app)
    end

    local ctx = RequestCtx.context(app, { scope = "rewrite" })
    if type(ctx.on_rewrite) == "function" then
        pcall(ctx.on_rewrite, ctx)
    end

    -- Route once here so the access phase can apply route-scoped middleware.
    local matched = match_route(app, ctx)

    -- Rewrite-phase middleware runs here; returning a response short-circuits.
    local list = phase_middleware(app, "rewrite", matched)
    if #list == 0 then
        return
    end

    local ok, resp = pcall(function()
        return app:make("dispatcher"):run_phase(list, nil, nil)
    end)
    if not ok then
        emit_error(app, ctx, resp, "middleware")
        return
    end
    if resp ~= nil then
        M.emit(resp)
    end
end

-----------------------------------------------------------------------
-- access_by_lua : admission control
-----------------------------------------------------------------------

function M.access_by_lua(app)
    local ctx = RequestCtx.context(app, { scope = "access" })
    if type(ctx.on_access) == "function" then
        pcall(ctx.on_access, ctx)
    end

    -- Reuse the route matched during rewrite; `false` means "definitely no
    -- match", which must be preserved (plain `or` would re-match and lose it).
    local matched = rawget(ctx, "_matched_route")
    if matched == nil then
        matched = match_route(app, ctx)
    end

    local list = phase_middleware(app, "access", matched)
    if #list == 0 then
        return
    end

    local ok, resp = pcall(function()
        return app:make("dispatcher"):run_phase(list, nil, nil)
    end)
    if not ok then
        emit_error(app, ctx, resp, "middleware")
        return
    end
    if resp ~= nil then
        -- Admission denied: emit and leave the phase immediately so the
        -- content phase never runs.
        M.emit(resp)
    end
end

-----------------------------------------------------------------------
-- content_by_lua : dispatch and emit
-----------------------------------------------------------------------

function M.content_by_lua(app)
    local ctx = RequestCtx.context(app, { scope = "content" })

    local dispatcher = app:make("dispatcher")

    -- `route.run` resolves the match AND applies per-parameter validation, which
    -- the dispatcher relies on.  Route-scoped phase middleware used the raw
    -- match from rewrite; this is the validated form.
    local matched, router = app:make("router").run(ctx)

    local ok, result = xpcall(function()
        return dispatcher:run(matched, router)
    end, require("Tilua.core.exception").handler("controller"))

    if not ok then
        emit_error(app, ctx, result, "controller")
        return
    end

    if type(ctx.on_content) == "function" then
        pcall(ctx.on_content, ctx)
    end

    M.emit(result)
end

-----------------------------------------------------------------------
-- log_by_lua : release the request scope
-----------------------------------------------------------------------

function M.log_by_lua(app)
    local slot = RequestCtx.slot()
    if not slot then
        return
    end

    local ctx = slot.ctx
    if ctx and type(ctx.on_log) == "function" then
        pcall(ctx.on_log, ctx)
    end

    -- Subrequests get their own slot and release their own scope; the parent
    -- request is untouched because its slot lives in a different ngx.ctx.
    if ngx and ngx.worker and ngx.worker.exiting and ngx.worker.exiting() then
        return
    end

    RequestCtx.finish(app)
end

-----------------------------------------------------------------------
-- exposed for tests / compatibility
-----------------------------------------------------------------------

M.middleware_phases = MIDDLEWARE_PHASES
M.phase_has_middleware = phase_has_middleware
M.phase_middleware = phase_middleware
M.emit_error = emit_error

return M
