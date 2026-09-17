--- Tilua.core.discovery
--- Convention-based route discovery for MVC controllers.
---
--- Instead of listing every controller action in `routes.lua`, this scans the
--- application's controller directory at worker start and registers a route per
--- public action, using a flat `/<controller>/<action>` URL.
---
---     MyApp/controller/index.lua     Index:index()    -> GET /index/index
---     MyApp/controller/user.lua      User:show(id)    -> GET /user/show
---     MyApp/controller/admin/post.lua Post:index()     -> GET /admin/post/index
---
--- Enable it in config:
---
---     auto_routes = true,
---
--- Annotations
---   An action's method and middleware can be declared in the comment block
---   immediately above it.  An annotated action keeps the annotation; an
---   unannotated one keeps the defaults above, so adding annotations never
---   changes the routes you did not touch.
---
---     --- @get /users/{id}
---     --- @post /users
---     --- @middleware auth
---     --- @middleware rate_limit, { limit = 10 }
---     --- @phases access = admin_guard
---     function User:update(id) ... end
---
---   `@get` / `@post` / `@put` / `@delete` / `@patch` / `@head` / `@options`
---                             one route per directive.  The path is optional
---                             and defaults to `/<controller>/<action>`; a
---                             missing leading slash is added.  Repeat the
---                             directive to serve several methods:
---                                 --- @get  /thing
---                                 --- @post /thing
---   `@route <methods> [path]` the long form, kept for compatibility.  Accepts a
---                             method list: `@route get,post /thing`.
---   `@middleware <entry>`     content-phase middleware.  Repeatable, or pass a
---                             comma-separated list.  Accepts the same forms as
---                             the route helpers: `name`, `name, { config }`,
---                             `[group]`.
---   `@phases <phase> = <entry>` middleware for a non-content phase (access /
---                             rewrite).
---
---   Directive names are case-sensitive and lowercase: `@get` is the directive,
---   so `@GET` is reported as an unknown annotation rather than silently
---   ignored.  Any other `@word` is reported for the same reason — a typo must
---   not silently drop an intended route.
---
--- Precedence
---   A route registered explicitly in `routes.lua` (or `config.route`) always
---   wins over a discovered one for the same method and path.  Discovered routes
---   are marked `source = "scanned"`; `router.pick_rule` prefers `"explicit"`.
---   This is what makes discovery additive rather than a breaking change.
---
--- Timing
---   Discovery runs from `App:boot_worker()` (`init_worker_by_lua`), not in the
---   master.  Two reasons: the scan needs the filesystem and the controller
---   modules, and the master phase is deliberately kept free of both so a bad
---   config fails `nginx -t`.  The cost is paid once per worker.
---
--- Lazy instantiation
---   Controllers are NOT instantiated here.  Each discovered route is bound to a
---   `<module>@<action>` handler string, which `Tilua.http.dispatcher` already
---   knows how to resolve (and which instantiates the controller per request).

local path_util = require("Tilua.utils.path")
local helpers = require("Tilua.core.helpers")
local lw_util = require("Tilua.utils.util")

local M = {}

----------------------------------------------------------------------
-- annotations
----------------------------------------------------------------------

--- HTTP verbs usable as a bare directive (`@get /users`).
---
--- The lowercase spelling is intentional and case-sensitive: `@get` is the
--- directive, so `@GET` is NOT accepted (it is reported as an unknown
--- annotation rather than silently ignored).
local HTTP_METHODS = {
    get = true, post = true, put = true, delete = true,
    patch = true, head = true, options = true,
}

--- A non-verb directive this parser understands.  Anything else in an
--- annotation comment is reported, so a typo cannot silently drop a route.
local KNOWN_DIRECTIVES = {
    route      = true,   -- @route GET /path   (long form, still supported)
    middleware = true,
    phases     = true,
}

--- Parse a `@<verb> [path]` argument into a route record.
---
--- `@get /users/{id}` -> { methods = { "GET" }, path = "/users/{id}" }
--- `@get`             -> { methods = { "GET" } }        (convention path)
---
--- The path may be given without a leading slash (`@get users`); it is
--- normalised, because a missing slash would silently register an unreachable
--- route key.
local function parse_verb_directive(verb, arg)
    local path = helpers.strip(arg or "")
    if path ~= "" and path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    return {
        methods = { verb:upper() },
        path = (path ~= "" and path or nil),
    }
end

--- Split a directive argument on commas that are not inside `{}` or `()`.
---
--- `rate_limit, { limit = 10 }` must split into two parts, while
--- `[a,b]`-style group names and `{ a = 1, b = 2 }` config tables must stay
--- whole.  `helpers.split` cannot do this, so track depth manually.
local function split_top_level(s)
    local out, buf, depth = {}, {}, 0
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "{" or c == "(" then
            depth = depth + 1
        elseif c == "}" or c == ")" then
            depth = depth - 1
        end
        if c == "," and depth <= 0 then
            out[#out + 1] = table.concat(buf)
            buf = {}
        else
            buf[#buf + 1] = c
        end
    end
    out[#out + 1] = table.concat(buf)
    return out
end

--- Parse one `@middleware` / `@phases` argument into a route middleware entry.
---
--- Accepted: `name`, `name, { config }`, `[group]`.  Returns the `{ name, ... }`
--- shape `add_route` expects.
local function parse_middleware_entry(arg)
    local parts = split_top_level(arg)
    local name = helpers.strip(parts[1] or "")
    if name == "" then
        return nil
    end
    if #parts == 1 then
        return { name }
    end
    -- "name, { cfg }" -> { name, cfg }; the config is evaluated as a Lua literal
    local config_src = table.concat(parts, ",", 2)
    local chunk = (loadstring or load)("return " .. config_src, "=(annotation)")
    if not chunk then
        return { name }
    end
    local ok, config = pcall(chunk)
    if not ok or config == nil then
        return { name }
    end
    return { name, config }
end

--- Parse `@route` into a list of methods plus an optional path.
--- `GET /users/{id}` -> { "GET" }, "/users/{id}"
--- `get,post`        -> { "GET", "POST" }, nil
local function parse_route_directive(arg)
    arg = helpers.strip(arg or "")
    if arg == "" then
        return nil, "empty @route"
    end

    -- `<method list> [path]`.  The method list is everything up to the first
    -- space; a path always starts with `/`, so detecting it that way avoids
    -- splitting `GET /users/{id}` wrongly.
    local head, path = arg:match("^(%S+)%s*(.*)$")
    if not head then
        return nil, "empty @route"
    end
    path = helpers.strip(path or "")

    local methods = {}
    for word in head:gmatch("[^,]+") do
        word = helpers.strip(word)
        if word ~= "" then
            if not HTTP_METHODS[word:lower()] then
                -- Report the method as WRITTEN so the message is greppable
                -- against the source.
                return nil, "unknown HTTP method '" .. word .. "'"
            end
            methods[#methods + 1] = word:upper()
        end
    end
    if #methods == 0 then
        return nil, "empty @route method list"
    end

    return { methods = methods, path = (path ~= "" and path or nil) }
end

--- Scan a controller source file for action annotations.
---
--- Returns `{ [action] = { methods, path, middleware, phases } }`.  `methods` is
--- nil when no `@route` was given (the caller then applies its default), and
--- `path` is nil when the directive omitted one.
---
--- Only `--` / `---` line comments are considered; a `--[[ ]]` block comment is
--- ignored so documentation blocks are not mistaken for annotations.
---
--- @param source string controller file contents
--- @return table annotations, table errors
function M.parse_annotations(source)
    local annotations = {}
    local errors = {}

    if type(source) ~= "string" or source == "" then
        return annotations, errors
    end

    -- Split into lines, keeping both the text and the 1-based number of every
    -- non-blank line so a definition can be matched to the comment block above.
    local lines, nonblank = {}, {}
    do
        local n = 0
        for line in (source .. "\n"):gmatch("(.-)\n") do
            n = n + 1
            lines[n] = line
            if line:find("%S") then
                nonblank[#nonblank + 1] = n
            end
        end
    end

    --- Is this line a line comment that carries an annotation?
    local function annotation_line(line)
        local comment = line:match("^%s*(%-%-+%s*@.*)$")
        return comment
    end

    --- Is this line any kind of comment?  (Blank is NOT a comment — a blank line
    --- terminates an annotation block.)
    local function is_comment(line)
        local stripped = line:match("^%s*(.*)$") or ""
        return stripped:sub(1, 2) == "--"
    end

    -- `function Name:method(` / `function Name.method(` / `function method(`,
    -- plus the `Name.method = function(` assignment form.
    local function action_of(line)
        local name = line:match("^%s*function%s+[%w_%.]*[:%.]([%w_]+)%s*%(")
        if name then
            return name
        end
        name = line:match("^%s*function%s+([%w_]+)%s*%(")
        if name then
            return name
        end
        return line:match("^%s*[%w_]+[:%.]([%w_]+)%s*=%s*function%s*%(")
    end

    -- Walk each definition backwards over its contiguous comment block.
    for idx = 1, #nonblank do
        local start_line = nonblank[idx]
        local action = action_of(lines[start_line] or "")
        if action then
            -- Walk the REAL lines backwards, not the non-blank index list: a
            -- blank line ends the block, and skipping blanks would let an
            -- annotation separated by a blank line attach to the next action.
            local block, i = {}, start_line - 1
            while i >= 1 do
                local text = lines[i] or ""
                if text:find("^%s*$") or not is_comment(text) then
                    break
                end
                table.insert(block, 1, text)
                i = i - 1
            end

            local entry
            for _, text in ipairs(block) do
                local directive = annotation_line(text)
                if directive then
                    local word, arg = directive:match("^%-%-+%s*@([%w_]+)%s*(.*)$")
                    if word then
                        -- `@route` is the long form; a bare lowercase verb
                        -- (`@get`, `@post`, …) is shorthand for it.  Both keep
                        -- one record per directive, so two lines may name
                        -- different paths.
                        local is_verb = HTTP_METHODS[word] == true

                        if not is_verb and not KNOWN_DIRECTIVES[word] then
                            errors[#errors + 1] = string.format(
                                "%s: unknown annotation '@%s'", action, word)
                        else
                            entry = entry or {
                                routes = {},
                                middleware = {},
                                phases = {},
                            }
                            if is_verb then
                                entry.routes[#entry.routes + 1] =
                                    parse_verb_directive(word, arg)
                            elseif word == "route" then
                                local parsed, err = parse_route_directive(arg)
                                if not parsed then
                                    errors[#errors + 1] = string.format(
                                        "%s: %s", action, err or "invalid @route")
                                else
                                    entry.routes[#entry.routes + 1] = parsed
                                end
                            elseif word == "middleware" then
                                local parsed = parse_middleware_entry(arg)
                                if parsed then
                                    entry.middleware[#entry.middleware + 1] = parsed
                                end
                            elseif word == "phases" then
                                local phase, value = arg:match("^%s*([%w_]+)%s*=%s*(.+)$")
                                if not phase then
                                    errors[#errors + 1] = string.format(
                                        "%s: @phases needs '<phase> = <middleware>'", action)
                                else
                                    local parsed = parse_middleware_entry(value)
                                    if parsed then
                                        entry.phases[phase] =
                                            entry.phases[phase] or {}
                                        local list = entry.phases[phase]
                                        list[#list + 1] = parsed
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if entry then
                if #entry.middleware == 0 then
                    entry.middleware = nil
                end
                if next(entry.phases) == nil then
                    entry.phases = nil
                end
                annotations[action] = entry
            end
        end
    end

    return annotations, errors
end

--- Method names that come from the framework's controller base class and are
--- therefore not actions.  `_call` returns 404 by design; the rest are helpers.
local RESERVED = {
    _construct = true,
    _call = true,
    -- Injected by the class system into every derived class, not an action.
    define = true,
    assign = true,
    display = true,
    service = true,
    model = true,
    fail = true,
}

--- Discovered methods that are conveniences, not URLs.
local function is_action_name(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    -- leading underscore marks a private helper (matches the `mvc` middleware)
    if name:sub(1, 1) == "_" then
        return false
    end
    return not RESERVED[name]
end

--- List directory entries.
---
--- Uses LuaFileSystem when present and `ls` otherwise, because `lfs` is optional
--- in this project (a stock openresty/openresty image ships no `lfs.so`).
--- Returns a sorted array of names, or nil + reason.
local function list_dir(dir)
    local names = {}

    if path_util.has_lfs and path_util.dir then
        -- `lfs.dir` returns an iterator for the generic-for form.  Calling it as
        -- `pcall(path_util.dir, dir)` and then iterating `iter, state` yields
        -- NOTHING: the iterator is the value itself, so it must be used directly
        -- in the for-in expression.
        local ok, iter = pcall(path_util.dir, dir)
        if ok and iter then
            for entry in iter do
                if entry ~= "." and entry ~= ".." then
                    names[#names + 1] = entry
                end
            end
            table.sort(names)
            return names
        end
    end

    local p = io.popen("ls -1 '" .. tostring(dir):gsub("'", "'\\''") .. "' 2>/dev/null")
    if not p then
        return nil, "cannot list directory (no lfs and io.popen unavailable)"
    end
    for line in p:lines() do
        if line ~= "" then
            names[#names + 1] = line
        end
    end
    p:close()
    table.sort(names)
    return names
end

--- Collect the public action names defined on a controller class.
---
--- Walks the class chain but stops at the framework's controller base, so
--- inherited helpers (`assign`, `display`, …) are not mistaken for actions.
--- `inherited` guards against a cyclic `__parent`.
local function action_names(controller_class, base)
    local out = {}

    local chain, seen = {}, {}
    local current = controller_class
    while current ~= nil and not seen[current] and #chain < 16 do
        seen[current] = true
        chain[#chain + 1] = current
        if current == base then
            break
        end
        current = current.__parent
    end

    -- Skip the base class itself (index 1 is the controller under inspection).
    for i = 1, #chain do
        local class = chain[i]
        if class ~= base then
            for name, value in pairs(class) do
                if type(value) == "function" and is_action_name(name) and out[name] == nil then
                    out[name] = true
                end
            end
        end
    end

    local names = {}
    for name in pairs(out) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

--- Turn a controller filename into its URL prefix.
--- `user.lua` -> "user"; `admin/post.lua` -> "admin/post".  Subdirectories are
--- only descended one level (a controller is always a file).
local function controller_name_for(root, file)
    local rel = file:sub(#root + 2)              -- strip "<root>/"
    return (rel:gsub("%.lua$", ""))
end

--- Scan `dir` for controllers and register their actions on `router`.
---
--- @param app table the application (supplies `name` and `path`)
--- @param router table the router module
--- @param opts table|nil { dir, prefix, modules, log }
--- @return table report { registered, controllers, skipped, errors }
function M.scan(app, router, opts)
    opts = opts or {}

    local report = {
        registered = 0,
        controllers = {},
        skipped = {},
        errors = {},
    }

    local app_name = app.name
    if type(app_name) ~= "string" or app_name == "" then
        report.errors[#report.errors + 1] = "app.name is not set"
        return report
    end

    local root = opts.dir or path_util.join(app.path or ".", "controller")
    if not path_util.isdir(root) then
        -- Not an error: an app may legitimately have no controllers.
        report.skipped[#report.skipped + 1] = root .. " (no such directory)"
        return report
    end

    local prefix = opts.prefix
    if prefix ~= nil and prefix ~= "" then
        prefix = "/" .. tostring(prefix):gsub("^/", ""):gsub("/$", "")
    else
        prefix = ""
    end

    local entries = list_dir(root)
    if not entries then
        report.errors[#report.errors + 1] = "cannot list " .. root
        return report
    end

    for _, entry in ipairs(entries) do
        -- Skip dotfiles, and anything that is not a .lua file or a subdirectory.
        if entry:sub(1, 1) ~= "." then
            local full = path_util.join(root, entry)
            -- Classify by extension FIRST.  A `.lua` entry is always a controller
            -- file; only ask the filesystem about directory-ness for entries that
            -- are not Lua files.  This keeps discovery working even when the
            -- directory probe is unreliable.
            local is_lua = entry:sub(-4) == ".lua"

            if is_lua then
                M._register_controller(app_name, router, entry:gsub("%.lua$", ""),
                    full, prefix, report)
            elseif path_util.isdir(full) then
                -- One level of nesting: scan subdirectory controllers too.
                local sub = list_dir(full)
                for _, inner in ipairs(sub or {}) do
                    if inner:sub(-4) == ".lua" and inner:sub(1, 1) ~= "." then
                        local cname = controller_name_for(root, path_util.join(full, inner))
                        M._register_controller(app_name, router, cname,
                            path_util.join(full, inner), prefix, report)
                    end
                end
            end
        end
    end

    return report
end

--- Load one controller module and register its actions.
--- Exposed (`M._register_controller`) so tests can drive a single file.
---
--- Articles are registered with their `@route` / `@middleware` / `@phases`
--- annotations when present; an unannotated action keeps the
--- `GET /<controller>/<action>` default.
---
--- @param app_name string
--- @param router table
--- @param cname string controller name relative to the controller dir
--- @param file string absolute/relative path to the controller module
--- @param prefix string "" or a "/api"-style prefix
--- @param report table mutated in place
function M._register_controller(app_name, router, cname, file, prefix, report)
    local module_name = app_name .. ".controller." .. cname:gsub("/", ".")
    local controller_class = lw_util.import(module_name)
    if not controller_class then
        -- A file that is not a loadable controller module (bad name, syntax
        -- error, missing require).  Reported, not fatal: discovery must not take
        -- the worker down because one directory holds a non-controller.
        report.errors[#report.errors + 1] = "cannot load " .. module_name
        return
    end

    local base = require("Tilua.controller")
    local actions = action_names(controller_class, base)
    if #actions == 0 then
        report.skipped[#report.skipped + 1] = cname .. " (no public actions)"
        return
    end

    -- Annotations are read from the SOURCE, not from the loaded class: Lua
    -- discards comments, and the method/phase a route should use is authoring
    -- metadata rather than runtime state.
    local annotations = {}
    do
        local f = io.open(file, "r")
        if f then
            local source = f:read("*a")
            f:close()
            local parsed, errs = M.parse_annotations(source or "")
            annotations = parsed
            for _, e in ipairs(errs) do
                report.errors[#report.errors + 1] = cname .. ": " .. e
            end
        end
    end

    -- The URL segment keeps the on-disk path so nested controllers stay
    -- addressable: admin/post.lua -> /admin/post/<action>.
    local url_base = prefix .. "/" .. cname:gsub("%.lua$", "") .. "/"
    url_base = url_base:gsub("//+", "/")

    -- The `@` responser form is `<module path>@<action>`, and the dispatcher
    -- checks it for a dot *after the app name* before prefixing.  A bare
    -- controller name therefore resolves to `Api.demo` (missing the
    -- `controller.` layer) and the dispatcher returns 404.  Emit the full
    -- module path.
    local handler = module_name .. "@"

    local registered = {}
    for _, action in ipairs(actions) do
        local note = annotations[action]
        local default_url = url_base .. action

        -- One route record per `@route` directive; no directive means the
        -- historical default, so annotating one action never changes another.
        local specs = (note and note.routes) or { { methods = { "GET" } } }

        -- `add_route(verbs, path, handler, ...)` reads slot 1 as the middleware
        -- list and slot 2 as the `{ phases = ... }` config.  Both slots must be
        -- supplied positionally: passing only a phases table in slot 1 would
        -- make it the middleware list, and a `nil` middleware placeholder must
        -- be preserved rather than dropped by `{ ... }`.
        local args
        if note and (note.middleware or note.phases) then
            args = {
                note.middleware,                            -- slot 1 (may be nil)
                {
                    phases = note.phases,                   -- slot 2
                    opts   = { source = "scanned" },
                },
            }
        else
            args = { { opts = { source = "scanned" } } }
        end

        for _, spec in ipairs(specs) do
            local url = spec.path or default_url
            for _, method in ipairs(spec.methods) do
                router.add_route(app_name, method, url, handler .. action,
                    table.unpack(args, 1, #args))
                registered[#registered + 1] = method .. " " .. url
                report.registered = report.registered + 1
            end
        end
    end

    report.controllers[#report.controllers + 1] = {
        name = cname,
        url_base = url_base,
        actions = actions,
        routes = registered,
    }
end

return M
