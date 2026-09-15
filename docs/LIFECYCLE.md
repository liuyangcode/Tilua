# 生命周期重新设计

> 基于**实测**的 OpenResty 语义，不是假设。所有结论都在
> `openresty/openresty:1.21.4.1-buster`（ngx_lua 0.10.21）上跑过。

---

## 1. 实测数据（探针结果）

| 探针 | 结果 | 结论 |
|---|---|---|
| `ngx.req.is_internal()` 外部请求 | `false` | 可用作内部请求判据 |
| `ngx.req.is_internal()` 子请求 | `true` | **无法**区分内部重定向与子请求，需另找判据 |
| 内部重定向（`ngx.exec`）后 `ngx.ctx` | **`nil`（被整体替换）** | `ngx.ctx` **不能**作为跨内部重定向的上下文载体 |
| 子请求的 `ngx.ctx` | 全新的表，**不继承**父请求值 | 旧假设"子请求共享父 ctx"是**错的** |
| 子请求返回后父请求的 `ngx.ctx` | 仍是 `parent-value`（父请求自有表未被污染） | 父请求上下文安全 |
| `rewrite_by_lua` → `access_by_lua` → `content` 的 `ngx.ctx` | 值一路存活 | 同一请求内正常存活 |
| `ngx.worker.exiting()` | 可用 | 可做优雅关闭 |
| `ngx.on_abort` / `ngx.req.start_time()` | 可用 | 可做中断处理 / 请求计时 |

### 由此推翻的两个设计假设

1. ~~把请求上下文只存在 `ngx.ctx` 就能扛住内部重定向~~ —— **错**。重定向后
   `ngx.ctx` 换表，框架会**重建一个新的容器上下文**，同一请求出现两个作用域、
   两次 flush。
2. ~~子请求共享父请求的 `ngx.ctx`~~ —— **错**。子请求拿到独立空表，
   因此子请求里访问不到父请求的上下文。

---

## 2. 阶段归属（新）

| 阶段 | 职责 | 为什么放这里 |
|---|---|---|
| `init_by_lua` | 载入配置、注册路由规则、校验配置 | master 进程执行，产物被 worker 继承（COW）；**坏配置在启动/重载时 fail fast**，而不是在请求期炸 |
| `init_worker_by_lua` | 建 view engine、载入中间件配置、boot 插件、预热 | 需要文件系统与逐 worker 状态，master 里没有 `ngx.worker.pid()` |
| `rewrite_by_lua` | **创建请求作用域容器上下文**；跑 rewrite 阶段中间件 | 请求早期、API 完整，且早于 access |
| `access_by_lua` | 跑 access 阶段中间件（鉴权/限流）；拒绝即短路 | 拒绝的请求不进入 content，省掉业务开销 |
| `content_by_lua` | 跑 content 阶段中间件 + 路由分发 + **输出响应** | 真正产出响应体 |
| `log_by_lua` | 释放请求作用域、关闭连接池、写访问日志 | 请求尾声，无论成败都会到 |

**`set_by_lua` 已彻底移除**（该阶段为设置 nginx 变量而设计、API 受限），
nginx 配置需改为 `rewrite_by_lua_block` + `access_by_lua_block` + `content_by_lua_block`。

---

## 3. 上下文载体：`ngx.ctx` + URI 指纹

```lua
-- 外部请求 / 新请求
ngx.ctx.__tilua = { ctx = container_ctx, uri = ngx.var.uri, flushed = false }

-- 取上下文时
local slot = ngx.ctx.__tilua
if not slot or slot.uri ~= ngx.var.uri then
    -- 内部重定向：ngx.ctx 被替换，或 URI 已变 → 重建作用域
    slot = new_slot()
end
```

**为什么用 `ngx.ctx` 而不是 `ngx.var`**：
`ngx.ctx` 是唯一既按请求隔离、又在同请求各阶段存活、且不污染 nginx 变量空间的载体。
代价是它**不扛内部重定向**，所以用 URI 指纹检测并重建。

**子请求判据**：`ngx.req.is_internal()` 对外部请求为 `false`，对内部重定向与子请求
都为 `true`，**单独不够**。实际用的是：

- 子请求 → `ngx.ctx` 里**没有** slot（独立空表）→ 自然会新建自己的上下文，
  且 `_parent` 指向 worker 类（拿得到单例），但**不参与父请求的 flush**。
- 内部重定向 → slot 存在但 `uri` 不匹配 → 重建。

两者都不会误 flush 父作用域：flush 只处理「本请求 slot 里的 scoped 集合」。

---

## 4. 责任边界：master 与 worker 分离

`App:boot()` 原先把两件事混在一起，导致 master 里就需要 `ngx.worker.pid()` 和
文件系统。新设计拆开：

```
App:load_config()                  # 纯配置，无副作用
App:register_routes()              # 路由规则 → 路由索引
        ↓  (master, init_by_lua)

App:boot_worker()                  # view engine / middleware / plugins / 预热
        ↓  (worker, init_worker_by_lua)
```

配置校验放在 master：`config` 缺失必填项、`dispatch` 类不可加载、路由规则语法错误，
都应在 `init_by_lua` 阶段直接报错让 `nginx -t` / reload 失败，而不是等到第一个请求。

---

## 5. 中间件声明式分阶段

```lua
-- config
middleware_phases = {
    rewrite = { "html_cache" },                    -- 尽早短路
    access  = { "auth", "rate_limit" },            -- 鉴权，拒绝即止
    content = { "body_parser", "session", "json", "mvc" },  -- 默认
}
middleware_group = { web = "...", api = "..." }    -- 仍可用，落到 content
```

规则：

- **未声明阶段的中间件默认落 `content`**，因此现有配置行为不变。
- 路由级中间件（`route.get(path, handler, {"auth"})`）**仍全部跑在 content**，
  因为它们依赖路由匹配结果；要提前跑必须写进 `middleware_phases`。
- 同一中间件**不应跨阶段重复声明**（它会被跑两次）。

`access` 阶段短路语义：中间件返回非 nil 结果即视为最终响应 —— 渲染并
`ngx.exit(status)`，不再进入 content。

---

## 6. 响应输出（新增）

`content_by_lua` 拿到 dispatcher 结果后显式输出：

```
prepare_response(...)
  → response:send()
       1. ngx.status = status（若 > 0）
       2. 逐条 add_header（Content-Length / Content-Type 归一）
       3. 204/304 → 不发 body
       4. ngx.print(body)
       5. ngx.exit(status)
```

注意：OpenResty **不会**自动输出 `content_by_lua` 的返回值。

---

## 7. 清理时机

```
log_by_lua
  └─ 仅在「本请求 slot 存在且未 flush」时
       ├─ ctx:flush()           释放 scoped（close() + defer LIFO）
       └─ 运行 on_app_handled 回调
```

- 内部重定向重建的上下文：旧上下文在重建时**立即** flush，避免泄漏。
- 子请求：自建自 flush，不影响父请求。
- `ngx.worker.exiting()` 为真时不再做昂贵清理（worker 正在退出）。

---

## 8. 迁移影响

| 项目 | 变化 |
|---|---|
| `lifecycle.set_by_lua` | **删除** |
| `app.set_by_lua` / `is_setted_by_lua` | **删除** |
| nginx 配置 | 必须加 `rewrite_by_lua_block` / `access_by_lua_block` |
| `on_app_init` 钩子 | 由 `rewrite` 阶段调用（语义不变） |
| 路由级中间件 | 行为不变（仍 content） |
| 全局中间件配置 | 可选声明阶段；不写就是 content |

新的 nginx 配置模板见 `tests/e2e/nginx.conf`。

---

## 9. 实施中发现的框架缺陷（已修）

端到端测试（真实 nginx）暴露了若干**与生命周期无关但阻塞运行**的既有缺陷，均已修复：

1. **`router.parse_rule` 的 matcher 默认值是 `*`（前缀）** —— 这让**每一条路由都变成前缀匹配**：
   `/nope` 命中 `/` 规则并被当作静态文件处理，而 `/user/{name}` **从未编译成正则**（参数路由
   完全失效）。改为**默认精确匹配**；`* /api` 需显式书写。参数路由现正确编译为
   `^/user/([^/]+)$`。
2. **`dispatcher.create_responser` 把 handler 存在 `self.handler`** —— dispatcher 是
   **worker 单例**，于是上一个请求的 handler 泄漏到下一个请求（每个请求都在重跑第一个路由的
   handler）。改为**纯局部变量**；`to_handler()` 也改为存在**请求上下文**上。
3. **`lifecycle.ensure_dir` 误判 `os.execute` 返回值** —— `ret ~= 0 and ret ~= true` 会把
   成功的 `mkdir` 当失败，导致 worker 启动时崩溃。改为回查文件系统判定。
4. **`app:load_config_and_routes` 在 `set_app_name` 之前 require 路由模块** —— 路由文件通常在
   **require 期**就调用 `route.get(...)`，此时 app 名未建立，规则落到了错误的键下。现在先解析
   router 单例（触发 `set_app_name`）再加载路由。
5. **请求上下文不共享 worker 单例** —— 容器新增 `_parent` 链解析：singleton 缓存在**拥有该绑定
   的容器**上，scoped 缓存在**解析它的容器**上。

---

## 10. 端到端验证现状

`tests/e2e/` 提供真实 nginx 下的端到端测试（`docker run ... sh tests/e2e/run.sh`）。
**当前全部通过**：

| 用例 | 结果 |
|---|---|
| `/greeter` JSON 路由 | 200 `{"marker":"GREETER",...}` |
| `/text` 裸字符串返回 | 200 `TEXT-MARKER`（作为文本，不再是模板名） |
| `/text-literal` `response("...")` | 200 `TEXT-MARKER` |
| `/about` 回调式注册 | 200 `about` |
| `/user/{name}` 路径参数 | 200 `hello ada` |
| `/admin` 无 token | **403** `admin token required`（access 阶段拒绝） |
| `/admin` 带正确 token | 200 `admin area`（access 阶段放行） |
| `/healthz` | 404（路由未匹配，非 nginx 默认页） |
| `/nope` | 404 `Not Found` |
| `/boom` 抛异常 | 500 统一 JSON 错误体（含 `request_id`） |
| 连续多请求隔离 | ✅ 各路由返回各自响应，无串扰 |

**跨请求响应泄漏已修复。** 根因是 `dispatcher` 是容器**单例**，而
`dispatch:_construct(app)` 把它第一次解析时的 receiver（worker boot 发生在**类**上）
缓存为 `self.ctx`；于是每个请求的 `self.ctx:make("response")` 都在**类容器**上解析，
把本应请求级的 `response` 变成了跨请求共享的单例——请求 N 看到请求 N-1 的响应体。

修复方式：dispatcher 不再缓存 receiver，改为经 `dispatch:ctx()` 从
`ngx.ctx` 的请求槽位读取**当前请求上下文**。

### 同批修复的其他跨请求 / 接线缺陷

1. **`create_responser` 把 handler 存在 worker 单例上**（`self.handler`）→ 上一请求的
   handler 泄漏到下一请求。改为纯局部变量。
2. **`response._construct(ctx)` 只接受上下文** → 文档推荐的 `return response("text")`
   把字符串当成了 `ctx`，结果返回**空 200**。现在接受上下文／体值两种形式。
3. **裸字符串返回被当作视图名** → 与文档契约不符；现在为纯文本，`return "view", {}`
   才是显式渲染视图。
4. **`get_bind_args` 按下标并跳过含数字的名字** → `/user/{name}` 传 `nil`。改为按名绑定。
5. **`request:get_header(name)` 不可用** —— 类系统的 `__index` 包装器对 `get_*` 只传
   receiver、丢弃参数，因此 `name` 收到的是请求表本身。已改为读实时
   `ngx.req.get_headers()` 并在文档中写明正确用法。
6. **header 快照过早** —— `capture()` 在 rewrite 阶段取快照时，OpenResty **尚未**暴露
   自定义头（实测：客户端发了 `X-Admin-Token`、`ngx.var.http_x_admin_token` 有值，
   而快照只有 `connection,host`）。改为实时读取。
7. **阶段中间件名未解析到应用命名空间** → `middleware_phases.access = {"admin_guard"}`
   解析为 nil，整条 access 链被静默跳过。现在按
   `alias → 全限定名 → <App>.middleware.<name> → 原名` 顺序解析。
8. **`phase_list` 返回裸字符串** 而 `instance()` 期望 `{name, config}` → 加规范化。
9. **路由级阶段中间件需要路由匹配** —— access 阶段早于路由，所以 rewrite 阶段先匹配一次
   并把结果存入请求上下文；access 仅对**该路由**声明的中间件生效（否则声明在 `/admin`
   上的守卫会把整个应用都拦下）。
10. **`pcall` 吞掉 `route.match` 的第二个返回值**（captures）→ 规则恒为 nil。

### 已知限制

**内部重定向（`ngx.exec`）前的旧作用域不会被即时释放**：OpenResty 在内部重定向时
整体替换 `ngx.ctx`，旧上下文从中已不可达。`slot.uri ~= uri` 这条判据只在槽位**存活**时
才触发，而 `ngx.exec` 之后并非如此。旧作用域依赖请求结束后的正常 GC 回收。
要即时释放需要保留一份模块级的旧上下文引用，而那本身又是跨请求泄漏风险，故列为后续项。
（`tests/test_lifecycle_container.lua` 中用注释标注了这一点。）

> `tests/support/lua_stub.lua` 下 **242 项单元断言**全部通过（容器 55 + Application 82 +
> 生命周期 49 + Trie 路由 56）。端到端测试是必需的补充：上面第 1、4、6、9 条都**只能**
> 在真实 nginx 下暴露。



