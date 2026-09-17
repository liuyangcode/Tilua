# Tilua IoC Container

`Tilua.core.container` 是一个 Laravel 风格的 IoC / 服务容器。**Application 对象本身就是容器**：`App` 继承自 `Container`，因此 `app:make("db")` 与 `app.db` 都会经由容器解析。

```
App (Tilua/app.lua)
 └── 继承 Container (Tilua/core/container.lua)
      ├── singleton   worker 级，进程内复用
      ├── scoped      请求级，请求结束自动回收
      └── bind        每次解析都新建
```

---

## 1. 快速上手

```lua
local App = require("Tilua.app").define()

App.name   = "MyApp"      -- 必须等于 require 路径
App.status = "dev"
App.debug  = true

--- 注册应用自己的服务（在基类构造完成之后执行）
function App:_construct(opts)
    self:singleton("report", function(c)
        return { build = function() return c.config.report_title end }
    end)

    self:alias("report", "reporting")   -- 起个别名
    return self
end

return App
```

> **注意**：`name` / `status` / `debug` 必须写在**类**上（如上），因为容器基类的构造
> 先于 `_construct` 执行。写 `_construct` 里也可以，但要在调用基类构造之前完成。

---

## 2. API

### 注册

| 方法 | 说明 |
|---|---|
| `container:bind(name, factory)` | 每次 `make` 都调用 `factory` 新建 |
| `container:singleton(name, factory)` | 每个容器只解析一次（worker 级） |
| `container:scoped(name, factory)` | 每个请求作用域解析一次，`flush()` 回收 |
| `container:instance(name, value)` | 注册已构造好的对象 |
| `container:value(name, value)` | 注册普通值（不会被当工厂调用，`false` 也安全） |
| `container:alias(name, alias)` | 给抽象起别名，支持链式 |
| `container:extend(name, decorator)` | 装饰已注册的绑定 |

`factory` 的签名是 `function(container, name)`。Lua 没有反射，**构造函数注入是显式声明**的：

```lua
app:singleton("mailer", function(c)
    return Mailer.new(c.config.smtp, c:make("logger"))   -- 显式解析依赖
end)
```

`factory` 返回 `nil` 会**报错**而不是静默变成 nil。

### 解析

| 方法 | 说明 |
|---|---|
| `container:make(name)` | 解析抽象；也支持 `{"Class", {params}, "Convention"}` 表形式 |
| `container:make(name, params)` | 类形式解析并转发构造参数 |
| `container.name` | 属性语法，等价于 `make("name")` |
| `container:bound(name)` / `:has(name)` | 是否已绑定（含别名解析） |
| `container:call(fn, args)` | 解析 `"$name"` 参数后调用 `fn` |

```lua
local db  = app:make("db")
local db2 = app.db                 -- 同上
local svc = app:make({ "UserService", { app }, "MyApp" })   -- MyApp.UserService
app:call(function(db, logger) end, { "$db", "$logger" })
```

### 生命周期

| 方法 | 说明 |
|---|---|
| `container:flush([closer])` | 释放全部 scoped 实例，默认调用其 `close()` |
| `container:defer(fn)` | 注册作用域结束回调（LIFO） |
| `container:forget(name)` | 删除绑定与缓存实例 |
| `container:scoped_instances()` | 当前存活的 scoped 名称（诊断用） |

`flush()` 会尽量继续执行：某个服务的 `close()` 抛错不会阻止其他服务被释放，错误通过第二个返回值汇总返回。

---

## 3. 生命周期与作用域

| 作用域 | 服务 | 说明 |
|---|---|---|
| **worker 单例** | `config` `logger` `middleware` `router` `dispatcher` `view_engine` | 进程内构建一次，跨请求复用 |
| **请求 scoped** | `request` `response` `view` `cache` `db` `model` `service` | 每请求构建，`log_by_lua` 阶段自动回收 |
| **每次解析** | 应用自行 `bind` 的服务 | 无缓存 |

回收链路：

```
ngx log_by_lua
  └─ App:flush_scope()          Tilua/app.lua
       ├─ Container:flush()     释放 scoped + 运行 defer（LIFO）
       │    └─ 对每个 scoped 实例调用 :close()（失败不中断，含错误汇总）
       └─ 运行 on_app_handled 注册的回调（旧 API 兼容）
```

这取代了原先的 `on_app_handled_callbacks` 手工列表；`App:on_app_handled(cb)` 仍然可用。

---

## 4. 两条必须遵守的规则

这两条都是实现过程中被真实缺陷逼出来的，违反任一条都会立刻炸。

### 4.1 类对象不能用属性语法取服务，必须用 `make()`

```lua
App:init_by_lua()          -- 阶段处理器是在「类」上调用的
App:make("config")         -- ✅ 正确
App.config                 -- ❌ 永远 nil
```

原因：类的 `_bindings[name]` 里存的是**工厂函数**，不是服务实例。如果让类也走属性解析，
返回的会是工厂函数本身（被当作方法调用还会无限递归）。
所以容器只在**实例**上启用属性解析，类上一律 `make()`。

同理，下列名字既是服务名又是方法名，属性语法会被方法遮蔽，框架内部一律用 `make()`：

`config` `router` `middleware` `plugin` `channel`

（`db` / `cache` / `logger` / `model` / `service` / `request` / `response` / `view`
没有冲突，`app.db`、`ctx.cache` 这类属性语法可正常使用。）

### 4.2 `define()` 的接收者必须显式声明

```lua
function Container.define(self)   -- ✅ 有参数
function Container.define()       -- ❌ Lua 不绑定 self
```

写成无参形式时，`App.define()` 传入的接收者被静默丢弃，子类退化成从 `Container`
派生，从而丢掉父类全部方法（`TestApp.boot` 变成 nil）。源码注释里也标注了这一点。

另外，容器内部**一律用 `rawget` 读取 `_bindings` / `_instances` / `_parent` 等内部字段**：
属性解析的 `__index` 会把「缺失的内部字段」也送去解析，从而无限递归。

---

## 5. 生命周期与作用域详解

```
App (类，worker 单例的属主)
 ├─ _instances: config, logger, router, dispatcher, plugin, channel, middleware, view_engine
 └─ _parent 指向它的请求上下文 ×N
      └─ _scoped: request, response, view, cache, db, model, service
```

- **singleton 缓存在「拥有该绑定的容器」上** → worker 类，因此跨请求共享。
- **scoped 缓存在「解析它的容器」上** → 请求上下文，因此 `flush()` 只清自己的作用域。
- 上下文通过 `_parent` 向上查找绑定与单例，所以请求里 `ctx:make("router")` 与
  `App:make("router")` 是**同一个对象**。

`Tilua/core/request.lua` 的 `context()` 在 `rewrite_by_lua` 里建立这条 `_parent`
连接（把请求容器挂到 worker 级的 `App` 类上），`log_by_lua` 再通过
`RequestCtx.finish()` 释放作用域。

---

## 6. 与旧 API 的关系

所有旧的 lazy getter 都保留为薄封装，现有应用代码无需改动：

```lua
app:get_config(key)   app:get_logger()   app:get_view()
app:get_cache()       app:get_db()       app:get_model()
app:get_service()     app:get_request()  app:get_response()
app:get_dispatcher()  app:unpack()
app:on_app_handled(cb)
```

它们内部一律走容器解析，因此**没有第二条解析路径**。

---

## 7. 测试

```bash
# 容器单元测试（纯 Lua，不需要 OpenResty）
luajit tests/support/lua_stub.lua tests/test_container.lua

# Application 容器集成测试
luajit tests/support/lua_stub.lua tests/test_app_container.lua

# OpenResty 阶段生命周期 + 请求作用域回收
luajit tests/support/lua_stub.lua tests/test_lifecycle_container.lua

# 无本地 Lua 时用 Docker
docker run --rm -v "$PWD:/app" -w /app openresty/openresty:1.21.4.1-buster \
       luajit tests/support/lua_stub.lua tests/test_lifecycle_container.lua
```

当前共 **168 项断言全部通过**（容器 55 + Application 82 + 生命周期 31）。

`tests/support/lua_stub.lua` 是共享的 no-OpenResty 测试脚手架：提供 `ngx` / `lfs`
的加载期最小面，以及 `cjson` / `resty.jit-uuid` 的桩，并自动探测
OpenResty 的 `lualib` 目录（视图渲染改由自带的 `Tilua.template` 实现，不再需要
`resty.template` 桩）。

---

## 6. 设计说明

- **不静默失败**：容器解析失败一律 `error`，错误信息包含服务名。此前的框架大量使用
  `pcall(require)`，导致 `Tilua.log.file` / `Tilua.cache.driver.redis` 这类不存在的
  模块长期静默失效。
- **`scoped` 是回收的唯一依据**：请求级资源必须注册为 `scoped`，否则不会在请求结束被释放。
- **`define()` 的接收者必须显式声明**：`function Container.define(self)`。Lua 在无参函数
  中不会绑定 `self`，写成 `function Container.define()` 会让 `App.define()` 静默退化成
  从 `Container` 派生，子类会丢掉父类方法。
