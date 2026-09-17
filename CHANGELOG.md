# Changelog

All notable changes to Tilua are documented in this file.

## [Unreleased] - Controller and view layer

### Fixed
- **`view:render(view, context)` discarded everything set with `assign`.** The
  context argument REPLACED the view context instead of merging into it, so the
  most natural controller style silently lost data:

  ```lua
  self:assign("title", "Hi")
  return self:display("index", { items = items })   -- "title" was lost
  ```

  It now merges: explicit values win per key, and `mount_context` remains the
  final fallback.

- **`controller:display(name, context)` ignored its second argument.**
  `display` only accepted a template name, so a context table passed by an
  action was dropped and every template key came out `nil`. It now forwards the
  context (and documents that it returns the response object, with the rendered
  HTML on `response.body`).

- **Framework methods leaked as routable actions.** `Tilua.controller` gained
  `get` and `mount_context` while the reserved-name list lived in the discovery
  module as a hand-maintained copy, so `GET /<controller>/get` and
  `GET /<controller>/mount_context` were published for every controller. The set
  now lives beside the definitions as `controller.framework_methods`, is read by
  discovery at scan time, and a test fails if a base method is not accounted for.

- **`find_handler` crashed on a nil `responser`** with
  `bad argument #1 to 'string_find' (string expected, got nil)`. It is treated as
  the empty string and falls through to the conventional path form.

### Changed
- `find_handler`'s two handler forms are now documented, because they invoke the
  controller differently and only one supports the controller API:

  | `responser` | Controller | `assign` / `display` / `service` |
  |---|---|---|
  | `"<module>@<action>"` | called on the **class**, `self = ctx` | unavailable |
  | `"<action>"` (or absent) | **instantiated** from `router.path` | available |

  Its dead `handler.__parent` check was removed; the branch now has explicit
  precedence (named action, then `_call`) and always returns a callable.

- `Tilua.controller` gained `get` and `mount_context`, so the view API is
  reachable from a controller instead of only part of it being delegated.

### Added
- `tests/test_mvc_pipeline.lua` — 34 checks covering the pipeline that had **no
  coverage at all**: instantiating a controller, running an action, rendering
  through `display()`, `assign` values surviving the render, `mount_context` as
  the fallback, an action returning a table, both `find_handler` forms, the
  nil-`responser` guard, and the framework-method drift guard.
- Fixtures `TestApp/controller/mvc.lua` plus `view/mvc/{index,mounted}.html`, and
  four `/mvc/*` cases in the e2e suite (real nginx, 23 cases now).

## [Unreleased] - Action annotations for methods and middleware

### Added
- **`auto_routes_unannotated`** — controls whether a controller action with no
  route annotation is registered.

  | Value | `Demo:hello` (no annotation) | `Demo:echo` (`@get`) |
  |-------|------------------------------|----------------------|
  | `true` (default) | exposed as `GET /demo/hello` | exposed |
  | `false` | **404**, and listed in the discovery report | exposed |

  It defaults to `true` so enabling it cannot silently un-route a project that
  already relies on convention routes. Skipped actions are recorded in
  `report.skipped` (and counted in `report.unannotated_skipped`) so the omission
  is visible rather than silent — "why is my action not routed?" has an answer.
  An explicit `routes.lua` entry is unaffected by the switch.

- **Action annotations.** A discovered controller action can declare its HTTP
  method and middleware in the comment block immediately above it:

  ```lua
  --- @get  /users/{id}
  --- @post /users
  --- @middleware auth
  --- @middleware rate_limit, { limit = 10 }
  --- @phases access = admin_guard
  function User:update(id) ... end
  ```

  | Directive | Meaning |
  |-----------|---------|
  | `@get` `@post` `@put` `@delete` `@patch` `@head` `@options` | One route per directive. The path is optional and defaults to `/<controller>/<action>`; repeat the directive to serve several methods. |
  | `@route <methods> [path]` | The long form, kept for compatibility. Accepts a method list: `@route get,post /thing`. |
  | `@middleware <entry>` | Content-phase middleware. Repeatable. Accepts `name`, `name, { config }`, `[group]`. |
  | `@phases <phase> = <entry>` | Middleware for a non-content phase (`access`, `rewrite`). |

  Directive names are **lowercase and case-sensitive**: `@get` is the directive,
  so `@GET` is reported as an unknown annotation rather than silently ignored.
  A path given without a leading slash (`@get users`) is normalised, because the
  malformed key would have registered an unreachable route.

  Each route directive keeps **its own** path, so `@get /a/{id}` + `@post /a`
  register two routes with different URLs rather than collapsing into one.

  An **unannotated** action keeps the `GET /<controller>/<action>` default, so
  annotating one action never changes another. Annotations are read from the
  controller *source* (Lua discards comments, and this is authoring metadata, not
  runtime state). A `--[[ ]]` block comment is not an annotation, and a blank
  line ends the block. An unknown `@directive` or HTTP method is reported as an
  error rather than ignored, so a typo cannot silently drop a route.

- `tests/test_annotations.lua` — 64 checks: the parser on synthetic sources
  (the short verb form for all seven verbs, multi-path directives, method lists,
  middleware config tables, `@phases`, `@GET` rejection, missing leading slash,
  block comments, blank-line separation, unknown directives, bad methods), the
  `auto_routes_unannotated` switch in both directions, and end-to-end discovery
  over a fixture controller.
- `examples/api/Api/controller/demo.lua` now demonstrates annotations
  (`@get /demo/echo/{word}`, `@post /demo/echo`, `@get` with no path,
  `@phases access = api_token`, `@middleware request_id`), verified under nginx.

### Fixed
- `@route` with a comma-separated method list only parsed the first method.
- An unknown HTTP method was reported in lower case (`'wrong'`), making the
  message hard to grep back to the source. It is reported as written.
- An annotation block separated from its action by a **blank line** still
  applied, because the block walk skipped blank lines instead of stopping at
  them.
- Multiple route directives with **different paths** collapsed into one: only the
  last path survived, so `@get /a/{id}` + `@post /a` sent the GET to `/a`. Each
  directive now keeps its own path.
- A path written without a leading slash registered an unreachable route key.

## [Unreleased] - Convention-based controller routing

### Added
- **`Tilua.core.discovery`** — scans `<App>/controller/` at worker start and
  registers a route per public action, so an MVC app no longer has to list every
  action in `routes.lua`:

  ```
  MyApp/controller/index.lua     Index:index()   -> GET /index/index
  MyApp/controller/user.lua      User:show(id)   -> GET /user/show
  MyApp/controller/admin/post.lua Post:index()   -> GET /admin/post/index
  ```

  Enable with `auto_routes = true`. Off by default: discovery depends on a
  project layout, and a framework that silently invents URLs is harder to reason
  about than one that does not.

  - Private helpers (leading `_`) and the framework's controller base methods
    (`assign` / `display` / `service` / `model` / `fail` / `_call` /
    `_construct`, plus the class system's injected `define`) are not registered.
  - Nested controllers are scanned to one level (`admin/post.lua`).
  - Controllers are NOT instantiated at scan time; each route is bound to a
    `<module>@<action>` handler string, which the dispatcher already resolves
    per request.
  - A missing controller directory is skipped, not an error.
  - `auto_routes_prefix` nests every discovered route (e.g. `/api`).
- `tests/test_discovery.lua` — 38 checks covering the scan, filtering, handler
  form, precedence, and the error/skip paths.
- `examples/api/Api/controller/demo.lua` + `/demo/*` expectations — discovery
  verified under real nginx.

### Fixed
- **`resty`-style `@` handler strings needed the full module path.** The
  dispatcher resolves `"<module>@<action>"` and prefixes the app name only when
  the string does not already contain `"<app>."`. A bare `"demo@hello"` became
  `Api.demo` (missing the `controller.` layer) and silently 404'd.
- **`route.get(path, handler, middleware)` registered the middleware as the
  handler**, and **`route.get(path, handler, nil, { phases = ... })` lost its
  phase config.** Both are documented call shapes; see the detailed notes below.
- **A route registered after boot was silently unreachable.** `add_route` recorded
  it in `route.rules`, but `build_index` compiles from `route.rule_caches`, so the
  trie never saw it until someone re-ran `init_rule_caches`. Registration now
  compiles immediately, and the index rebuilds lazily on the next match.
- **Registering a route before the app name was known crashed** with
  `attempt to index a nil value`. Such routes are now parked in
  `route._pending_rules` and adopted by the next `set_app_name`, which is what
  makes registering routes ahead of time work.
- **`route.run` returned the boolean `true`** where every caller expected the
  matched rule, so `router.midware` / `router.responser` were nil — route-level
  middleware never ran and the dispatcher fell through to a nil handler.
- Explicit routes now always beat discovered ones for the same method + path.
  Discovered rules carry `source = "scanned"`; `pick_rule` prefers `"explicit"`,
  and a discovered duplicate is not registered at all when an explicit route
  already covers it.
- `tests/support/lua_stub.lua`: the `lfs` stub reported **every** path as a
  directory and its `dir()` returned an iterator that never yielded. Both were
  wrong in the same direction as a bug — code branching on `lfs.attributes(p,
  "mode")` took the directory branch for files, and anything enumerating a
  directory saw it as empty. Now backed by real `stat`/`ls`.

### Notes
- `plugin.request_trace`'s `on_boot` / `on_worker_init` hooks call
  `app.logger`, which is nil during worker boot in some configurations; the hook
  is caught and logged rather than fatal. Tracked in `docs/ANALYSIS-2.md`.

## [Unreleased] - Plugin hooks on the phase path, and route call-shape fixes

### Fixed
- **Plugin hooks now fire on the phase path.** `on_request`, `on_dispatch`,
  `on_response` and `on_error` were emitted only from `App:run()` and
  `Channel.dispatch()` — the *non-phase* entry points. A normal nginx config runs
  the lifecycle handlers, which emitted nothing except `on_route_loaded`, so the
  entire plugin system was inert in production. `on_worker_init` was declared and
  documented but never emitted anywhere.
  - `on_worker_init` fires once per worker from `init_worker_by_lua` (guarded, so
    the lazy call from `rewrite_by_lua` cannot re-fire it).
  - `on_request` fires once per request in `rewrite_by_lua`, before rewrite
    middleware.
  - `on_dispatch` fires once per request in `content_by_lua`, after the route is
    matched and validated.
  - `on_response` fires once per emitted response, through a single
    `lifecycle.emit_response` used by every terminal path (content, rewrite
    short-circuit, middleware denial, error rendering).
  - `on_error` fires from the lifecycle error path **and** from the dispatcher,
    because the dispatcher catches handler errors itself — without that, the hook
    never saw a route handler that throws.
  - Hook failures were already caught; the bus call is too, so a malformed
    registry entry cannot break a request.
- **Route-level middleware never ran.** `route.run` returned the **boolean**
  `true` as its first value while every caller named it `matched` and passed it
  straight to the dispatcher. Truthy, so routing appeared to work — but
  `router.midware` and `router.responser` were nil, so `create_responser` saw no
  handler. It now returns the rule.
- **`route.get(path, handler, middleware)` registered the middleware as the
  handler.** With three arguments Lua binds `verbs="/p"`, `path=<function>`,
  `handler={middleware}` — all non-nil, so the old reorder was skipped. This is
  the form documented in `docs/ROUTER.md` and used by both examples; the route
  ended up with no handler *and* no middleware.
- **`route.get(path, handler, nil, { phases = ... })` lost its phase config.**
  The `nil` middleware placeholder must be preserved positionally. Two attempts at
  re-expanding the arguments dropped it — first by nesting the tail in a new
  table, then because `#t` (and a `table.unpack` without an explicit end) stops at
  the `nil`. The trailing arguments are now carried with an explicit count. A
  `{ phases = ... }` table passed without a `nil` placeholder is handled too.

### Changed
- `Plugin.emit(hook, app, ctx, ...)` — `app` is now always the first argument and
  `ctx` the second. Several hooks run before a request exists, and `app` is the
  container, so `app:make(...)` works everywhere; the previous signatures were
  inconsistent between the boot hooks and the request hooks.
- `Plugin.load_from_config` resolves config through `app:make("config")` so it
  works on the Application class as well as an instance, and records modules it
  could not require in `Plugin._load_errors` instead of swallowing the failure.
- `tests/support/lua_stub.lua`: `ngx.exit` now raises a catchable error instead of
  calling `os.exit`. It used to terminate the whole test process, silently
  truncating any suite that drove the content phase (exit code 200, no summary).

### Added
- `examples/api/Api/plugin/request_trace.lua` — a worked plugin that records a
  per-request trace through the hooks (`on_request` / `on_dispatch` /
  `on_response` / `on_error`) and exposes it at `GET /traces`.
- `tests/test_plugin_hooks.lua` — drives the real phase handlers and asserts each
  hook fires, in order, exactly once: 40 checks covering success, 404, a throwing
  handler, a middleware denial, a throwing hook, and the non-phase entry point.
- `tests/test_trie_router.lua` — coverage for every documented `route.get()`
  call shape (2-arg, 3-arg middleware, 3-arg phases, nil placeholder, internal).

### Documentation
- `docs/EXTENSIONS.md` rewritten around the real hook contract: which phase each
  hook fires in, its arguments, and the `matched` / `status` / error semantics.

## [Unreleased] - Onboarding: examples, CLI entry point, fewer hard dependencies

### Added
- **`bin/tilua` + `bin/tilua.lua`** — a real CLI entry point. The README had
  documented `tilua doctor` / `serve` / `new` for several releases with no such
  executable in the repository. It runs under plain LuaJIT: no nginx, no `resty`
  CLI (the stock `openresty/openresty` image does not ship one), and no
  LuaFileSystem or lua-resty-jit-uuid.
- **`examples/hello`** — a minimal but complete application: a view, a path
  parameter, a JSON endpoint, a throwing handler, and a route declared in config.
  Ships with `nginx.conf`, `Dockerfile` and `docker-compose.yml`, so
  `docker compose up --build` works with nothing installed.
- **`examples/api`** — a realistic JSON service: container services
  (singleton + scoped), two annotated middleware split across phases, declarative
  parameter validation (`reg`, `in`), structured errors, JSON request bodies, and
  a per-route access guard.
- **`examples/README.md`** — how to run both, what each route demonstrates,
  which files to read in what order, and a troubleshooting table.
- **`tests/run_example.sh`** / **`tests/run_examples.sh`** — boot an example
  under real nginx and assert every path in its `.expect` file, printing status
  and body.
- **`tests/support/http_get.lua`** — small FFI HTTP client for those tests.
- **`tests/syntax_check.sh`** — parse-checks every Lua file **including
  `examples/`**, which the previous check skipped.
- **`tests/test_path_no_lfs.lua`** — proves the framework loads and resolves
  paths with `lfs` hidden.
- **`tests/test_middleware_registry.lua`** — loads every middleware named by the
  default config, expands every default group, and instantiates each one.

### Changed
- **LuaFileSystem is now optional.** `Tilua/utils/path.lua` used to `error()` at
  require time without `lfs`, so the framework could not load at all on a stock
  `openresty/openresty` image — which ships no `lfs.so`, despite LuaFileSystem
  often being described as bundled with OpenResty. A pure `io`/`os` fallback now
  covers existence, type, size and modification time; `path.dir`, `path.chdir`
  and symlink queries still need `lfs` and are documented as such.
- **`resty.jit-uuid` is now optional.** A built-in v4 UUID generator uses the
  same randomness (`/dev/urandom`, falling back to OpenSSL `RAND_bytes`) as
  `util.random_string`.
- Removed the unused `require("random")` (flagged in `docs/ANALYSIS.md` §5.1).
- `tilua doctor` now reports `lfs` and `resty.jit-uuid` as **optional** instead
  of failing on them, and treats `## [Unreleased]` as a valid CHANGELOG head so
  a checkout with work in progress no longer reports a version mismatch.
- `CLI.run` skips app boot when no `App.name` is set (running from the framework
  checkout) instead of emitting "App.name must be set" on every command.

### Fixed
- **`Tilua.middleware.json_response` required a non-existent module**
  (`Tilua.midware.base` — only the `Tilua.midware` *module* shim exists, not the
  `.base` submodule). Every other middleware had been migrated; this one was
  missed, so any app using the default `api` / `web` middleware groups crashed at
  boot with "module 'Tilua.midware.base' not found".
- **Config-declared routes crashed the master process.** `route.init_rule_caches`
  sorted rules by declaration order, but keys injected from `config.route` never
  went through `add_route` and had no order index, so the sort compared `nil`
  with a number: "attempt to compare nil with number" in `init_by_lua`. Rules
  missing an index are now assigned one.
- **`init_rule_caches` duplicated every rule when called twice.** It now rebuilds
  from `route.rules`, which makes it idempotent.
- **Validation specs on rules without path parameters aborted the request.**
  The spec was parsed only for the `~` matcher, so `get /echo mode:in,upper,lower`
  (matcher `=`) left `rule.validation` a raw *string* and `route.validate` called
  `pairs()` on it — "bad argument #1 to 'pairs' (table expected, got string)".
  Validation is now parsed whenever the spec is present.
- **`in` / `notin` validation silently dropped all values but the first.**
  `util.parse_expression` returns a list for multi-value input, and the router
  stored `v[2]` — so `mode:in,upper,lower` became `{"in", "upper"}`, rejecting
  `lower`. The argument is now rebuilt into a string and split at match time;
  this also stops a regex containing a comma from being truncated.
- `path.exists` returned the boolean `false` for a missing path instead of the
  documented `nil` (`a ~= nil and P` evaluates to `false`, not `nil`).

## [0.9.3] - Project scaffolding

### Removed
- **Penlight is no longer referenced anywhere.** It was never actually installed
  in a stock OpenResty, so every Penlight call site was already running its
  hand-rolled fallback — the dependency only existed as dead branches and a
  misleading README row. Verified by probing the runtime: `pl.tablex`,
  `pl.pretty` and `pl.dir` all fail to load.
  - `Tilua/utils/util.lua` — dropped the soft-loads of `pl.tablex` / `pl.pretty`.
  - `Tilua/utils/useragent.lua` — dropped an **unused hard `require("pl.tablex")`**
    (the only hard Penlight dependency left in the framework).
  - `Tilua/core/lifecycle.lua`, `Tilua/middleware/body_parser.lua` — dropped the
    speculative `pcall(require, "pl.dir")` `makepath` attempts; `mkdir -p` was
    always the branch that ran.

### Added
- `Tilua/core/helpers.lua` — pure-Lua replacements for the Penlight surface the
  framework actually used: `update` (merge/append), `size`, `foreach`, `pretty`.
- `Tilua/utils/path.lua` — `_searchpath_fallback`, a pure-Lua
  `package.searchpath`. The framework previously called `package.searchpath`
  directly; it exists in OpenResty's LuaJIT but not in every LuaJIT build, where
  its absence broke `App.path` (and therefore the whole view engine).
- `tests/test_no_penlight.lua` — asserts no `require("pl...")` survives in
  `Tilua/`, and covers each replacement (including that `helpers.pretty` output
  re-parses as Lua and that cycles do not hang).

### Fixed
- `helpers.update` appends arrays instead of overwriting them. `pairs({3,4})`
  yields `1 -> 3, 2 -> 4`, so array-ness must be detected on the source *table*,
  not per element.
- `util.extend` now deep-merges nested tables. With Penlight absent it fell back
  to a flat overwrite, so `app.lua`'s layered config
  (`Tilua.config.default` -> `<App>.config.default` -> `<App>.config.<status>`)
  **replaced** whole nested config subtables instead of merging them, silently
  losing framework defaults for any nested table the app also defined.

### Changed
- `util.extend` delegates to `helpers.update` so there is one merge
  implementation. `helpers.extend` remains a flat overwrite for
  middleware/config option merging.

### Added (scaffolding)
- `tilua new <Name>` — generates a runnable project skeleton:
  `<Name>/app.lua`, `routes.lua`, `config/dev.lua`, `controller/index.lua`,
  `view/index.html`, plus `public/`, `.gitignore` and a README.
  - `--dir DIR` target directory (default `./<Name>`), `--force` to write
    into a non-empty one
  - refuses invalid module names and non-empty targets; `--force` only fills
    in missing files and never overwrites an existing one
  - the generated config disables the HTML cache and uses stderr logging, so
    a fresh project boots with no Redis and no writable log directory
- `tests/test_cli_new.lua` — asserts the generated files exist, are valid
  Lua, use current APIs (not `derive()`), that the routes actually register
  against the live router, that the view renders through `Tilua.template`,
  and that the scaffolded `SHDICIT_NAME` matches what `tilua serve` declares.

### Fixed
- `tilua serve` now declares both `app_cache` and `app_test_cache` as shared
  dicts. The framework default for `config.SHDICIT_NAME` is `app_test_cache`,
  which the previously generated config did not declare.
- README Quick Start was documenting APIs that do not exist and would fail on
  first run (`docs/ANALYSIS.md` item 25):
  - `require("Tilua.app").derive()` → `.define()`; there is no `derive()`
  - the `_init` / `self:super(self)` app entry → class fields + `_construct`
  - `require("Tilua.controller").derive()` → `.define()`
  - controller path `MyApp/Home/controller/index.lua` →
    `MyApp/controller/index.lua`, which is what `mvc_router` actually resolves
  - route/response requires updated to `Tilua.http.router` /
    `Tilua.http.response` (the old paths remain as shims)

## [0.9.2] - Dev server

### Added
- `tilua serve` — local OpenResty dev server, no hand-written nginx.conf
  needed to get started:
  - autodetects the app module (`<Name>/app.lua` under the project root),
    with a clear "pass --app" error when it is ambiguous or absent
  - generates `.tilua/dev.nginx.conf` wiring all six lifecycle phases
    (`init` / `init_worker` / `rewrite` / `access` / `content` / `log`)
  - `lua_code_cache off` + `daemon off` + single worker: edited Lua is picked
    up on the next request, Ctrl-C stops the server
  - flags: `--port`, `--app`, `--root`, `--log`, `--print-conf`
  - `--print-conf` writes and prints the config without starting anything,
    which also makes it usable as a starting point for a real deployment
  - falls back to a readable message (not a stack trace) when no OpenResty
    binary is on PATH; a stock nginx without ngx_lua is explicitly rejected
- `tests/test_cli_serve.lua` — covers autodetection, both flag styles, phase
  wiring, brace balance of the generated config, and all three error paths.

### Changed
- CLI argument parsing now understands `--flag value`, `--flag=value` and
  bare `--flag` booleans, in addition to positional arguments.
- `tilua help` output is sorted; it previously iterated `pairs()` and so
  printed commands in an arbitrary order.
- `.gitignore`: ignore the generated `.tilua/` scratch directory.

## [0.9.1] - Dependency-free templates

### Added
- `Tilua.template` — a small, dependency-free template engine backing
  `Tilua.view`:
  - `{{ expr }}` HTML-escaped output, `{{{ expr }}}` raw output
  - `{% lua %}` arbitrary Lua statements for control flow
  - `{# comment #}` compiled away, no output
  - `include(view, extra_context)` for partials, context inherited unless overridden
  - `tests/test_template.lua` (interpolation, escaping, loops, comments,
    include, precompile→process round-trip)

### Removed
- The `lua-resty-template` dependency. `Tilua.core.lifecycle.init_view_engine`
  now requires `Tilua.template` instead; `Tilua.view`'s call sites
  (`new/caching/compile/compile_string/process/precompile`) are unchanged, so
  existing `view:render(...)` call sites in application code do not change.
- `resty.template` stubs in `tests/support/lua_stub.lua` and
  `tests/e2e/lua/resty/template.lua` (no longer needed).

### Changed
- `tilua doctor` no longer checks for `resty.template`; it now checks for
  `lfs` (LuaFileSystem), which `Tilua.utils.path` has always hard-required
  but was previously undocumented and unchecked.
- README dependency table: removed `lua-resty-template`, added the
  previously-undocumented `lfs` requirement.

## [0.9.0] - Trie router + lifecycle fixes

### Added
- `Tilua.http.router` rewritten as a **segment trie**:
  - `{name}` single-segment parameters, `*` / `{name*}` wildcards
  - per-segment precedence **static > `{name}` > `*`**, independent of
    registration order
  - `~ <pattern>` regex routes kept in a flat fallback list (arbitrary regex
    cannot live in a trie)
  - trailing-slash and duplicate-slash normalisation
- Route-scoped OpenResty phase middleware:
  `route.get(path, handler, mid, { phases = { access = { "auth" } } })`
- `tests/test_trie_router.lua` (56 assertions)
- `tests/e2e/` – real-nginx end-to-end suite with dependency stubs
- `docs/LIFECYCLE.md` – measured OpenResty phase semantics + redesign

### Fixed
- **Cross-request response leak.** `dispatch:_construct` cached `self.ctx`, and
  the dispatcher is a container **singleton** first built on the Application
  *class* during worker boot — so every request resolved its scoped services
  (`response`, `request`, `view`, …) on the class container, sharing them
  between requests (request N saw request N-1's body). The dispatcher now reads
  the live request context instead of caching a receiver.
- `dispatcher.create_responser` stored the handler on the worker singleton
  (`self.handler`), leaking the previous request's handler. Now local.
- `response._construct(ctx)` accepted only a context, so the documented
  `return response("text")` produced an **empty 200** (the string became `ctx`).
  It now accepts a context or a body value.
- A bare string return was treated as a **view name** instead of text; now it is
  plain text, and `return "view", {}` explicitly renders a view.
- `get_bind_args` indexed captures positionally and skipped any name containing a
  digit, so `/user/{name}` passed `nil`.
- `request:get_header(name)` could never work: the class system's `__index`
  wrapper calls `get_*` with only the receiver, so `name` received the request
  table. Headers are now read live from `ngx.req.get_headers()`, and the API
  caveat is documented.
- Header snapshots taken in `rewrite_by_lua` could miss custom headers entirely
  (measured: client sent `X-Admin-Token`, `ngx.var.http_x_admin_token` was set,
  the snapshot held only `connection` and `host`).
- Phase middleware names were not resolved against the application namespace, so
  `access = { "admin_guard" }` resolved to nothing and the whole phase was
  silently skipped. Resolution is now
  `alias → fully-qualified → <App>.middleware.<name> → as-is`.
- `middleware.phase_list` returned bare strings while `instance()` expects
  `{ name, config }`; entries are now normalised.
- `pcall` discarded `route.match`'s second return value, so route-scoped phase
  middleware never saw a matched rule.
- `router.parse_rule` defaulted the matcher to `*` (prefix) for every rule, so
  `/nope` matched `/` and `{name}` routes never compiled to a regex. Unprefixed
  paths are now exact.
- `route.add_route` silently dropped `route["GET /x"] = handler` registrations
  (the `__newindex` handler passed two arguments to a three-argument function).
- `ensure_dir` misread `os.execute`'s return value and treated a successful
  `mkdir` as failure, crashing worker boot.
- `app.lua` required the routes module before `set_app_name`, so rules declared
  at require time were registered under the wrong key.

### Changed
- Trie-based matching is O(path segments) instead of scanning candidate lists.
- `find_matched_route` / `select_best_match` / `parse_rule` /
  `parse_path_to_regex` are retained as thin wrappers.
- `tests/test_router.lua` and `tests/test_router_index.lua` removed: the former
  asserted a boolean from `find_matched_route` (long dead) and the latter
  asserted the pre-trie index internals.

### Known limitation
- The scope that existed before an **internal redirect** (`ngx.exec`) is not
  released eagerly: OpenResty replaces `ngx.ctx` wholesale, leaving the old
  context unreachable. It is reclaimed by GC when the request ends.

## [0.8.0] - Application IoC Container

### Added
- `Tilua.core.container` – Laravel-inspired IoC container
  (`bind` / `singleton` / `scoped` / `instance` / `value` / `alias` / `extend` /
  `make` / `bound` / `has` / `call` / `forget` / `flush` / `defer` /
  `scoped_instances` / `define`)
- `Container.define()` – derive a class, with further subclassing supported
- Parent-chain resolution: a container consults its `_parent` for bindings and
  singletons, so a request context shares the worker's singletons
- `tests/test_container.lua`, `tests/test_app_container.lua`,
  `tests/test_lifecycle_container.lua` (168 assertions)
- `tests/support/lua_stub.lua` – shared no-OpenResty harness (ngx / lfs /
  cjson / resty.jit-uuid / resty.template), auto-detects OpenResty's lualib
- `tests/fixtures/TestApp/` – fixture application for integration tests
- `docs/CONTAINER.md` – container guide, including the class-vs-instance rules

### Changed
- `Tilua.app` now derives from `Tilua.core.container`; the application object is
  the container
- Every service is a container binding:
  - worker singletons: `config` `logger` `middleware` `router` `dispatcher`
    `view_engine` `plugin` `channel`
  - request scoped: `request` `response` `view` `cache` `db` `model` `service`
- All legacy `App:get_*` accessors are kept as thin wrappers over `make()`, so
  there is only one resolution path
- `Tilua.core.lifecycle` boots through `App:boot()`; `log_by_lua` releases the
  request scope via `App:flush_scope()`, replacing `on_app_handled_callbacks`
  (the old `App:on_app_handled` API still works)
- `Tilua.core.channel` / `Tilua.http.dispatcher` resolve services via `make()`
  instead of `app.route` / `app.dispatcher` / `app.config` properties

### Fixed
- `Tilua.log` never wrote anything: it looked for a non-existent `Tilua.log.file`
  backend, so every log line was buffered in memory and dropped. It now uses
  `Tilua.logging.writer`, has a real severity threshold, and gains the missing
  `warn` / `notice` methods plus `flush` / `close`
- `Tilua/middleware/init.lua:22` had a syntax error (`[[…\]]]`) that prevented
  the whole middleware package from loading
- `Tilua.app` could not resolve `view_engine`; `lifecycle.init_view_engine` is
  now exported

### Compatibility
- Existing applications keep working: `get_*` accessors, `unpack`,
  `on_app_handled`, `run` / `run_cli` and the channel API are unchanged
- `App:channel(ch)` was renamed to `App:use_channel(ch)` and `App:plugin(name)`
  to `App:get_plugin(name)`, because `channel` and `plugin` are now bindings

## [0.2.0] - 2026-09-15

### Added
- `Tilua.core.helpers` – pure Lua helpers (split, strip, find, deepcopy, reduce, …)
- `Tilua.core.errors` – structured TiluaError with JSON/text response helpers
- `Tilua.core.lifecycle` – OpenResty phase handlers extracted from app
- `Tilua.http.*` package: router, dispatcher, request, response
- `Tilua.middleware` as canonical middleware package
- Built-in health endpoint (`config.health_path`, default `/health`)
- Production config keys: `request_timeout`, `body_read_timeout`, `enable_json_errors`, `health_path`
- Smoke tests: helpers, errors, router, middleware
- Compatibility shims for Tilua.route / dispatch / midware, etc.

### Changed
- app.lua slimmed (~160 lines; was ~600+)
- Dispatcher uses helpers + structured error handling
- Router / request / middleware prefer helpers over hard Penlight requires
- Default dispatcher path: Tilua.http.dispatcher
- README rewritten

### Compatibility
- Existing require("Tilua.route") / Tilua.midware continue via shims
- Config accepts both middleware_* and legacy midware_* keys

## [0.1.0] - 2020

- Initial MVC kit based on OpenResty (pre-refactor)

## [0.7.0] - 2026-09-15

### Unified exceptions
- `Tilua.core.exception` – router/controller/service/database/middleware types
- API body: `{ code, message, request_id }`; production sanitizes secrets/SQL/paths
- Dispatcher + HTTP channel `xpcall`; `errors.apply` aligned
- `Service:fail`; docs/EXCEPTION.md

## [0.6.2] - 2026-09-15

### RW separation + model Query bridge
- Connection resolves master/slave endpoints from CSV host lists
- Separate keepalive pools per endpoint; SELECT prefers slave when rw_separate
- FOR UPDATE / writes still use master
- Model: to_query(), master(); Mysql selectInsert

## [0.6.1] - 2026-09-15

### Database polish
- Fixed `Query:build_select` token replacement order
- Fluent `Query.builder(db):table():where():get()/first()/count()`
- MySQL `insertAll` batch insert
- `Service:query(table)` fluent helper
- Model `_parseOptions` merge cleanup

## [0.6.0] - 2026-09-15

### Database layer restructure
```
Tilua/database/
  manager.lua      – pool by config hash
  connection.lua   – connect / keepalive
  transaction.lua  – nested-safe tx helper
  query.lua        – SQL builders + bind
  driver/mysql.lua – MySQL implementation
```
- `Tilua.db` and `Tilua.db.driver*` remain as compatibility shims

## [0.5.0] - 2026-09-15

### Service layer
- `Tilua.service.base` – business logic base (model/db/cache/transaction)
- `Tilua.service` manager – lazy load `app.service.Name`
- `App:get_service` / `Controller:service` / `Controller:model`
- docs/SERVICE.md

## [0.4.0] - 2026-09-15

### Extension architecture
- `Tilua.core.plugin` – plugin registry & hook bus
- `Tilua.core.channel` – HTTP / WebSocket / CLI entry multiplex
- Stubs: `Tilua.openapi`, `Tilua.cli`, `Tilua.websocket`
- App:use / App:channel / App:run_cli; lifecycle boots plugins from config.plugins
- docs/EXTENSIONS.md

## [0.3.0] - 2026-09-15

### Soft delete
- `soft_delete = true` or `"deleted_at"` column on model
- Auto scope on select/find; `with_trashed` / `only_trashed` / `restore` / `force_delete`

### Relations
- `hasOne` / `hasMany` / `belongsTo` / `relation(name)`
- `with(name, rows)` batch eager load
- Configure via `self.relations = { posts = { type="hasMany", model="Post", foreign_key="user_id" } }`

## [0.2.9] - 2026-09-15

### ORM query UX + hydration
- `Tilua.model.result` Row objects: get/set/to_table/save
- model: `first`, `get`, `find_by`, `value`, `pluck`, `exists`, `get_list`, `chunk`
- Optional `config.orm_hydrate = true` for automatic hydration on get_list
- Fixed stringx.strip after Penlight removal

## [0.2.8] - 2026-09-15

### ORM continued
- Process-local schema field cache (worker memory + optional Redis)
- MySQL getFields memoized per worker
- `query_bind` / `execute_bind` placeholder `?` binding via quote_sql_str
- escapeString prefers ngx.quote_sql_str
- initConnect / insert_id handling improvements
- Expanded tablex compatibility shim in model

## [0.2.7] - 2026-09-15

### ORM
- Restored model + db driver sources into tree
- Removed hard Penlight deps from model/driver/mysql (helpers)
- Field membership hash set for `_facade` filtering
- MySQL: configurable timeout/pool_size/keepalive; safer connect
- `parseKey` adds identifier backticks

## [0.2.6] - 2026-09-15

### Router performance
- Method-indexed route tables: exact map (O(1)), sorted prefixes, regex lists
- `_method_set` replaces linear method search
- `ngx.re.match(..., "jo")` instead of gmatch for single capture
- Best-match cache + candidate cache with size cap (2048)
- Prefix match anchored at path start; priority exact > regex > longest prefix
- `rebuild_index` on init / add / clear

## [0.2.5] - 2026-09-15

### Dispatcher + JSON
- Auto `response:json` for table returns when `enable_json_errors` or request wants JSON
- Status+message / status+table forms; passthrough if handler returns response object
- Structured errors respect JSON preference

### CSRF
- Auto-check unsafe methods; session + double-submit cookie (SameSite configurable)
- Accepts body field / header / cookie; rotates token after success
- View helpers `__CSRF__` and `__CSRF_META__`

### util.lua
- Soft-load Penlight; split/bind1/empty/is_array via helpers
- dump/extend work without Penlight

## [0.2.4] - 2026-09-15

### Request / Response
- Response: `json` / `text` / `html` / `no_content`, `attachment` / `inline`, chainable API
- Response: fix send_body for non-200 with body; sync ngx.status via set_status
- Response: table body auto-JSON; Content-Length maintained
- Request: `is_get/post/put/delete`, `is_ajax`, `is_json`, `wants_json`
- Request: `input(key)`, `client_ip` (trust_proxy), `bearer_token`
- Request: cookie jar + cached headers; lazy user-agent; safer get_pid
- tests/test_request_response_api.lua

## [0.2.3] - 2026-09-15

### Cookie module
- New `Tilua.http.cookie`: build / parse / encode / clear
- Response: `set_cookie` supports raw string, opts table, positional args; `clear_cookie`
- Request: parse `Cookie` header once into jar + ngx.var fallback
- Session uses cookie builder (Max-Age, SameSite, Secure, Path, Domain)
- SameSite=None automatically adds Secure
- tests/test_cookie.lua

## [0.2.2] - 2026-09-15

### Session rewrite
- Consistent colon-style API; fixed decode/destroy self bugs
- `_dirty` flag + lazy_write skips unchanged payloads
- Safer probabilistic GC (no per-request randomseed)
- Session id validation (length/charset)
- Cookie: HttpOnly, optional Secure, SameSite=Lax, Max-Age
- Middleware caches save_handler module; only sets cookie when present
- Redis handler restored + `Tilua.session.redis` alias
- New `Tilua.session.memory` handler for tests/dev
- pcall around start/write so session errors do not crash requests
- tests/test_session.lua

## [0.2.1] - 2026-09-15

### Fixed
- `App:run` now uses `route.run` (correct best-match + validation) instead of raw `find_matched_route` list

### Performance
- Router no longer deep-copies full rule caches on every request; shallow-copies only rules that need mutation
- Matched-rule cache returns by reference

### Changed
- cache / db / model / session / mvc_router / body_parser / html_cache / lifecycle prefer `Tilua.core.helpers`
- Soft-optional Penlight only for `makepath` when available
