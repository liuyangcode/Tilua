# Tilua 项目重新分析报告（v0.9.3）

> 分析对象：`D:\Tilua\Tilua`
> 代码规模：**91 个 Lua 文件 / 14,584 行**（`VERSION` = `0.9.3`）
> 范围：**不含 ORM 层**（`Tilua/model*`、`Tilua/database*`、`Tilua/db*` 仅作为"已知不覆盖"列出）
> 分析方式：**全部结论均在真实运行时验证**。单元套件 14/14 通过，真机 nginx e2e 19/19 通过。
> 本文取代 `docs/ANALYSIS.md`（那份是 v0.7.0 的静态阅读报告，当时环境里没有 runtime，结论多为推断）。

---

## 0. TL;DR

| 维度 | v0.7.0（旧报告） | v0.9.3（本次实测） |
|---|---|---|
| 能否跑通一次完整 HTTP 请求 | **不能** | **能**（真机 nginx，19/19 用例） |
| 架构 | 概念好、接线断 | 容器 + Trie + 分阶段生命周期，自洽 |
| 响应泄漏 | 有（dispatcher 缓存 `self.ctx`） | 已修，且**同类问题在中间件层被重新发现并修复** |
| 测试 | 无 runner、ORM 测试自欺 | 14 套单元 + 1 套真机 e2e，含回归测试 |
| 主要风险 | 大面积不可用 | 集中在**少数设计取舍与文档/接线漂移** |

**核心判断：框架已经可用。** 本轮发现并修复了 6 个真实缺陷，其中 2 个属于"跨请求状态泄漏"
这一类——即上一轮已经修过一次、但**在另一层复发**的问题。这说明该缺陷类别是本项目最需要
系统性防范的对象，而不是一次性 bug。

---

## 1. 架构现状

### 1.1 分层

```
Tilua/app.lua                  Application = IoC Container（不是"拥有"容器）
Tilua/core/container.lua       容器本体：bind/singleton/scoped/instance/alias/extend/make/call/flush/defer
Tilua/core/request.lua         请求作用域载体：ngx.ctx["__tilua"] = { ctx, uri, flushed }
Tilua/core/lifecycle.lua       OpenResty 相位处理：init / init_worker / rewrite / access / content / log
Tilua/http/router.lua          Trie 路由 + 正则回退
Tilua/http/dispatcher.lua      处理器解析 + 中间件链 + 返回值归一
Tilua/middleware/init.lua      中间件管理器（相位列表 / 分组 / 别名 / 实例）
Tilua/template/init.lua        自研模板引擎（零外部依赖）
Tilua/cli/init.lua             CLI：routes / version / doctor / serve / new
```

### 1.2 生命周期（已按 OpenResty 语义重新设计）

| 相位 | 职责 |
|---|---|
| `init_by_lua`（master） | 配置 + 路由规则编译。坏配置让 `nginx -t` 失败，而不是第一个请求 |
| `init_worker_by_lua`（worker） | view engine、中间件配置、插件、`warming_up` 定时器 |
| `rewrite_by_lua` | **建立请求作用域** + rewrite 相位中间件 + 提前匹配路由（供 access 用） |
| `access_by_lua` | access 相位中间件，可短路（拒绝即止） |
| `content_by_lua` | 路由匹配（带校验）+ dispatch + 输出 |
| `log_by_lua` | 释放请求作用域 |

`set_by_lua` 已彻底移除。

**关于子请求与内部重定向的处理是正确的**，且有实测支撑（见 `core/request.lua` 头注释）：
`ngx.ctx` 在内部重定向时被整体替换，子请求有自己**空**的 `ngx.ctx`。因此槽位记录 URI 指纹，
URI 变化即重建作用域并先释放旧作用域。

> **已知限制（不是 bug，但要知道）**：作用域在**内部重定向后**才被释放，此时旧 `ctx` 已不可达，
> 只能等 GC。`core/request.lua:84-87` 的释放发生在**下一次**取得上下文时，因此"重定向后立即
> 泄漏"这一小段时间窗口是设计上接受的。

---

## 2. 本轮发现并修复的真实缺陷

以下 6 项全部先在真实运行时复现，再修复，再回归验证。

### 2.1 视图缓存路径指向错误位置（`lifecycle.lua:88`）

```lua
view_cache_path     = path_join("cache", "view", ""),   -- 相对路径，给模板引擎做 cache key
view_cache_abs_path = view_cache_path,                  -- ← 也变成了相对路径
```

`Tilua/view.lua:44-51` 把 `view_cache_abs_path` 当**文件系统前缀**用：

```lua
local view_cache_mtime = getmtime(view_cache_abs_path .. view_file)
local view_abs_path    = path.join(self.ctx.path, 'view', view_file)
local view_mtime       = getmtime(view_abs_path)
assert(view_mtime, "[view.render] Template file named " .. view_abs_path .. " not exists!")
```

于是 mtime 检查永远相对 nginx 前缀（`/app`）而非应用根（`/app/tests/fixtures/TestApp`），
**每次请求都重新编译模板**；一旦缓存文件读不到，还会把"模板不存在"误报成 500。

修复：`view_cache_abs_path = path_join(cache_path, "view", "")`。

### 2.2 中间件实例被跨请求缓存（`middleware/init.lua:89`）★ 同类复发

```lua
function manager.instance(self, midware)
    if self.midwares[hash] then return self.midwares[hash] end
    ...
    local mid = mid_class(self.ctx, midware[2])   -- ← self.ctx 是 worker 启动时的 ctx
    self.midwares[hash] = mid
end
```

中间件管理器是 **worker 级容器单例**（`init_worker_by_lua` 期间在 Application **类**上创建），
所以：

1. `self.midwares` 缓存让**第一次请求**的实例成为永久实例；
2. `self.ctx` 永远是 boot 上下文，**每个后续请求都拿不到自己的 ctx**。

而中间件把按请求状态存在 `self` 上：`mvc_router` 存 `controller_name/action_name/controller/action`，
`session` 存会话句柄，guard 存 `self.ctx`。这与 `dispatcher` 当年缓存 `self.ctx` 是**同一个缺陷类别**，
只是在另一层复发。

修复：实例缓存改挂在**请求上下文**（`ctx._middleware_instances`），并把解析上下文显式传入：

```lua
function manager.instance(self, midware, ctx)   -- dispatcher 传 ctx
```

`dispatcher.lua:72,113` 两处调用点同步传 `ctx`。

### 2.3 Trie 参数名冲突导致路由不可达 / 绑定 nil（`router.lua:217`）

Trie 每个节点只有**一个** `param` 槽位（`node.param = { name, node }`），插入时以第一次注册的
名字为准。于是：

```lua
route.get("/user/{id}",   h1)   -- 节点名 = "id"
route.get("/user/{name}", h2)   -- 复用同一节点，但 rule.args = {"name"}
```

匹配时 captures 以节点名 `id` 写入，而 dispatcher 用 `rule.args`（`name`）取名 → **绑定到 nil**。
更严重的是后注册的路由在结构上被前一个遮蔽。

修复：遍历时累积**有序的名字列表与值列表**，回溯时正确回退，最后按名字成对写入 captures；
另外按位置为 `rule.args` 里未覆盖的名字补别名（兼容两种命名风格）。

同时暴露了一个**非确定性**问题：`init_rule_caches` 用 `pairs()` 遍历 `route.rules[app]`
（哈希表），每个进程的编译顺序不同 → 谁遮蔽谁、哪条 validation 生效，**每个 worker 都可能不一样**。
修复：为声明式规则键记录声明序号 `_rule_seq`，按序号排序编译（`router.lua:440-465`）。

> **仍存在的设计限制**：同形路由（`/user/{a}` vs `/user/{b}`）只有第一条可达——Trie 结构决定的。
> 现在至少是**确定性地**由第一条获胜，且获胜方拿到自己的参数值。文档需明确这一点。

### 2.4 CLI 启动调用已删除的方法（`cli/init.lua:680`）

```lua
pcall(function()
    app:load_config()    -- nil
    app:load_route()     -- nil
end)
```

`load_config` / `load_route` 早已合并进 `load_config_and_routes()`，而 `pcall` 把
"attempt to call a nil value" 吞掉——**CLI 静默运行在一个未配置的 app 上**。

修复：改调 `load_config_and_routes()` + `boot_worker()`，失败写 stderr 但不致命
（`help` / `version` / `new` 不需要已配置的 app）。

### 2.5 `route.rest()` 生成无法解析的处理器名（`router.lua:995`）

```lua
name .. "." .. m[1] .. m[2]     -- "post" → "post.GET/new"、"post.DELETE/{id}"
```

任何 `require` 都无法解析这种名字，所有 `rest()` 生成的路由都是 404。

修复：改为约定动作名——`post.index` / `post.store` / `post.create` / `post.show` /
`post.update` / `post.destroy` / `post.edit`，并接受 `"post"` 或 `"post.index"` 两种写法。

### 2.6 e2e 的 `lfs` 桩是"错误方向的桩"（`tests/e2e/lua/lfs.lua:53`）

桩只实现 `mode` / `size`，且把 size 硬编码成 0，**从未实现 `modification`**。
于是 `path.getmtime()` 对**任何存在的文件都返回 nil**，`view.lua:51` 把它当成"模板不存在"。

这比"没有桩"更糟：**一个和被测代码同向出错的桩会把真 bug 伪装成假 bug**（当时正是它让
`/view` 报 500，掩盖了 2.1 的真实症状）。修复：用 `stat(1)` 读取真实 `mode/size/atime/mtime/ctime`。

同时发现 e2e 环境本身的问题：仓库以 bind mount 挂载、只有 root 可写，而 nginx worker 默认
以 `nobody` 运行 → 模板缓存写入 `EACCES`。`nginx.conf` 加 `user root;`（仅测试用）。

---

## 3. 已验证的正确行为（回归基线）

真机 nginx（`openresty/openresty:1.21.4.1-buster`，`tests/e2e/run.sh`），19/19：

| 用例 | 期望 | 结果 |
|---|---|---|
| `/greeter` | 200 JSON | 200 |
| `/text`（裸字符串返回） | 200 文本 | 200 `TEXT-MARKER` |
| `/text-literal`（`response(...)`） | 200 文本 | 200 |
| `/view`（`return "index", {}`） | 200 HTML + **转义** | 200，`&lt;b&gt;&amp;&lt;/b&gt;` |
| `/view-assign`（`view:assign` + 无 context） | 200 HTML | 200 |
| `/about`（回调形式注册） | 200 | 200 |
| `/user/{name}` | 参数绑定 | 200 `hello ada` |
| `/num/42` / `/num/abc` | 正则校验 ACCEPT / REJECT | 200 / 404 |
| `/kind/ok` / `/kind/no` | eq 校验 ACCEPT / REJECT | 200 / 404 |
| `/pair/x` | 同形参数获胜方拿到自己的值 | 200 `pair-a=x` |
| `/left/1`、`/right/2` | 不同父节点参数名互不干扰 | 200 / 200 |
| `/admin`（无 token / 有 token） | access 相位拒绝 / 放行 | 403 / 200 |
| `/healthz` | 业务路由未注册 → 404 | 404 |
| `/nope` | 404 | 404 |
| `/boom` | 500 且 JSON 含 `request_id` | 500 |

单元套件 14/14（含新增 `test_middleware_instance_scope`），连跑 3 轮无抖动。
所有 91 个 Lua 文件 `luajit -bl` 解析通过。

---

## 4. 仍然存在的设计取舍与待办（未修改，供决策）

### 4.1 架构层

1. **插件钩子在相位路径下不触发**（重要）
   `Plugin.emit("on_request"/"on_dispatch"/"on_response"/"on_error")` 只出现在
   `Tilua/app.lua:437-439`（`App:run()`）与 `core/channel.lua:74-116`（HTTP channel）。
   真实 nginx 配置走的是 `lifecycle.content_by_lua`，**从不发这些钩子**——只有
   `on_route_loaded` 会发。因此插件系统目前在标准部署下基本是哑的。

2. **两条并存的请求路径**
   `core/channel.lua` 的 `http_handle` 自带"健康检查 + 路由 + dispatch + 错误处理"，
   与 `lifecycle.content_by_lua` 功能重复。`App:run()` / `run_cli()` 只在 CLI/WS 或非相位
   嵌入时有意义。建议明确"相位路径为准"，把 channel 的 HTTP 分支收敛为健康检查/WS 专用。

3. **`App:boot()` 与相位路径的边界**
   CLI 用 `load_config_and_routes() + boot_worker()`；`App:boot()` 是两者合一。语义已清晰，
   但 `docs/LIFECYCLE.md` 曾写作 `load_config()`，已修正。

### 4.2 安全 / 健壮性

4. **`Exception.request_id` 用 `math.random`**（`core/exception.lua:114`）
   请求 ID 可预测（未 seed）。仅用于日志关联，风险低，但既然 `util.random_string`
   已经有 `/dev/urandom` + `RAND_bytes` 实现，应直接复用。

5. **模板环境暴露 `_G`**（`template/init.lua:133`）
   `build_env` 在 context 未命中时回退 `_G[k]`，模板里可访问任意全局。模板是开发者
   自己写的，不是用户输入，因此不是漏洞；但削弱了"模板沙箱"的边界。

6. **`M:process` 用 `load()` 探测是否预编译**（`template/init.lua:232`）
   `if not load_lua(content, ...) then` —— 用 `load` 判断内容是不是 Lua。`load` 只编译不执行，
   所以没有执行风险，但"编译失败即当模板"意味着每次渲染都要先尝试一次 Lua 编译。
   建议改为按缓存文件路径判断，而不是靠内容嗅探。

7. **`util.import` 用 `pcall(require)` 静默失败**（`utils/util.lua:417-426`）
   拼错模块名会得到 `nil`，调用方往往忘了检查。容器里的 `load_module` 已经改成"响亮失败"，
   `util.import` 还是静默的——建议统一。

### 4.3 文档漂移

8. `docs/ANALYSIS.md` 是 v0.7.0 的静态报告，开头即声明"没有执行任何代码"，其中大量
   "不可用"结论已被本轮实测推翻。**建议在文件头加 superseded 标注**，或归档。
9. `docs/LIFECYCLE.md` 的 `App:load_config()`、`docs/CONTAINER.md` 的 `set_by_lua`
   引用都已过时——**本轮已修正**。
10. `README.md` 状态行仍写 `v0.2.0`——**本轮已改为 v0.9.3**。

### 4.4 测试

11. `lua_stub.lua` 的 `ngx.re.match/find` 恒返回 nil，因此**正则/参数校验类断言无法在单元层
    覆盖**，只能在真机 e2e 里验证。这是已知边界，建议在 `tests/README` 里写清。
12. **`tests/test_orm_helpers.lua:39` 失败**（`attempt to call method 'parseSql'`）。
    ORM 明确不在范围内，未处理。这是唯一失败的套件。
13. 建议补：`App:boot()` / `run_cli()` 路径的测试（当前只有 CLI 命令级测试）。

### 4.5 环境依赖

14. `Tilua/utils/util.lua` 硬依赖 `resty.jit-uuid`、`cjson.safe`，`Tilua/utils/path.lua`
    硬依赖 `lfs`（缺失即 `error`）。`util.lua:16` 在 require 阶段就索引 `ngx`，**纯 Lua 环境
    无法加载**——"脱离 OpenResty 跑 CLI"这个卖点仍不成立（CLI 必须跑在 `resty` 或 nginx 里）。
    这正是上一份报告的结论之一，**依然成立**。

---

## 5. 建议的下一步（按价值排序）

1. **修插件钩子**（4.1.1）——现在插件系统在标准部署下不工作，属于"承诺了但没接线"。
2. **收敛双请求路径**（4.1.2）——避免两条路径继续各自漂移。
3. **`ANALYSIS.md` 标注 superseded**（4.3.8）——避免后来者被过时结论误导。
4. **把"跨请求状态"变成结构性防御**——本轮 2.2 是同类缺陷第二次出现。建议：
   - 明确规则：**worker 级单例禁止持有 `ctx`**；
   - 加一条 lint/测试：遍历 worker 级绑定实例，断言不存在指向请求上下文的字段。
5. `Exception.request_id` 改用 `util.random_string`（4.2.4）。
6. 补 `App:boot()` / `run_cli()` 测试（4.4.13）。

---

## 6. 本轮改动文件清单

| 文件 | 改动 |
|---|---|
| `Tilua/core/lifecycle.lua` | `view_cache_abs_path` 改为绝对路径（2.1） |
| `Tilua/middleware/init.lua` | 中间件实例缓存改挂请求作用域；删除 worker 级 `midwares`（2.2） |
| `Tilua/http/dispatcher.lua` | 两处 `instance()` 传入请求 ctx（2.2） |
| `Tilua/http/router.lua` | Trie 捕获按路径参数名 + `rule.args` 别名（2.3）；编译顺序确定化（2.3）；`rest()` 动作名（2.5） |
| `Tilua/cli/init.lua` | `CLI.run` 调用存在的启动方法（2.4） |
| `tests/e2e/lua/lfs.lua` | 桩实现 `stat(1)` 真实元数据（2.6） |
| `tests/e2e/nginx.conf` | 测试用 `user root`（2.6 环境） |
| `tests/test_middleware_instance_scope.lua` | **新增**：中间件实例不得跨请求缓存 |
| `tests/test_trie_router.lua` | 新增参数名捕获 / 独立父节点断言 |
| `tests/fixtures/TestApp/routes.lua` | 新增 `/pair`、`/left`、`/right`、`/view-assign` |
| `tests/e2e/client.lua` | 新增 4 个 e2e 用例 |
| `.gitignore` | 忽略 `.e2e/`、生成的模板缓存 |
| `docs/LIFECYCLE.md`、`docs/CONTAINER.md`、`README.md` | 修正过时引用与版本号 |
