# Tilua 项目分析报告

> 分析对象：`D:\Tilua\Tilua`（`VERSION` = 0.7.0，73 个 Lua 文件 / 约 10,000 行）
> 分析方式：逐文件静态阅读，覆盖 ORM 层、HTTP/路由/中间件层、核心运行时与文档。所有问题均标注 `file:line`。
> 本机**没有安装 lua / luajit / openresty / resty**，也没有 CI 配置，因此**没有执行任何代码** —— 全部结论来自源码阅读。

## 摘要（TL;DR）

| 维度 | 评价 |
|---|---|
| 架构意图 | **好**。MVC + 中间件管线 + 通道抽象 + 统一异常 + ORM 分层，有清晰的阶段化重构计划 |
| 当前可运行性 | **不可用**。响应体从不输出、日志全站失效、缓存一用即崩、默认中间件组一用即崩 |
| 数据层正确性 | **大面积失效**。软删除必崩、`where` 链第二次必崩、`add()` 拿不到 insert id、`chunk()` 丢 WHERE 漏数据、事务原子性失效、连接池跨用户串连接 |
| 安全 | **多处可绕过**。伪造客户端 IP、鉴权校验被缓存短路、CSRF 可自我满足、标识符无转义、Session 固定攻击 |
| 工程化 | **几乎没有**。无构建、无 CI、无测试 runner，且唯一的 ORM 测试替换了被测模块本身 |

**核心判断：问题集中在"接线"而非"架构"，但接线的缺失程度已经使框架在当前状态下无法完成一次正常的 HTTP 响应。**

---

## 1. 项目定位

**Tilua 是一个面向 OpenResty (LuaJIT) 的 MVC Web 开发套件**，类似 PHP 生态里的 ThinkPHP / ThinkCMF 的 Lua 版本：

- 经典 MVC（`controller` / `model` / `view`）+ 闭包路由（Express 风格）双范式
- 深度绑定 OpenResty 生命周期（`init_by_lua` → `init_worker_by_lua` → `set_by_lua` → `content_by_lua` → `log_by_lua`）
- 内置中间件管线、多驱动 ORM、Session、Redis/共享字典缓存、CSRF、HTML 缓存
- 自研轻量类系统（`Tilua.utils.class`）+ 大杂烩工具层（从 Penlight 改写的 `path` / `util` / `strings` / `tables`）

**规模分布（行数）**：

| 文件 | 行数 | 说明 |
|---|---|---|
| `Tilua/model/model.lua` | 1284 | 巨石类（78 个方法），ORM 全部职责 |
| `Tilua/http/router.lua` | 680 | 路由匹配 + 索引 + 校验 + 缓存 |
| `Tilua/utils/util.lua` | 454 | FFI/OpenSSL/uuid/随机数/时间…混杂 |
| `Tilua/utils/path.lua` | 419 | 从 Penlight 移植，硬依赖 `lfs` |
| `Tilua/http/response.lua` | 378 | 响应链式 API |
| `Tilua/database/query.lua` | 376 | SQL 构造器 |

文档（README/CHANGELOG/docs）声称 "Phase 1–3 完成，v0.2.0"，但 `VERSION` 文件是 `0.7.0`，CHANGELOG 里 `0.1.0`（2020）后面紧跟着 `0.7.0`、`0.6.2` … `0.2.1` 的**倒序**条目 —— 版本与文档完全失同步。

---

## 2. 架构总览

```
ngx content_by_lua
  └─ App:run()                              Tilua/app.lua:179
       └─ Channel.dispatch()                Tilua/core/channel.lua:45
            ├─ websocket (priority 50)      升级请求
            ├─ cli       (priority 10)      app._channel == "cli"
            └─ http      (priority 100)     ← 默认，注意优先级数值最小者先跑
                 ├─ /health 短路返回         core/channel.lua:73-87
                 ├─ route.run()             http/router.lua:638   (xpcall)
                 └─ dispatcher:run()        http/dispatcher.lua:189 (xpcall)
                      └─ prepare_response(handler())
```

分层意图（`docs/SERVICE.md`）：`Controller → Service → Model/DB/Cache`，各层通过 `Tilua.core.exception` 统一抛错，由 `Exception.render` 输出 `{code, message, request_id}`。

**设计上值得肯定的部分**：

- 中间件管线用 `reduce` + `reverse` 组合，`next` 链语义正确（`dispatcher.lua:38-58`）。
- 路由做了三级索引（精确 hash / 正则列表 / 长前缀排序）+ 匹配缓存（`router.lua:81-127`），比线性扫描有明显性能意图。
- 异常体系做了**生产环境脱敏**（`core/exception.lua:42-98`：密码/SQL/路径正则擦除、5xx 只回通用文案、`X-Request-Id` 贯穿），这个设计方向是对的。
- ORM 有软删除、关联、读写分离、批量预加载、字段缓存等相对完整的特性集。
- 兼容层（shim）保留了旧 require 路径，迁移成本低。

---

## 3. 致命问题：框架在当前状态下无法完整启动

这是最重要的结论。**至少 3 条主链路存在"引用不存在的模块"级别的硬错误**，且因为用了 `pcall(require)` 包裹而**静默失败**，不会报错、只会功能缺失。

### 3.1 `Tilua.log` 后端不存在 → 全站日志静默失效

```lua
-- Tilua/log.lua:97-103
function log.init(cfg)
    log.handler = import("Tilua.log." .. cfg.type)   -- cfg.type = "file"
    if log.handler then log.handler.init(cfg) end
    return log
end
```

`Tilua/log.lua` 是**文件**，不是目录；仓库里不存在 `Tilua/log/` 。`import` 内部是 `pcall(require, module)`（`utils/util.lua:394-403`），失败返回 `nil` 而非抛错 → `log.handler` 永远是 `nil`。

后果：

- `log:record()` 把条目塞进 `self.log_data`（内存数组），**但没有任何代码把它落盘** —— `log:flush()` 会 `self.handler.flush(self)` 直接空指针崩溃（`log.lua:86-88`）。
- 新写的 `Tilua/logging/writer.lua`（file / ngx / stderr 三种后端，实现是完整的）**从未被接入** `Tilua.log`。两套日志实现并存，实际生效的是坏掉的那套。
- `database/connection.lua:136,142,168`、`driver/mysql.lua:123`、`middleware/session.lua:44` 的所有 `logger:error(...)` 全部进了内存垃圾，生产环境**零可观测性**。

### 3.2 `log:warn` 不存在

```lua
-- Tilua/app.lua:185-187
if self.logger and self.logger.warn then
    self.logger:warn("channel dispatch: ", err or "nil", " – fallback HTTP")
end
```

`Tilua/log.lua` 只定义了 `debug` / `info` / `error`（第 68-78 行），**没有 `warn` / `notice`**。日志等级常量表里明明列了 `WARN`、`NOTICE`（第 7、12 行）。这段代码是 factually dead 的防御性判断。

### 3.3 默认缓存驱动不存在 → 用到缓存即崩

```lua
-- Tilua/config/default.lua:74,83
data_cache_handler = 'redis',
redis = { ..., driver = 'Tilua.cache.driver.redis' },
```

仓库中**不存在 `Tilua/cache/` 目录**。`Tilua/cache.lua:38-41`：

```lua
local driver = lw_util.import(config.driver)
if not driver then error('unsupported cache type ' .. config.driver) end
```

→ `app:get_cache()` 首次 `get/set` 时直接 `error`。Session 中间件、HTML 缓存、ORM 字段缓存都挂在 `ctx.cache` 上，**全链路连带失败**。

### 3.4 `json_response` 中间件 require 路径写错

```lua
-- Tilua/middleware/json_response.lua:1
local base = require("Tilua.midware.base")   -- ← 应为 Tilua.middleware.base
```

`Tilua/midware.lua` 是文件（兼容 shim），`Tilua.midware.base` 这个模块路径不存在。`Tilua.middleware.mvc_router`、`csrf_token`、`html_cache` 都已改成 `middleware.base`，只有这一个漏改。由于 `default.lua:25-26` 的 `middleware_group.api/web` 默认包含 `'json'`，**任何使用 web/api 中间件组的应用启动即崩**。

同一文件还有 Content-Type 拼写错误（第 9 行）：`"application/json;chartset=uft-8"` —— `chartset` / `uft-8` 两个词都拼错了。

---

## 4. 安全缺陷

### 4.1 `trust_proxy` 取 XFF 最左值 → IP 可任意伪造

```lua
-- Tilua/http/request.lua:224-240
if cfg and cfg.trust_proxy then
    local xff = self.header["x-forwarded-for"] ...
    local first = tostring(xff):match("^([^,]+)")   -- ← 最左 = 客户端完全可控
    if first then return trim(first) end
end
```

攻击者只需发 `X-Forwarded-For: 1.2.3.4` 就能伪造 `client_ip`。若用它做限流、白名单、审计日志，等于形同虚设。正确做法是取**右起第 N 个可信代理跳数**，而不是最左值。

### 4.2 路由匹配结果被缓存 → 校验逻辑被绕过

```lua
-- Tilua/http/router.lua:643-659
local bkey = cache_key(ctx.name, request_method, pathinfo)
local cached_best = best_match_caches[bkey]
if cached_best ~= nil then return true, cached_best end   -- ← 直接命中，跳过 select_best_match
...
best_match_caches[bkey] = best_match or false
```

而 `select_best_match` 里的 `route.validate(ctx, rule.validation)`（第 603、612、629 行）是**依赖请求上下文**的运行时校验（`router.lua:469-497`，支持 `reg/eq/neq/in/notin` 和函数式校验，用于 `{uid:\d+}` 这类路由约束）。

缓存键只有 `app + method + path`，**不含任何用户/会话维度**。命中缓存后校验被完全跳过（`router.lua:645`）。典型后果：

- 用户 A 命中 `/admin` 类带校验的路由并写入缓存 → 用户 B 用同样的 path 直接拿到该路由，即便 B 的上下文校验本该失败。
- 校验里若写了"已登录才可匹配"，缓存等于把鉴权短路了。

`cached_best == false` 分支（第 646-648 行）又返回 `false, pathinfo`，用 `false` 当哨兵值把"无匹配"和"匹配到 string 型 handler"两种情况混在一个槽位里，语义脆弱。

### 4.3 Session 与 CSRF 令牌退回可预测随机数

```lua
-- Tilua/session.lua:21-28
local function default_random_id()
    local ok, util = pcall(require, "Tilua.utils.util")
    if ok and util.random_string then return util.random_string() end
    return ngx.md5(tostring(ngx.now()) .. tostring(math.random(1, 1e9)))
end
```

`Tilua/middleware/csrf_token.lua:46-49` 有**完全相同的退化分支**。

`util.random_string` 本身实现是正确的（`utils/util.lua:362-372`：`/dev/urandom` → OpenSSL `RAND_bytes`，24 字节 base64）。问题在于 `pcall(require, "Tilua.utils.util")` 一旦失败（而 `util.lua` 确实有硬依赖问题，见 5.1），就退化到 `math.random` —— **LuaJIT 中 `math.random` 未显式 seed 时在 worker 内是确定性序列**，Session ID / CSRF Token 可被预测。这是安全实现"优雅降级到不安全"的经典反模式：失败时应当**报错或拒绝**，而不是降级。

### 4.4 `string.strip` 第二参数被静默忽略 → 文件名带引号

```lua
-- Tilua/middleware/body_parser.lua:47,51
name = strip(field[2], "\"")
filename = strip(file_fields[2], "\"")
```

`Tilua.utils.strings.strip(str)` 只接受一个参数（`utils/strings.lua:19-24`，内部 `gsub(str, "^ *", "")`）。第二个参数被丢弃，且该函数**只去掉空格、不去引号**。因此 multipart 解析出的 `filename` 会变成 `"report.pdf"`（含字面引号）。

### 4.5 开发环境把 `details` 原样返回给客户端

```lua
-- Tilua/core/exception.lua:257-262
if not prod and ex then
    body.error_code = ex.code
    body.layer = ex.layer
    if ex.details ~= nil then body.details = ex.details end   -- ← 未脱敏
end
```

`Exception.database(msg, status, details)` 允许把原始 DB 错误放进 `details`。`is_production` 的判定又过度依赖显式配置（见下），一旦误判为非生产，SQL 细节直接暴露给客户端。

### 4.6 `is_production` 判定链脆弱

```lua
-- Tilua/core/exception.lua:74-98
function Exception.is_production(ctx)
    if ctx and ctx.config then
        local env = ctx.config.env or ctx.config.environment or ctx.status
        ...
        if ctx.config.debug == false and (env == nil or env == "prod") then
            if ctx.config.app_env == "production" or ctx.debug == false then return true end
        end
        ...
    end
    if ctx and ctx.debug == false then return true end
    return false   -- ← 默认"非生产"，即默认不脱敏
end
```

默认返回 `false`（非生产），意味着**忘记配置就默认泄露**。安全默认应当反过来。README 示例里 `self.status = "dev"`、`self.debug = true`，与生产配置的约定（`prod` + `debug=false`）靠约定而非强制。

### 4.7 其他

- **`register_shutdown` / workers 全局状态**：`router.lua:46-49` 的匹配缓存、`middleware/html_cache.lua:15-16` 的 `rules` / `caches` 都是模块级全局表，`html_cache` 的 `caches[app_name]` 是**无上限的 worker 内存缓存**，且默认配置里的 `html_cache_time = 60`（`config/default.lua:4`）**从未被 html_cache 中间件读取**（它只认自己 `lifetime` 字段，默认 3600），属于内存泄漏 + 配置失效。
- `default.lua` 里硬编码了内网 IP `172.17.0.2`、`redis.timeout = 2000`（单位疑似秒，`lua-resty-redis` 实际用毫秒）、`multipart.tmpdir = '/tmp/Tilua-multipart-tmp/'`（固定路径，多实例会互相干扰）。
- `default.lua:47` 与 `:107` **重复定义了 `health_path`**。

---

## 5. 无法运行 / 死代码

### 5.1 `utils/util.lua` 有未使用的硬依赖

```lua
-- Tilua/utils/util.lua:59
local lrandom = require "random"
```

全文**从未使用** `lrandom`。`random`（luaossl 的 random 模块）不是标准 OpenResty 自带库 → `util.lua` 直接加载失败。而 `util` 是全局核心依赖（`app.lua:6`、`router.lua:33`、`model/model.lua:7`、`cache.lua:6`…），这足以让整个框架起不来。

同文件还有 `local ffi = require "ffi"`（第 28 行）、`require("resty.jit-uuid")`（第 37 行）、`require("cjson.safe")`（第 21 行）—— 与注释"Prefer pure helpers; soft-load Penlight only when available"（第 1 行）宣称的解耦目标矛盾：**Penlight 被 soft-load 了，但 `random` 被硬编码了**。

### 5.2 `Tilua.utils.useragent` 硬依赖 Penlight

```lua
-- Tilua/utils/useragent.lua:6
local tablex = require("pl.tablex")
```

而 CHANGELOG 0.2.1/0.2.7 明确写着"Removed hard Penlight deps"、"prefer `Tilua.core.helpers`"。`request.lua:118-138` 有 5 处懒加载 `useragent`，一旦走 UA 分支就需要 Penlight。

### 5.3 `Tilua.utils.path` 硬依赖 `lfs`

```lua
-- Tilua/utils/path.lua:22-29
local res, lfs = _G.pcall(_G.require, 'lfs')
if res then ... else error("Tilua.utils.path requires LuaFileSystem") end
```

`lfs` 不是 OpenResty 内置，需自行编译安装。而 `path` 被 `app.lua`、`lifecycle.lua`、`view.lua`、`body_parser.lua`、`html_cache.lua` 全局引用。

### 5.4 CLI 通道根本无法工作

```lua
-- Tilua/core/channel.lua:166-168
local function cli_match(app)
    return app._channel == "cli" or (not ngx) or
           (ngx and ngx.config and ngx.config.subsystem == nil and app._cli)
end

-- Tilua/cli/init.lua:77-83
if type(app.init_by_lua) == "function" then
    pcall(function() app:load_config(); app:load_route() end)   -- ← load_route 需要 ngx.re / path / lfs
end
```

`load_route → route.init_rule_caches → rebuild_index` 依赖 `ngx.re.match`、`Tilua.utils.path`（`lfs`）。在纯 `lua` 环境下 `require("Tilua.http.router")` 第 3 行 `ngx.re.sub` 就 nil 索引崩溃。所以"脱离 OpenResty 跑 CLI"这个卖点目前不成立 —— 整个框架**没有一处能脱离 ngx 运行**。

### 5.5 README 快速开始示例本身是错的

```lua
-- README.md:65-72
function App:_init()
    self.name   = "MyApp"
    self.module = "Home"
    self.debug  = true
    self.status = "dev"
    self:super(self)      -- ← 框架里没有 super
end
```

全仓库搜索 `_init` 只命中两处**注释**（`model/model.lua:134`、`service.lua` 无），类系统实际调用的构造钩子是 `_construct`（`utils/class.lua:67-70`）：

```lua
if child.__parent then child.__parent._construct(instance, ...) end
return t._construct(instance, ...) or instance
```

两个后果：

1. **`App:_construct()` 永远不会执行** → `self.midware` 和 `self.on_app_handled_callbacks` 都是 `nil`（`app.lua:23-27`）。`dispatcher.lua:45` 的 `self.ctx.midware.instance(...)` 立刻 nil 索引崩溃。
2. **`self:super(self)` 不存在** → `super` 从未在框架中定义（搜索 `super` 零命中），照抄 README 会直接报 "attempt to call method 'super' (a nil value)"。

也就是说，**唯一一份上手指南给出的入口代码是跑不通的**。README 第 5 行还写着 "Status: v0.2.0"，与 `VERSION`（0.7.0）不符。

### 5.6 `model:select` 的标量分支把 where 条件丢掉

```lua
-- Tilua/model/model.lua:368-401
function model:select(options)
    if is_string(options) or is_number(options) then
        ...
        self.options.where = where        -- ← 设置到 self.options
    ...
    options = self:_parseOptions(options) -- ← 第 401 行：传的是原始标量，不是 self.options
```

而 `_parseOptions(options)` 内部（第 441-474 行）先 `tablex.update(self.options, options)` 取 `self.options`，最后又 `self.options = {}` **清空**（第 473 行）。标量分支写入的 `where` 依赖这条隐式通路，而 `_parseOptions` 结束时无条件清零 —— 链路极其脆弱，且 `select(5)` 这类主键查询的正确性完全依赖调用顺序。

同一函数第 390 行 `where[#pk[j]] = options[j]` 是明确 bug：`pk[j]` 是列名字符串，`#` 取的是字符串长度，键名变成数字而非列名。

### 5.7 `app.lua` 的 run 回退分支是死代码

```lua
-- Tilua/app.lua:184-192
local matched, router = self.route.run(self)   -- self.request 从未初始化
```

若 `Channel.dispatch` 返回 `nil`（无 channel 匹配），走到这里 `self.route` 和 `self.request` 都可能是 `nil` → 崩溃。而且 `self.logger:warn` 也不存在（见 3.2）。这个"回退"路径从未被真正执行过。

---

## 6. 设计问题

### 6.1 自研类系统有继承缺陷

```lua
-- Tilua/utils/class.lua:50-56
function M.define(parent)
    local child = get_definable_class()
    if parent then child = merge(child, parent) end   -- merge = 浅拷贝（utils/tables.lua:14-26）
```

- `child` 是父类的**浅拷贝**，不是原型链引用。父类方法在两个表里各存一份 → 运行中给父类加方法，已定义的子类**看不到**。
- 每个属性读取都走 `__index` 闭包 + `rawget(class, 'get_' .. key)` 字符串拼接（第 10-19 行）→ **热路径每次访问都做一次字符串拼接 + 一次 hash 查找**，比标准 `__index` 表查找慢得多。
- `setter` 无条件 `rawset`（第 28 行），意味着 `__newindex` 永远走自定义路径，没有对 `body` 之类的"虚拟属性"支持（`response.lua:51` 定义了 `__newindex_body` 但类系统根本不调用它）。
- `is_sub_class` 只比较直接父类（第 40-48 行），多级继承判断失效。
- `dispatcher.lua:255-267` 的动作解析顺序可疑：`elseif type(handler._call) == "function"` 分支排在 `elseif type(handler[action]) == "function"` **之前**。由于 `Tilua.controller` 自己定义了 `_call`（`controller.lua:31-33` 返回 `404`），凡继承该基类走 MVC 控制器的场景，都会先命中 `handler._call`。这里依赖 `handler.__parent[action]` 的真假来兜住，耦合了类系统的内部结构，一旦 6.1 的类系统改成真正的原型链，或子类用 `class()` 而非 `class.define()` 定义，行为就会翻转成"永远 404"。
- `dispatcher.lua:270` / `dispatcher.lua:229`：`lw_util.import` 失败（控制器模块里存在语法错误或运行时错误）时返回 `nil`，被静默转成 `errors.not_found()` → **代码 bug 表现为 404**，排查成本极高。

### 6.2 日志双实现

`Tilua/log.lua`（旧，坏）+ `Tilua/logging/writer.lua` + `Tilua/logging/formatter.lua`（新，完整但未接线）并存，且新旧接口不一致（`log.handler.flush` vs `Writer`）。这是重构做到一半的典型状态。

### 6.3 巨石类

`Tilua/model/model.lua` 1183 行承担：字段缓存、SQL 拼装、软删除、关联、事务、结果水合、查询桥接……`Tilua/http/router.lua` 625 行混合了规则解析、索引构建、校验、缓存、分发。

### 6.4 `utils/util.lua` 是杂物间

FFI 声明、OpenSSL `RAND_bytes`、`gethostname`、`/dev/urandom` 直读、uuid、时间、字符串、数组、JSON、URL 解析混在一个 454 行文件里（第 39-57 行的 `ffi.cdef` 甚至重复声明了 `read` / `write` / `close` / `open` 等 libc 符号）。其中 `get_rand_bytes` / `urandom_bytes` 是从 `lua-resty-session` 抄来的代码，但注释与实现存在不一致。

### 6.5 无构建 / 无测试基础设施

- **没有** Makefile、rockspec、CI 配置、`.busted`、任务运行器。
- `tests/*.lua` 是 10 个裸脚本，用 `print("xxx passed")` 表示成功，靠 `error()` 表示失败，**没有断言库、没有 runner、没有退出码约定、没有 CI 集成**。
- 测试文件各自**内联 `ngx` stub**（`test_cookie.lua:1`、`test_request_response_api.lua:2`、`test_orm_helpers.lua:2`…），没有共享 harness。
- 最严重的是 `tests/test_orm_helpers.lua:5-31` **用 `package.preload` 把 `Tilua.utils.class` 和 `Tilua.utils.util` 替换成了测试自己写的假实现** —— 这个测试验证的是测试桩，不是产品代码。真实的类系统（含 6.1 的缺陷）从未被覆盖。
- `test_router.lua:29-31` 直接写明"可能匹配也可能不匹配，只要不崩溃就行"，等于放弃断言。

### 6.6 文档与实现脱节

| 文档声称 | 实际情况 |
|---|---|
| README "Status: v0.2.0" | `VERSION` = 0.7.0 |
| README 目录结构 | 未提 `service/`、`database/`、`logging/`、`openapi/`、`cli/`、`websocket/` |
| README "Penlight (being reduced)" | `random` / `lfs` / `pl.tablex` 仍是硬依赖 |
| CHANGELOG "Built-in health endpoint" | 存在，但看 `channel.lua:76-77` 直接字符串拼 `app.name` 进 JSON（未转义，app 名可控时是注入点） |
| CHANGELOG「Removed hard Penlight deps」 | `useragent.lua:6` 仍 `require("pl.tablex")` |
| `docs/EXTENSIONS.md` 的 OpenAPI/CLI/WS | 三个都是 stub（`openapi/init.lua:70` 注释直说 "future: auto-scan"） |
| `docs/EXCEPTION.md` 说 `Tilua.core.errors` 与 exception 同管线 | 成立 |

CHANGELOG 版本号倒序排列（0.1.0 → 0.7.0 → 0.6.2 → …）也不正常。

### 6.7 其他实现细节问题

- `utils/util.lua:440-455`：`elapse_time_start(tag, ctx)` 构造了 `tag` 变量却**从未使用**，总是写 `ctx.tag`；`elapse_time_end` 同理。多计时器会互相覆盖。
- `utils/util.lua:146-157`：`index_value` 用 `if not res[properties[i]]` 判断中间节点存在性 → 值为 `false` 或 `0` 时提前返回 `nil`。
- `service/base.lua:60-92`：`Service:transaction` 找不到 driver 时**静默降级为无事务执行**（第 78-81 行 `return fn(self)`）—— 事务语义悄悄丢失。第 71-72 行甚至用 `self.ctx.model["User"] or self.ctx.model["user"]` 这种硬编码名字去猜默认连接，非常脆弱。第 91 行 `return error(a)` 用 `pcall` 的字符串错误值再抛，丢失原始 traceback。
- `service/base.lua:117`：`self.ctx.db and self.ctx.db()` —— `ctx.db` 是 manager 表（`app.lua:71`），不是函数，这个分支永远不成立。
- `core/plugin.lua:69-85`：`Plugin.emit` 的 `pcall` 会吞掉所有插件异常，仅靠 `ngx.log`；钩子失败对调用方完全不可见。
- `core/channel.lua:100-110` / `dispatcher.lua:199-213`：错误在两处被 `xpcall` 捕获、两处渲染，职责重叠。
- `middleware/html_cache.lua:94,102,110`：`caches[self.ctx.name][key]` 若 `_construct` 未执行（`config.type ~= 'memory'`）则为 `nil` 索引崩溃。
- `middleware/html_cache.lua:65-70`：`helpers.find(rule.path.params, m[1])` 用 `find` 做"值→索引"反查，params 含重复值时结果错误。
- `session/session_redis_hanler.lua`：文件名拼写错误（`hanler`），且需要靠 `session/redis.lua` 一行 shim 兜住。
- `middleware/init.lua:19`：`midware_group_parsed` 是模块级缓存，配置变更后不失效。
- `view.lua:66-68`：`setmetatable(self.context, {__index = self.mounted_context})` 在每次 `fetch` 时**覆盖 context 的 metatable**，破坏调用方传入的 context。
- `model/model.lua:389`：`where[#pk[j]] = options[j]` —— 用 `#pk[j]` 作键，`pk[j]` 是字符串时 `#` 是长度，几乎必然是逻辑错误（应为 `where[pk[j]]`）。
- `model/model.lua:357`：`if not result and type(result) == 'number'` —— `not result` 为真时 `result` 必是 `nil`/`false`，不可能是 number，条件永远为假。

---

## 6A. 数据层（ORM / DB）深入审查

以下结论均已回到源码逐行核对（`Tilua/model/model.lua` 实为 **1284 行 / 78 个方法**，我前文误记为 1183 行）。

### 6A.1 模型层几乎全部主功能处于"硬报错或静默失效"状态

| 功能 | 状态 | 依据 |
|---|---|---|
| **软删除** | **必然生成非法 SQL** | `soft_delete.lua:36` 产生 `{"exp", "`col` IS NULL"}`，而 `query.lua:126` 又拼上 key → ``WHERE `deleted_at` `deleted_at` IS NULL``（MySQL 1064）。任何 `soft_delete="col"` 的模型 select/save/delete/count 全部失败 |
| **`soft_delete = true`** | **完全无效** | `soft_delete.lua:5-10` 的 `apply_defaults` 把 `true` 归一成 `"deleted_at"`，但**全仓库从未调用它**（grep 只命中定义）。`is_enabled` 要求 string（第 13 行）→ CHANGELOG 文档的 `true` 写法是 no-op |
| **`where()` 链式调用** | **第二次必崩** | `model.lua:924` 写的是 `tablex.update(options.where, where)`，而 `options` 既非参数也非局部变量 → `attempt to index a nil value (global 'options')`。这直接扼杀 `Model:where(a):where(b)` 与实例复用 |
| **字符串 where** | 静默生成伪列 | `model.lua:918-922` 把字符串塞进 `{_string = where}`，但**没有任何驱动代码消费 `_string`**（全仓库 grep 零命中）→ ``WHERE `_string` = 'status = 1'``。同时第 912-917 行算了 `parse` 转义却**从未使用** |
| **`add()` 返回值** | **破坏文档契约** | `docs/SERVICE.md:23,39-43` 演示 `local id = svc:create(...)`。但 `model.lua:222-234` 只在 `type(result)=='number'` 时回填主键，而 `execute_sql` 对写操作返回的是 resty.mysql **结果表**（`mysql.lua:130-138`）→ 永远拿不到 insert id。`save()` 同理：永远返回真值表，`if Model:save(...)` 恒为 true |
| **`delete({where=...})`** | **静默 no-op** | `model.lua:338` 调 `self:_parseOptions()` **不带参数**，丢弃调用方的表；前面分支只处理标量/复合主键 → `options.where` 为 nil → 第 339-341 行 `return false` |
| **`chunk()`** | **第 2 页起丢失 WHERE（数据泄漏）** | `_parseOptions` 返回实例 options 后随即 `self.options = {}` 清空（`model.lua:444,473`），`chunk` 只恢复 `order` → 第 2 轮变成 `SELECT * FROM t LIMIT n,n` **无 WHERE**，遍历全表；且未强制 ORDER BY，翻页不确定（漏行/重复） |
| **`group/having/alias/strict/lock/distinct/auto/filter/validate/result/token/index/force`** | **13 个方法不存在** | `model.lua:123` 的 `self.methods` 对外宣传这 15 个链式方法，实际只定义了 `order`（130）和 `master`（1278）。`Model:group('x')` → nil call |
| **`setField` / `setInc` / `setDec`** | 必崩 | `model.lua:576-581` else 分支对未初始化的 `local data` 索引赋值 |
| **`select({table=...})` / `getDbFields`** | 必崩 | `model.lua:839` 把**标准库 `table`** 传给 `string.find`（应为局部变量 `tableName`）；第 836 行 `tableName` 被遮蔽未赋值 → `SHOW COLUMNS FROM `nil`` |
| **复合主键** | 不可用 | `model.lua:1054-1060` 对字符串 `self.fields._pk` 做 `[#x+1] = ...` → 索引字符串；`model.lua:329,391` 调 `options.remove(i)` 但该表无 `remove`（局部 `tablex` shim 也没有，见 `model.lua:19-70`） |
| **`select({index=...})`** | 必崩 | `model.lua:421-431` `local cols` 未初始化即 `cols[_key] = ...` |
| **`getDbError`** | nil call | `model.lua:813` 调 `self.db:getDbError()`，驱动只有 `getError`（`mysql.lua:315`） |
| **`getError`** | 永远返回 `''` | `model.lua:809` 返回 `self.error`，而 `properties()` 里初始化为 `''` 且**从未写入** → 模型层错误被彻底吞掉 |

### 6A.2 SQL 注入面（值有转义，标识符/片段没有）

- `Query:key` 在包含反引号或 `(` 时**原样返回**（`query.lua:42-43`），不匹配 `^[%w_]+$` 的也原样放行（51-52），随后被无转义地插入 WHERE / ORDER / field / insert / update（`query.lua:87-89,122-136,179,200,220-224`）。而 key 常直接来自请求数据（`Model:where(ngx.req.get_uri_args())`）。
- `Query:order` 接受裸字符串拼接（`query.lua:191-192`）、`Model:comment` 裸包进 `/*...*/`（`model.lua:962-965` / `query.lua:250`）、`%GROUP%`/`%HAVING%`/`%JOIN%` 同样裸拼（`query.lua:242-245`）。
- 表名经 `Query:table_name → Query:key` 原样透传（`query.lua:95-115`），`mysql.lua:269-276` 拼 `SHOW COLUMNS FROM \`..name..\`` 无反引号转义。
- 聚合函数把调用方字段裸插：`'COUNT(' .. field .. ') AS tilua_count'`（`model.lua:744-768`）。
- `Query:bind`（`query.lua:310-321`）替换**所有** `?`，包括字符串字面量里的（`WHERE note = 'why?'` 会被破坏），缺参静默替换成 `NULL`，多参静默忽略 → 参数个数不匹配退化为"语法合法但结果错误"的查询。
- 转义本身：默认转义器**剥掉 `ngx.quote_sql_str` 加的引号**再由 `Query:value` 重新包裹（`query.lua:24-30`），对 utf8 等价，但对 GBK/Big5 这类宽字节字符集存在 0xBF27 绕过面，而 charset 是可配置的。非 ngx 回退的 `lw_utils.addslashes` 内部**仍然依赖 ngx**（`util.lua:192-194` 用 `ngx.re.gsub`），且不转义反斜杠与 `\0\n\r\Z`。
- **无空 WHERE 保护**：`Query:where` 对空表返回 `""`（`query.lua:163-165`），而 `build_update` / `build_delete` 不检查 → `model:save(data)` 在无 where/无主键时执行**全表 UPDATE**；`soft.restore_null`（`soft_delete.lua:68-82`）在没有 pk 时同样会 `UPDATE t SET deleted_at=NULL` 打全表（`options.where` 是空表但为真值，`or` 兜底永不触发）。

### 6A.3 事务与连接池（生产事故级）

- **`startTrans()` 先 commit**：`model.lua:794-798` 第一句就是 `self:commit()`。嵌套开事务会**先把外层事务提交掉**，再开新事务；而 `Mysql:startTrans`（`mysql.lua:94-99`）在 `transTimes > 0` 时并不发 SQL → 内层提交是空操作，**原子性彻底失效**。
- **归还连接前不回滚**：`Mysql:close`（`mysql.lua:323-326`）→ `Connection:close`（`connection.lua:177-190`）直接 `set_keepalive`，**从不检查 `transTimes`、从不发 ROLLBACK**。一个被中途放弃的事务会把未提交状态和锁**留在池化 socket 上**，下一个复用该 socket 的请求会看到别人的未提交数据。
- **连接池名不含 user 和 charset**：`connection.lua:120` 的 `pool_name = host:port:db`。同一 host/db 下**以不同 MySQL 用户**连接的两个应用会共享同一个 resty pool name → 请求 B 可能拿到以用户 A 身份认证的 socket。这是权限越界级别的缺陷。
- `rollback()` 吞异常后 `return true`（`mysql.lua:84-92`）→ 回滚失败被报告为成功。`beginTransaction/commitTrans` 绕开 `execute_sql`，用裸 `error()` 抛字符串（66-82），丢失 `self.error` 与统一异常管线。
- 读写在事务内不正确：`Mysql:select` 只要 `rw_separate` 打开且非 `FOR UPDATE` 就走从库（`mysql.lua:172-185`），`startTrans` 内不钉住主库 → 事务内读到从库陈旧数据。且 `rw_separate == "1"` 在 `connection.lua:57` 被认可、在 `mysql.lua:178` 不认可，配置解析不一致。
- 查询出错后 socket 保持存活：`execute_sql` 只设 `self.error` 并返回，不清空/关闭 `self._linkID`（`mysql.lua:119-129`）→ 超时或中断的读之后若继续在同一 socket 上查询，会出现**响应错位/串数据**。`set_timeout(2000)` 是连接+读+写共用一个预算（`connection.lua:8,118`），无语句级超时、无死锁重试。
- `keepalive` 在 `set_keepalive` 失败时仍把引用置 nil（`connection.lua:166-171`）→ fd 泄漏。

### 6A.4 缓存与 schema 缓存

- 查询缓存**不可用**：默认指向不存在的 `Tilua.cache.driver.redis`（与 P0-2 同源），`model:select` 的缓存路径无保护地调 `self.ctx.cache.get/set`（`model.lua:403-410,435-437`）→ `Model:cache(...):select()` 直接抛错；schema 缓存路径则用 `pcall` **吞掉**同一失败（`model.lua:1025-1037`，`ok` 被丢弃）→ 缓存静默关闭。
- 缓存键不稳定/不一致：`get_hash` = `md5(json.encode(...))` 依赖 `pairs` 顺序（`util.lua:477-479`）；`select` 认 `cache.key` 且缓存行数组，`find` **忽略** `cache.key` 且缓存单行到另一个键（`model.lua:403-409` vs `521-528`），两者可互相读到形状不符的数据。
- **worker 级 schema 缓存永不失效**：`Mysql._fields_mem`（`mysql.lua:13,296`）与 `model._SCHEMA_MEM`（`model.lua:79,1009,1018`）是模块全局、无 TTL、无版本号，`flush()` 也无法让驱动层失效（`model.lua:1043 → db:getFields` 仍读 `_fields_mem`）→ **`ALTER TABLE` 后所有 worker 直到重启前都用旧列集**。键在 `config.database` 为 nil 时退化成 `":users"`，跨库冲突。
- **schema 表被就地污染**：`getDbFields` 把返回的 schema 表 `_type/_pk` 置 nil（`model.lua:848-851`），而 `_checkTableInfo` 把**共享的缓存表**存进 `self.fields`（`model.lua:1079-1084`）→ 一次 `field(true)` 调用后 `_type` 对所有后续请求消失，`_parseType` 静默停止类型转换。

### 6A.5 关联与水合

- `relation.lua:79-96`：父实例既无 `data` 也无 `options.where`（例如父对象来自 `select()`，而它已把 `self.options` 清空）时，`parent_val` 保持 nil 且**不加任何约束** → `Model:relation("posts")` 静默返回关联表**全表数据**，而不是报错。
- `relation.lua:129-151`：`eager` 对 `belongsTo` 的方向搞反了 —— 它查 `related WHERE fk IN (父 ids)` 并按 `cd[fk]` 归组，而 belongsTo 应该是 `related.pk IN (父的 fk 值)` 并按子表主键归组 → `Relation.with("author", rows)` 结果错误或为空。
- `Relation.query` 直接改写从 `ctx.model[name]` 拿到的**共享实例**（`relation.lua:70-100`）→ 两个指向同一模型的关联会累积条件，并撞上 6A.1 的 `where` 二次调用崩溃。
- `Result.pluck` 带 `key_field` 时写 `out[data[key_field]]`（`result.lua:79`）→ 键列含 NULL 时 "table index is nil"。
- `model:exists()` 在计数为 nil 时返回 nil 而非 false（`model.lua:1163-1166`）。

### 6A.6 并发

单个请求内的 driver 完全没有重入保护：`Connection.link_id[linkNum]`（`connection.lua:102-105`）与 `Mysql._linkID`（`mysql.lua:50`）每个角色只持有一个 cosocket，而 `select/execute` 会改写共享 driver 状态（`self.model`、`queryStr`、`modelSql`、`lastInsID`、`numRows`，见 `mysql.lua:141-162,172-174`）。因此用 `ngx.thread.spawn` 并发跑多个 handler 并共享 `ngx.ctx` 时，它们会在**同一条 MySQL 连接上交错**（协议错位、"socket busy"），且 `getLastSql`/`getLastInsID` 可能报出别的模型的语句（`modelSql` 只在 `execute` 里写、`query` 里不写，`mysql.lua:151-157,304-309`）。

### 6A.7 驱动 shim 与死代码

- 同一个驱动有**四个入口**（`Tilua.db` / `Tilua.db.driver` / `Tilua.db.driver.mysql` / `Tilua.database.driver.mysql`）、三套调用约定。`Tilua/db/driver.lua:29-32` 的 `connect/query/execute/close` 是**空 no-op** → 任何走这条遗留基类的调用静默返回 nil。两套"驱动"形态并存（canonical `setmetatable({}, Mysql)` vs 遗留 `class.define()`），且 `escapeString` 返回**不带引号**的值而 `parseValue` 带引号（`db/driver.lua:20-21` vs `query.lua:55-75`），契约不一致。
- 深度计数的事务封装 `Tilua/database/transaction.lua` **从未被 model 使用**（只有 `mysql.lua:24` 的 `Mysql.tx = Transaction.new(self)` 挂着没人调）。`Transaction:run` 丢弃 commit 结果、`rollback` 恒返回 true。
- 其他死代码：`model:db_instance` 的 close 分支（`model.lua:1101-1107`，不可达）、`soft.apply_defaults`/`soft.soft_delete`/`soft.restore`、`Mysql:getResult`、只写不读的 `queryTimes`/`executeTimes`/`numRows`、`build_select` 里恒为空的 `%UNION%`/`%FORCE%`。
- `model.lua:146-149` 点号模型名解析：`helpers.split(name, '.')` 默认是**模式**模式（`helpers.lua:11-27`），`.` 匹配任意字节 → `"mydb.users"` 解析出空库名、空表名。
- `model.lua:168-190`：`self._field_set` 从**查询投影** `self.options.field` 记忆化，只有 `flush()` 会清 → `Model:field('id,name'):select()` 之后，该实例上所有 `add/save` 都会静默丢弃其余列。
- `tests/test_orm_helpers.lua:39` 调用的 `d:parseSql(...)` **在整棵树里都不存在**（`db/driver.lua` 只有 `parseKey/parseValue/escapeString/parseField/parseTable/parseWhere/parseOrder/parseLimit/buildSelectSql/parseSet`）→ 这个唯一的 ORM 测试在最后那行 `print` 之前就已经报错了。

### 6A.8 缺失的生产能力

无迁移/schema 工具（无 DDL helper、无 SQL 文件、无 CLI 任务）；分页只有裸 `LIMIT a,b`（无总数、无游标分页、软删除模型上 `count()` 不可用）；无重连/重试/退避/熔断/ping 健康校验；只有一个 2000ms 的 connect+read+write 超时预算，无语句超时、无锁等待超时、无死锁重试；**完全没有 SQL 日志**（驱动里仅 connect 失败/调试/查询错误三处日志，无慢查询、无耗时、无连接池指标）；无真正的预编译/参数绑定（全靠转义后字符串拼接）；`insertAll` 每条一次 `INSERT ... UNION ALL ...` 且不分块、无 upsert（只有语义危险的 `REPLACE`）；`ctx.model.X` 恒用默认连接（`manager.instance` 的 `connection` 参数在 `__index` 路径上不可达）。

---

## 6B. HTTP 路由 / 分发 / 中间件深入审查

（`Tilua/http/router.lua` 实为 **680 行**，我前文误记为 625 行。）

### 6B.1 响应从未被发出 —— 最严重的一条

`response:send()`（`http/response.lua:340-343`）是唯一会调 `ngx.print` 的地方（`send = ngx.print`，第 5 行），而**全仓库 grep `:send()` 只命中它自己的定义**。同时：

```lua
-- Tilua/core/lifecycle.lua:165-171
function M.content_by_lua(app)
    local ctx = ngx.ctx.ctx
    if not ctx then ctx = app:set_by_lua() end
    return ctx:run()          -- ← 返回值被 nginx 丢弃，且没有任何代码 print 它
end
```

`channel.http_handle` 把 dispatcher 的结果 `return` 回 `App:run()`，`content_by_lua` 再 `return` 给 nginx —— 但 nginx 的 `content_by_lua` **不会**自动输出 Lua 函数的返回值，必须显式 `ngx.print/say`。HTTP 路径上（`channel.lua` / `dispatcher.lua` / `lifecycle.lua`）**没有任何一处 `ngx.say` / `ngx.print`**（唯二的 `ngx.say` 在 websocket stub 的 `channel.lua:149` 和调试用的 `util.lua:244`）。

后果：`response.body` 被正确填充、状态码被正确设置，**但响应体永远不会到达客户端**，用户拿到空白页。只有应用代码自己显式调 `ctx.response:send()` 才能出内容 —— 而 README、`examples/health/routes.lua`、`docs/SERVICE.md` 的所有示例都是 `return {...}` / `return "text"` 形式，**没有一个调 `send()`**。

### 6B.2 `App:get_request` / `App:get_response` 从未被自动调用

`app.lua:54-62` 定义了 `get_request()`（`Tilua.http.request.capture(self)`）和 `get_response()`（构造 response），但**没有任何框架代码调用它们**。而：

- `core/channel.lua:74` 读 `app.request.path_info`
- `dispatcher.lua:65` 读 `self.ctx.response`
- `dispatcher.lua:106` 读 `response.body`

即 `app.request` / `app.response` 必须由应用在 `on_app_init` 之类的地方自己初始化，否则 `/health` 短路分支和 dispatcher 都会 nil 索引崩溃。这是"框架没接线"的又一例。

### 6B.3 `manager.parse` 把字符串表原样返回 → 默认中间件组会崩

```lua
-- Tilua/middleware/init.lua:87-93
function manager.parse(val)
    if type(val) == "table" then
        return val          -- ← 表原样返回，元素 {"session"} 不会被规范成 {{"session"}}
    end
```

传入 `{"session", "json"}` 时原样返回，随后 `manager.instance` 执行 `midware[1]` → 对字符串取下标得 `nil` → `get_shortname(nil)` → 第 27 行 `name:gsub(...)` **"attempt to index a nil value"**。

而 `config/default.lua:24-31` 的默认分组正是 `web = {'body_parser','session','json','html_cache'}` 这种字符串表形式。`tests/test_middleware.lua` 只断言 `type(group) == "table"`，所以这个 bug 被测试放过了。

### 6B.4 CSRF 校验可自我满足

```lua
-- Tilua/middleware/csrf_token.lua:109-111
if not token and request.cookie and self.config.enable_cookie then
    token = request.cookie[self.config.cookie_name]   -- ← 拿应用自己发的 cookie 当"用户提供的 token"
end
-- 第 126 行
if not expected or not provided or provided ~= expected then return false end
```

而 cookie 在每个请求都会被重新下发（第 157-160 行 `issue_cookie`）。于是"cookie 里的 token"与"session 里的 token"天然相等 → 任何携带 cookie 的跨站 POST 都能通过校验。默认 `SameSite=Lax` 是唯一缓解；一旦按 CHANGELOG 0.2.5 描述把 `cookie_samesite` 设为 `None`（SSO 场景常见），**CSRF 保护完全失效**。

### 6B.5 `request:get_header(name)` 返回整个 header 表

```lua
-- Tilua/http/request.lua:320-322
local getter = rawget(request, "get_" .. key)
if util.callable(getter) then
    return getter(t)      -- ← 只传 self，丢掉调用方所有参数
```

`request.get_header(name)`（第 173 行）签名是**不带 self** 的 `function request.get_header(name)`，因此 `request:get_header("X-Token")` 实际执行 `get_header(t)` → `name` = request 对象（真值）→ 直接返回 `headers` **整张表**，而非 `headers["X-Token"]`。

更系统性的问题是：`__index` 对**任何** `get_*` / `set_*` 函数都只传 `self`（仅第 310-313 行的白名单例外），所以没被列入白名单的实例方法都会静默丢弃参数。

### 6B.6 分发层的返回类型推断存在多处误判

- `dispatcher.lua:112-115`：`#res1 == 2 and type(res1[1])=="string"` 就把表当 `{"view", context}` 渲染视图 → 返回 `{"ok", {...}}` 这类 JSON 数组会被当成模板名去渲染。同段 `elseif res1.new then`（第 114 行）会**静默丢弃**任何含 `new` 键的表 → 空响应体。
- `dispatcher.lua:123-132`：handler 返回纯字符串被当作**视图名**（`response:render(res1, {})`），与 README:99-101 声称的"返回字符串即输出文本"矛盾 → 模板不存在则报错。
- `dispatcher.lua:141-149` `get_bind_args`：`if not string.match(v, "%d+")` 用来判断"参数名不含数字"，但 `%d+` 是**任意位置匹配** → `/user/{id2}` 这类命名参数会被整段跳过，导致后续位置参数**全体错位**。
- `dispatcher.lua:184` + `216-218`：`create_responser` 在链条构造时就捕获了 `self.handler`，而 `to_handler()` 替换的是这个没人再读的字段 → 只注册了中间件、没注册 handler 的路由恒返回 404。`middleware/mvc_router.lua:53-69` 在失败路径下留下 `self.action = nil` → `attempt to call a nil value`（500 而不是 404）。
- `dispatcher.lua:48-50`：`xpcall(f, h, ...)` 的第三个 vararg 参数在 LuaJIT / Lua 5.1 中**不被支持**（`xpcall` 只接受 2 个参数），这里的 `...` 会被忽略。

### 6B.7 路由注册路径不可达 / 死代码

```lua
-- Tilua/http/router.lua:668-680
__call = function(_, ...)
    local rule = select(1, ...)
    if lw_util.is_array(rule) then          -- ← 对字符串键的表返回 false
        lw_util.foreach(rule, function(responser, route_rule) ... end)
```

`helpers.is_array`（`helpers.lua:64-78`）要求所有键都是正整数 —— 而 `route{ ["get /x"] = handler }` 这种表是**字符串键**，恒返回 false，整块注册逻辑不可达。同理 `to_router` 的 table 分支（`router.lua:306-317`）也依赖它。

其余死代码：`accepts_method`、`parse_path_params`、`add_route_rule` / `clear_route_rule`、`get_routes`（内部调用未定义的 `get_init_route_rule`）、`html_cache:exists`、`response:__newindex_body`。

### 6B.8 路由匹配的其他缺陷

- `router.lua:574`：前缀匹配用 `string_find(path, p, 1, true) == 1`，**没有段边界判断** → `* /api` 会匹配 `/apifoo`。
- 正则路由之间按**插入顺序**取胜（`select_best_match` 第 608-623 行返回第一个通过的），没有优先级或特异性排序。
- `MATCH_CACHE_MAX = 2048` 满了就 `clear_match_caches()` **整体清空**（`router.lua:655-657`），攻击者用随机唯一路径就能持续打满缓存、让缓存彻底失效（缓存穿透放大）。
- `add_route_rule` 每加一条规则就 `rebuild_index` 全量重建（`router.lua:165-171`）→ 注册 N 条路由是 O(N²logN)。

### 6B.9 Session 固定攻击

- `use_strict_mode` 是 no-op：`validate_id` 只做长度/字符集检查（`session/memory.lua:74-76`、`session/session_redis_hanler.lua:83-85`），`reset_id` 从不真正重新生成（`session.lua:161-170`）。
- 客户端一旦提供 id，服务端就**停止下发 cookie**（`session.lua:262-264`）→ 攻击者预设的 id 会被沿用。
- `cookie_secure = false` 是默认值（`middleware/session.lua:81`）。
- `middleware/session.lua:51-60`：`next_fn` 没有包 `pcall` → handler 抛错时 `sess:close()` 被跳过，session 写入/关闭丢失。

### 6B.10 body_parser

- 模块级 `_config` / `_sock`（第 33-34、265 行）在**所有 app 和请求间共享**。
- 表单 / JSON body **无大小限制**（第 107-119 行）；非文件 part 无限制（163-174）；part 数量无上限（`config.multipart` 的 `fields` / `field_size` / `file_value_size_in_memory` 是死配置）。
- `get_limit_size` 对 `"1.5mb"` / `"gb"` 返回 nil（第 95-105 行）→ 第 154 行 `part.size > nil` 抛错。
- `io_open` 返回值未检查（第 143 行）；`os.execute("mkdir -p " .. p)` **未加引号**（第 27 行）。
- 前面已提的 `strip(x, '"')` 参数被忽略（4.4 节）。

### 6B.11 html_cache 中间件

- `enable` 配置项被忽略（默认 `false` 于第 21 行，但 `handle` 第 116-136 行从不检查）→ 关不掉。
- 内存模式**无 TTL、无容量上限**（第 109-110 行）。
- `type='file'` 时键是常量目录（`path.join(..., '', nil)`，第 85-89 行），且 `get`/`set` 没有 file 分支 → 完全失效。
- 缓存**不区分请求方法**（GET/POST 共用一个键）。
- 命中时只恢复 `body`（第 124 行），丢失 status 与 Content-Type。
- 无 `Vary` 处理 → 已登录用户的 HTML（可能内含 CSRF token）会被缓存并下发给其他用户。

### 6B.12 Cookie

- `cookie.lua:27` 解码时把 `+` 转成空格，而 encoding 端从不产生 `+` → 解码语义不一致。
- `raw = true` 时跳过全部编码（第 82-84 行），且 name / path / domain 全程未做合法性校验即插值。
- `response:set_cookie` 的位置参数 `expires` 被映射成 **Max-Age 相对秒数**（`response.lua:230-236` + `cookie.lua:95-120`），与"过期时间戳"的直觉契约不符。

### 6B.13 HTTP 层测试现状

- `tests/test_router.lua:22-24` 断言 `find_matched_route` 返回 boolean，但它实际返回**数组**（`router.lua:524-593`）→ 这个测试**从第一行断言就是错的**，早就失效。
- `test_router_index.lua` 的 `ngx.re` stub 无法真正演练正则路由。
- `test_middleware.lua` 没有 ngx stub（需要 `resty`）且对 group 内容零断言，正好掩盖了 6B.3。
- `test_cookie.lua` 从不校验它解析的带引号 cookie，编码检查是同义反复。
- `test_request_response_api.lua:42` 用桩替换了真实类加载器，缺少 `set_*`/`get_*` 桥接 → `body`/`status` 的行为与生产不一致。
- `test_session.lua` 把"允许固定 session id"的 `validate_id` 行为**当作预期写进了断言**。

只有 `test_cookie.lua` 和 `test_request_response_api.lua` 能在无 OpenResty 下自足运行。`dispatcher.lua`、CSRF、body_parser、html_cache、session 中间件、路由优先级/校验 —— **零测试覆盖**。

---

## 7. 测试与可运行性现状

- 本机**没有 lua / luajit / openresty / resty**，也没有 CI 配置，所以"测试通过"这件事目前无法被任何人复现验证。
- 无 git 提交历史可读（`git` 在沙箱内不可执行），无法评估演进过程。

---

## 8. 优先级建议

**P0 — 让框架能跑起来（否则其余讨论无意义）**

1. **补上响应输出**：在 `lifecycle.content_by_lua` 或 `channel.http_handle` 拿到 dispatcher 结果后调用 `response:send()`。当前**没有任何代码输出响应体**（6B.1），这是"页面空白"的根因，比其他所有问题都优先。
2. **接线 request/response**：在 `set_by_lua` 里自动调 `app:get_request()` / `app:get_response()`，否则 `/health` 与 dispatcher 会 nil 索引崩溃（6B.2）。
3. `middleware/json_response.lua:1` 改为 `Tilua.middleware.base`，顺手修 `chartset/uft-8` 拼写。
4. `middleware/init.lua:88-90` 让 `manager.parse` 把字符串数组规范成 `{{name, cfg}, ...}`；否则 `config/default.lua:24-31` 的默认中间件组一用即崩（6B.3）。
5. 删除 `utils/util.lua:59` 未使用的 `require "random"`；把 `lfs` / `pl.tablex` / `resty.jit-uuid` 改为可选降级（或写进 rockspec 明确声明）。
6. 二选一收口日志：把 `Tilua/logging/writer.lua` 接进 `Tilua/log.lua`（推荐），或补齐 `Tilua/log/file.lua`。同时补 `warn` / `notice` 方法。
7. 提供 `Tilua/cache/driver/redis.lua`（或把 `data_cache_handler` 默认改为 `shdict`/`memory` 并实现对应驱动）。
8. **修 ORM 的 where 链**：`model.lua:924` 的 `options.where` → `self.options.where`（不修则 `Model:where(a):where(b)` 必崩）；顺带修软删除的 `exp` 拼装（`query.lua:126` / `soft_delete.lua:33,36`）、`delete` 丢参数（`model.lua:338`）、`chunk` 丢 WHERE（数据泄漏）。
9. **修事务与连接池**：`model.lua:795` 的 `startTrans` 先 commit；`Connection:close` 归还前不回滚；`connection.lua:120` 的 pool name 必须包含 user 与 charset（否则跨用户串连接）。
10. 修 `service/base.lua` 的事务静默降级、`dispatcher.lua:184`+`216-218` 的 `to_handler` 死链、`dispatcher.lua:141-149` 的 `get_bind_args` 数字参数丢失。

**P1 — 安全**

11. **CSRF**：去掉 `csrf_token.lua:109-111` 的 cookie 自我满足回退（或引入独立的 double-submit 校验），改用常量时间比较。
12. `client_ip` 改为可信跳数右起解析（`trust_proxy` 建议接受整数跳数，而非布尔）。
13. 路由 best-match 缓存键加入运行时校验维度，或在命中缓存后**重新执行 `route.validate`**。
14. `Query:key` / `Query:order` / `model:comment` / 表名 / 聚合字段必须做标识符白名单或反引号转义（当前 identifier 全程无转义）；`build_update`/`build_delete` 补空 WHERE 保护（当前可全表 UPDATE）。
15. Session：实现真正的 `validate_id` 严格模式 + id 再生成，`cookie_secure` 默认 true。
16. `is_production` 默认值反转为 `true`（fail-safe）；`details` 无论环境都过一遍 `sanitize`。
17. Session / CSRF 的随机数降级路径改为硬失败，不要退回 `math.random`。
18. HTML 缓存补 `enable` 开关、TTL/容量上限、`Vary` 与 Host/用户维度，或明确声明只缓存匿名 GET 页。
19. `body_parser`：去掉模块级 `_config`/`_sock`，补 body 大小与 part 数量上限，修 `get_limit_size` 与 `os.execute` 引号。

**P2 — 工程化**

20. 引入测试 runner（busted 或自研 + 退出码），补 CI；重写 `test_router.lua`（当前断言与实现返回类型不符，已失效）、去掉 `test_orm_helpers.lua` 与 `test_request_response_api.lua` 里对被测模块的 `package.preload` 替换。
21. 一个共享的 `ngx` mock（`tests/support/ngx_stub.lua`），让纯 Lua 环境能跑核心逻辑测试。
22. 拆分 `model/model.lua`（1284 行）、`router.lua`（680 行）、`utils/util.lua`（454 行）。
23. 修 `utils/class.lua`：`merge(child, parent)` 会覆盖子类自身的 `define`，导致**二级继承丢失中间类方法**（所有中间件子类化都会中招）；建议改为真正的原型链。
24. 补齐 `model.lua:123` 对外宣传但不存在的方法，或删掉这份清单。
25. 对齐 README / CHANGELOG / VERSION（README 的 `derive()` / `_init` / `super` 全部不存在），CHANGELOG 按时间正序。
26. 把 OpenAPI / CLI / WebSocket 明确标注为 stub，或补齐实现。

---

## 9. 总体评价

**架构意图是清晰的**（MVC + 中间件管线 + 通道抽象 + 统一异常 + ORM 分层），CHANGELOG 显示作者有明确的阶段化重构计划，异常脱敏、路由三级索引、ORM 特性集这些地方看得出思考。

**但当前状态是"重构进行到一半的中间态"，且缺失的接线已经到了功能不可用的程度**：

1. 响应对象被正确构造，`response:send()` 却从未被调用 —— **HTTP 响应体永远不会到达客户端**（6B.1）。
2. 新旧两套实现并存（log / middleware / database / http），新路径没接完、旧路径已半死，关键断点全部被 `pcall(require)` 静默吞掉 —— 表面上"加载成功"，实际上日志不写、缓存不可用。
3. 数据层的主功能（软删除、链式 where、insert id、分页、事务）多数处于**必崩或静默失效**状态，且事务与连接池存在原子性/隔离性缺陷。
4. 安全上有完整可利用的链路：伪造 IP → 绕过校验 → 复用别人的路由决策与连接池 socket。

再叠加 `random` / `lfs` 这类未声明硬依赖、零测试基础设施、零 CI、以及一份跑不通的 README 入门示例，**距离 README 所称的 "production-ready defaults" 和 "Phase 1–3 complete" 有明显距离**。

**不过好消息是：这些都不是架构性难题**。第 8 节的 P0 清单（补响应输出、接线 request/response、4 处 require/parse 修正、2 处 ORM 状态 bug、事务与连接池）大约是一到两周的可控工作量。做完 P0，这个项目就能跑通第一个真实请求，后续按 P1/P2 逐步收敛即可。
