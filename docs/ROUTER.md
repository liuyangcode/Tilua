# Router 使用指南

`Tilua.http.router` 是基于**段级 Trie** 的 HTTP 路由器。旧入口 `Tilua.route`
仍然可用（一行 shim）。

```lua
local route = require("Tilua.http.router")   -- 或 require("Tilua.route")
local response = require("Tilua.http.response")
```

---

## 1. 五分钟上手

```lua
-- MyApp/routes.lua
local route    = require("Tilua.http.router")
local response = require("Tilua.http.response")

route.get("/", function(ctx)
    return response("Hello Tilua")
end)

route.get("/user/{name}", function(ctx, name)
    return response("hello " .. tostring(name))
end)

route.get("/api/status", function(ctx)
    return { ok = true }               -- 表 -> 自动 JSON
end)

-- 模块必须 return 一个函数；框架会以 (app, route) 调用它
return function(app, router)
    router.get("/about", function()
        return response("about")
    end)
end
```

> 路由文件通常在 **require 期间**就调用 `route.get(...)`。框架会先建立 app 名
> （`set_app_name`）再 require 该文件，所以两种写法都安全。

---

## 2. 注册路由

### 2.1 动词方法

```lua
route.get(path, handler [, midware [, phases]])
route.post(path, handler [, midware [, phases]])
route.put(path, handler [, midware [, phases]])
route.delete(path, handler [, midware [, phases]])
route.patch(path, handler [, midware [, phases]])
route.head(path, handler [, midware [, phases]])
route.options(path, handler [, midware [, phases]])
```

也支持 `route.add_route(app_name, verb, path, handler, ...)`。

### 2.2 声明式规则键

键的格式是 `"<method> <path> [validation]"`，方法可用逗号列举：

```lua
route["get /ping"]          = handler
route["get,post /form"]     = handler
route["delete /item/{id}"]  = handler
```

这是**唯一**能携带参数校验表达式的写法（见 §6）。

### 2.3 分组共享中间件

```lua
-- 两种等价写法
route.group(function()
    route.get("/a", h)
    route.get("/b", h)
end, "auth", "log")

route.group(function()
    route.get("/c", h)
end, { "auth", "log" })
```

组内声明的中间件会被**前置**到组内每条路由的链路，组外路由不受影响。
两种写法的条目都会被规范化成 `{ name, config }`。

### 2.4 RESTful 资源

```lua
route.rest("/users", handler)
```

一次生成 7 条：

| 方法 | 路径 |
|---|---|
| GET | `/users` |
| POST | `/users` |
| GET | `/users/new` |
| GET | `/users/{id}` |
| PUT | `/users/{id}` |
| DELETE | `/users/{id}` |
| GET | `/users/{id}/edit` |

`handler` 为函数时 7 条共用同一个；为字符串时按 `<name>.<METHOD><suffix>` 生成。
**注意**：`/users/new` 依赖静态优先于参数（§5），所以不会被 `{id}` 抢走。

---

## 3. 路径语法

| 写法 | 含义 | 示例匹配 |
|---|---|---|
| `/users` | 静态段 | 仅 `/users` |
| `{name}` | 捕获**一段** | `/users/{id}` ← `/users/42` |
| `*` | 吞掉**剩余全部**段（匿名，捕获名 `splat`） | `/files/*` ← `/files/a/b.txt` |
| `{path*}` | 同上，但捕获名自定 | `/assets/{p*}` ← `/assets/css/a.css` |

### 归一化

匹配前会折叠重复斜杠并去掉尾部斜杠：

```lua
"/about"   == "/about/"  == "//about"   -- 都匹配
```

因此 `/user/` 归一化为 `/user`（**一段**），**不会**匹配 `/user/{name}`（两段）。

---

## 4. 匹配模型

每个路径段独立比较，优先级为：

```
静态  >  {name}  >  *
```

**静态命中即返回**，与注册顺序无关。这解决了一类经典问题：

```lua
route.get("/user/{id}",  h_id)     -- 先注册参数路由
route.get("/user/new",   h_new)    -- 后注册静态路由

--> GET /user/new  交给 h_new，不是 h_id
```

复杂度为 O(路径段数)，与注册路由总数无关。

### 通配是终结性的

`*` / `{name*}` 只在**其余全部段被消费**后才生效，因此不会意外遮蔽更具体的路由：

```lua
route.get("/files/*",      h_all)
route.get("/files/readme", h_readme)

--> /files/readme      -> h_readme（具体优先）
--> /files/a/b/c.txt   -> h_all，捕获 splat = "a/b/c.txt"
--> /files/            -> h_all，捕获 splat = ""
```

### 前缀路由

`*` 作为**匹配符前缀**（不是段）表示前缀匹配：

```lua
route["* /api"] = handler
--> /api/anything/here  匹配
--> /apifoo             不匹配（尊重段边界）
```

---

## 5. 处理器签名与返回值

```lua
function(ctx, ...) end
```

`ctx` 是请求作用域容器；路径参数（按声明顺序）作为后续位置参数传入。

```lua
route.get("/user/{uid}/post/{pid}", function(ctx, uid, pid) end)
route.get("/files/*",               function(ctx, splat)  end)
route.get("/assets/{p*}",           function(ctx, p)      end)
```

> 参数**按名绑定**（取自 trie 捕获），不依赖位置索引。

### 返回值

| 返回 | 结果 |
|---|---|
| `response("text")` | 200，`text/plain` 文本 |
| `response:json(t, 201)` | 指定状态码的 JSON |
| 表 `{ ok = true }` | 200，自动 JSON |
| 字符串 `"hello"` | 200，**纯文本**（不是视图名） |
| `"index", { title = "x" }` | 渲染视图 `index`，上下文为第二值 |
| 数字 `404` | 该状态码；第二值为字符串时作为 body |
| `errors.not_found()` | 结构化错误 → 统一 JSON 错误体 |
| `response` 对象 | 原样透传 |
| 抛错 | 500 统一 JSON（含 `request_id`） |

`ctx` 上可取的服务（容器解析）：

```lua
function(ctx)
    local req  = ctx:make("request")
    local cfg  = ctx:make("config")
    local db   = ctx:make("db")
    ...
end
```

> `config` / `router` / `middleware` / `plugin` / `channel` 这五个名字同时是方法名，
> 属性语法会被方法遮蔽，**必须用 `make()`**。其余（`db`/`cache`/`request`/`response`/
> `view`/`model`/`service`）可用 `ctx.db` 这类属性语法。

---

## 6. 参数校验

校验表达式写在规则键的**第三个空白分隔字段**，格式 `<参数名>:<操作符>,<值>`：

```lua
route["get /num/{id} id:reg,^[0-9]+$"] = function(ctx, id)
    return response("numeric id=" .. tostring(id))
end

route["get /kind/{k} k:eq,ok"] = function(ctx, k)
    return response("kind=" .. tostring(k))
end
```

实测：

| 请求 | 结果 |
|---|---|
| `/num/42` | 200 `numeric id=42` |
| `/num/abc` | **404**（校验不通过，视为未匹配） |
| `/kind/ok` | 200 `kind=ok` |
| `/kind/no` | **404** |

支持的操作符：`reg`（正则，用 `ngx.re.find`）、`eq`、`neq`、`in`、`notin`。
多个条件用 `;` 分隔：

```lua
route["get /u/{id} id:reg,^[0-9]+$;id:neq,0"] = handler
```

**校验不通过按"未匹配"处理**，因此继续落到其他候选路由，最终得到 404。

> ⚠️ 第三个参数式写法 `route.get(path, handler, "id:reg,...")` **不生效** ——
> `route.get` 的第三个字符串参数被当作**中间件**。校验必须写在规则键里。

---

## 7. 正则路由（fallback）

Trie 无法容纳任意正则，因此 `~` 匹配符的路由进入一个**扁平回退列表**，
在 trie 未命中后按注册顺序尝试：

```lua
route["get ~/u/(%d+)"] = function(ctx, id) end
```

**重要区别**：含 `{name}` 段的 `~` 规则仍走 trie（因此享有 O(k) 与优先级）；
只有**纯正则**（无参数段）才落入回退列表。

```lua
route["get ~/user/{id}"] = h1   -- 走 trie
route["get ~/u/(%d+)"]   = h2   -- 走回退列表
```

回退列表是最后手段，优先级低于任何 trie 命中。

---

## 8. 中间件

### 8.1 路由级（content 阶段）

```lua
route.get("/dash", handler, "auth")                  -- 单个
route.get("/dash", handler, { "auth", "log" })       -- 多个
```

条目可为裸字符串 `"auth"` 或 `{ name, config }`；写 `{"auth"}` 时会被规范化。

### 8.2 声明 OpenResty 阶段

有些中间件应在**更早的阶段**跑（鉴权在 content 之前拒绝请求，省掉业务开销）。
用第 4 个参数的 `phases` 字段声明：

```lua
route.get("/admin", function(ctx)
    return response("admin area")
end, nil, { phases = { access = { "admin_guard" } } })
```

实测：

| 请求 | 结果 |
|---|---|
| `GET /admin`（无 token） | **403** `admin token required` |
| `GET /admin` + `X-Admin-Token: letmein` | 200 `admin area` |
| `GET /greeter` | 200（**不受该守卫影响**） |

**关键**：`rewrite` 阶段会先做一次路由匹配并把结果存入请求上下文，
`access` 阶段只对**该条已匹配路由**声明的中间件生效。否则声明在 `/admin` 上的守卫
会把整个应用都拦下。

可选阶段：`rewrite`、`access`、`content`（默认）。

### 8.3 全局阶段中间件

配置里声明的阶段中间件对**每个请求**生效：

```lua
-- config
middleware_phases = {
    rewrite = { "html_cache" },
    access  = { "rate_limit" },
}
```

### 8.4 中间件命名解析

名字按以下顺序解析：

1. `middleware_alias` 别名（如 `session` → `Tilua.middleware.session`）
2. 含点的全限定模块名（`MyApp.middleware.auth`）
3. **应用自身命名空间**：`admin_guard` → `MyApp.middleware.admin_guard`
4. 原名（框架内置或全局模块）

---

## 9. 校验与调试 API

```lua
-- 解析一条规则字符串
local method, matcher, url, validation = route.parse_rule("get /user/{id} id:reg,^[0-9]+$")

-- 自建规则表（声明式批量注册）
route.set_app_name("MyApp")
route.init_rule_caches({
    ["get /a"] = handler_a,
    ["post /b"] = handler_b,
})

-- 直接匹配（不经过请求上下文）
local rule, captures = route.match("MyApp", "get", "/user/42")
print(captures.name)     -- "42"

-- 解析路径 -> 正则（html_cache 中间件使用）
local url, regex, params = route.parse_path_to_regex("/user/{name}")
```

匹配结果 `rule` 上可用字段：`path`、`matcher`、`method`、`responser`、`midware`、
`args`（参数名顺序）、`validation`；`route.run(ctx)` 另外注入 `vals`（捕获表）与
`extra_path`（splat）。

---

## 10. 与请求生命周期的衔接

```
init_by_lua        (master)  register_routes()  -> 编译 trie
init_worker_by_lua (worker)  boot_worker()
rewrite_by_lua               建立请求作用域 + 路由匹配 + rewrite/w* 中间件
access_by_lua                该路由的 access 中间件（可短路）
content_by_lua               路由分发 + 处理器 + 输出响应
log_by_lua                   释放请求作用域
```

nginx 配置见 `tests/e2e/nginx.conf`。详见 `docs/LIFECYCLE.md`。

---

## 11. 已知陷阱

### 11.1 不要给 `route` 表写新字段

模块元表用 `__newindex` 实现 `route["get /x"] = h` 简写，而该钩子对**所有**新增键的
赋值都生效 —— 包括内部记账：

```lua
route.my_state = 1          -- ❌ 被当成路由注册！key 变成 "my_state ..."
rawset(route, "my_state", 1) -- ✅ 需要自己挂状态时用 rawset
```

框架内部已改为 `rawset` / 预置子表，但**应用代码不要往 `route` 上挂字段**。

### 11.2 裸字符串返回是纯文本，不是视图名

```lua
return "hello"             -- 200 text/plain: hello
return "index", { t = 1 }  -- 渲染视图 index
```

### 11.3 `route.get` 的第三个字符串是中间件

```lua
route.get("/a", h, "auth")               -- ✅ auth 是中间件
route.get("/a", h, "id:reg,^[0-9]+$")    -- ❌ 被当中间件，校验不生效
route["get /a id:reg,^[0-9]+$"] = h      -- ✅ 校验必须走规则键
```

### 11.4 同名参数不会合并

同一位置声明两种参数名时，它们**共用同一个节点**，只捕获一个名字（实测为**后注册者**生效）：

```lua
route.get("/u/{id}",   h1)
route.get("/u/{name}", h2)   -- 共用节点，最终捕获名是 name
```

请避免在同一位置用不同参数名。

### 11.5 `req:get_header(name)` 不可用

类系统的 `__index` 包装器对 `get_*` 方法只传 receiver、丢弃参数，所以 `name` 收到的
是请求表本身。请直接读表：

```lua
local headers = ctx:make("request").header
local token = headers["x-admin-token"]
```

### 11.6 内部重定向前的旧作用域不即时释放

`ngx.exec` 会整体替换 `ngx.ctx`，旧上下文从中不可达，依赖 GC 回收。详见
`docs/LIFECYCLE.md`。

---

## 12. 测试

```bash
# Trie 路由单元测试（56 项断言）
luajit tests/support/lua_stub.lua tests/test_trie_router.lua

# 真实 nginx 端到端（含参数校验、阶段中间件）
docker run --rm -v "$PWD:/app" -w /app openresty/openresty:1.21.4.1-buster \
       sh tests/e2e/run.sh
```
