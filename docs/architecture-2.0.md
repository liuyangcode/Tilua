# Tilua 2.0 完整架构改造文档

## 1. 项目目标

Tilua 2.0 的目标是构建一个面向 OpenResty/LuaJIT 的现代化、高性能、可扩展 Web Application Framework。

核心目标：

- 保留 OpenResty 的高性能模型
- 请求状态彻底隔离
- Worker 级 Application 常驻
- Router 启动阶段编译
- Middleware Pipeline 化
- Controller / Service / Repository 分层
- DB / Cache 独立抽象
- 统一异常处理
- 统一 Request / Response
- 统一 Context
- DI Container
- 结构化日志
- Session 独立
- 尽量兼容 Tilua 1.x
- 为 OpenAPI、CLI、WebSocket 等后续能力留出接口

## 2. 现有 Tilua 的主要问题

当前架构最大的不是功能少，而是职责混杂和状态边界不清晰。

当前 `app.lua`、`route.lua`、`dispatch.lua`、`model/model.lua`、`session.lua`、`log.lua` 等模块承担了过多职责，同时存在模块级可变状态。

OpenResty 中 Lua module 会在 Worker 生命周期内缓存，因此必须严格区分 Worker State 和 Request State。

目标边界：

```text
Worker State
    ↓
Application
    ↓
Request
    ↓
Context
```

任何当前请求的 route、params、user、request、response 等状态都不能放入 Worker 级共享变量。

## 3. Tilua 2.0 总体架构

```text
OpenResty
  -> Tilua Runtime
     -> Application
     -> Context
     -> Router
     -> Middleware Pipeline
     -> Controller
     -> Service
     -> Repository
     -> DB/Cache
     -> Response
```

完整调用链：

```text
HTTP
 ↓
Context
 ↓
Router
 ↓
Middleware
 ↓
Controller
 ↓
Service
 ↓
Repository
 ↓
DB / Cache
```

## 4. 核心设计原则

### 4.1 Application 是 Worker 级

Application 在 Worker 生命周期内创建并复用，负责 Config、Container、Router、Middleware、DB、Cache、Logger、Session 等 Worker 级组件。

Application 不保存：

- current_request
- current_user
- current_route
- current_params
- current_response

### 4.2 Context 是请求核心

每个请求创建独立 Context，并可挂载到 `ngx.ctx`。

```lua
Context {
    app
    request
    response
    route
    params
    state
    services
    session
    request_id
    trace_id
    finished
}
```

### 4.3 Router 编译后只读

路由定义在启动阶段编译，请求阶段只进行匹配，不保存当前请求状态。

### 4.4 Controller / Service / Repository 分层

```text
Controller
    ↓
Service
    ↓
Repository
    ↓
Database
```

Controller 负责 HTTP 层，Service 负责业务逻辑，Repository 负责数据访问。

## 5. 推荐目录结构

```text
Tilua/
├── core/
│   ├── application.lua
│   ├── context.lua
│   ├── container.lua
│   ├── lifecycle.lua
│   ├── config.lua
│   └── exception.lua
│
├── http/
│   ├── request.lua
│   ├── response.lua
│   ├── cookie.lua
│   └── body.lua
│
├── router/
│   ├── router.lua
│   ├── route.lua
│   ├── compiler.lua
│   ├── matcher.lua
│   └── trie.lua
│
├── middleware/
│   ├── middleware.lua
│   ├── registry.lua
│   ├── compiler.lua
│   ├── pipeline.lua
│   ├── auth.lua
│   ├── cors.lua
│   ├── csrf.lua
│   ├── rate_limit.lua
│   └── session.lua
│
├── controller/
│   ├── controller.lua
│   ├── api_controller.lua
│   └── invoker.lua
│
├── service/
├── repository/
│   └── repository.lua
├── model/
│   ├── model.lua
│   └── entity.lua
├── database/
│   ├── manager.lua
│   ├── connection.lua
│   ├── transaction.lua
│   ├── query.lua
│   └── driver/
│       └── mysql.lua
├── cache/
│   ├── manager.lua
│   └── driver/
├── session/
│   ├── manager.lua
│   ├── cookie.lua
│   ├── serializer.lua
│   └── driver/
├── logging/
│   ├── logger.lua
│   ├── formatter.lua
│   └── writer.lua
├── view/
│   └── renderer.lua
└── utils/
```

## 6. Core Application

`core/application.lua` 负责：

- Config
- Container
- Router
- Middleware
- DB
- Cache
- Logger
- Session
- Lifecycle

生命周期：

```text
Application()
      ↓
configure()
      ↓
register_core()
      ↓
register_services()
      ↓
load_router()
      ↓
load_middleware()
      ↓
boot()
      ↓
init_worker()
```

## 7. Container

`core/container.lua` 提供 Dependency Injection。

支持：

```lua
container:bind()
container:singleton()
container:value()
container:instance()
container:get()
container:make()
container:has()
```

例如：

```lua
app.container:singleton(
    "user_service",
    function(container)
        return UserService(
            container:get("user_repository")
        )
    end
)
```

## 8. Router 2.0

Router 是 2.0 核心模块。

目录：

```text
router/
├── router.lua
├── route.lua
├── compiler.lua
├── matcher.lua
└── trie.lua
```

### 8.1 Route

Route 表示一条路由定义：

```lua
Route {
    name = "users.show",
    method = "GET",
    path = "/users/{id}",
    handler = "User@show",
    middleware = {}
}
```

### 8.2 Router API

必须支持：

```lua
router:add()
router:get()
router:post()
router:put()
router:patch()
router:delete()
router:options()
router:any()
```

例如：

```lua
router:get("/users", "User@index")
router:get("/users/{id}", "User@show")
router:post("/users", "User@create")
router:put("/users/{id}", "User@update")
router:delete("/users/{id}", "User@delete")
```

### 8.3 Router 编译

路由在 Application 启动阶段编译，请求阶段不再重复解析 `/users/{id}`。

```text
Route Definition
       ↓
Compiler
       ↓
Compiled Route
       ↓
Matcher
```

### 8.4 Router 匹配结果

```lua
local result = router:match("GET", "/users/123")
```

返回：

```lua
{
    route = route,
    params = {
        id = "123"
    },
    method = "GET",
    path = "/users/123"
}
```

然后：

```lua
ctx:set_route(result)
```

Router 禁止保存 `current_route`、`args`、`vals` 等请求级状态。

### 8.5 Trie

第一阶段允许使用编译后的路由列表进行匹配；后续可使用 Trie 优化大量路由场景。

## 9. Middleware Pipeline

统一请求管线：

```text
Request
 ↓
Request ID
 ↓
CORS
 ↓
Rate Limit
 ↓
Session
 ↓
Auth
 ↓
Controller
 ↓
Response
```

统一接口：

```lua
function Middleware:handle(ctx, next)
end
```

Pipeline：

```lua
pipeline:handle(ctx)
```

Middleware 不负责业务数据访问。

## 10. Controller

Controller 只负责 HTTP 层。

```lua
local UserController = {}

function UserController:index(ctx)
    local service = ctx:service("user_service")
    return ctx:json(service:list())
end

return UserController
```

Controller 不应该直接操作 MySQL/Redis，也不应该承担核心业务规则。

## 11. Controller Invoker

新增：

```text
controller/invoker.lua
```

负责统一执行：

- `User@index`
- `User@show`
- `UserController@index`
- `function(ctx)`

流程：

```text
解析 Handler
 ↓
加载 Controller
 ↓
解析 Action
 ↓
注入 Context
 ↓
执行
```

## 12. Service

Service 负责业务逻辑：

- 业务规则
- 业务校验
- 事务协调
- 权限相关业务判断
- 多 Repository 协作
- Cache
- 事件

例如：

```lua
function UserService:create(data)
    self.validator:validate(data)
    return self.repository:create(data)
end
```

## 13. Repository

Repository 负责数据访问：

- SELECT
- INSERT
- UPDATE
- DELETE

Repository 不处理 HTTP、Session、Controller，也不承担业务规则。

## 14. Model / Entity

现有 Model 职责过重，2.0 拆分为：

```text
Model  → 数据模型定义
Entity → 数据对象
Repository → 数据访问
Service → 业务逻辑
```

## 15. Database

目录：

```text
database/
├── manager.lua
├── connection.lua
├── transaction.lua
├── query.lua
└── driver/
    └── mysql.lua
```

架构：

```text
Application
     ↓
Database Manager
     ↓
Connection Pool
     ↓
MySQL Driver
```

连接属于请求使用周期，不能把正在使用的 connection 作为全局共享连接。

### Transaction

```lua
db:transaction(function(tx)
    tx:insert(...)
    tx:update(...)
end)
```

异常时自动 Rollback。

## 16. Cache

目录：

```text
cache/
├── manager.lua
└── driver/
```

统一接口：

```lua
cache:get()
cache:set()
cache:delete()
cache:has()
cache:remember()
```

Redis 作为 Driver，而不是与业务 Model 耦合。

## 17. Session

目录：

```text
session/
├── manager.lua
├── cookie.lua
├── serializer.lua
└── driver/
```

Session 属于请求 Context，不保存当前用户到 Worker 级状态。

## 18. HTTP Request

`http/request.lua` 提供：

```lua
request:method()
request:path()
request:query()
request:headers()
request:body()
request:cookie()
request:ip()
request:host()
```

Controller 应通过 Request 抽象访问 HTTP 信息，而不是到处直接访问 `ngx.var` / `ngx.req`。

## 19. HTTP Response

`http/response.lua` 提供：

```lua
response:json()
response:text()
response:html()
response:redirect()
response:file()
response:status()
response:header()
response:cookie()
response:send()
```

### Response 生命周期

正确流程：

```text
rewrite
 ↓
access
 ↓
content
 ↓
response send
 ↓
log
```

`content` 阶段执行 Router、Middleware、Controller 并发送 Response；`log` 阶段只做日志、Metrics、Trace 和清理，不能再发送 HTTP Response。

## 20. Exception

新增：

```text
core/exception.lua
```

统一处理：

- Router Exception
- Controller Exception
- Service Exception
- Database Exception
- Middleware Exception

API 错误建议统一返回：

```json
{
    "code": 500,
    "message": "Internal Server Error",
    "request_id": "..."
}
```

生产环境禁止泄露 stack trace、SQL、密码、内部文件路径等敏感信息。

## 21. Logging

拆分：

```text
logging/
├── logger.lua
├── formatter.lua
└── writer.lua
```

推荐结构化日志：

```lua
logger:error(
    "database query failed",
    {
        request_id = ctx:request_id(),
        trace_id = ctx:trace_id(),
        table = "users"
    }
)
```

## 22. Trace

Context 提供：

```lua
ctx.request_id
ctx.trace_id
```

贯穿：

```text
Request
 ↓
Router
 ↓
Middleware
 ↓
Controller
 ↓
Service
 ↓
Repository
 ↓
Database
```

## 23. Configuration

新增：

```text
core/config.lua
```

推荐配置：

```text
config/
├── default.lua
├── development.lua
├── testing.lua
└── production.lua
```

统一通过 Config 访问，而不是在业务代码中散落读取配置结构。

## 24. OpenResty 生命周期

```text
init_by_lua
      ↓
Application 创建
      ↓
Config / Container / Router / Middleware / Service
      ↓
init_worker_by_lua
      ↓
worker ready
      ↓
HTTP Request
      ↓
Context 创建
      ↓
rewrite
      ↓
access
      ↓
content
      ↓
Router
      ↓
Middleware
      ↓
Controller
      ↓
Service
      ↓
Repository
      ↓
Response
      ↓
log
      ↓
Context cleanup
```

## 25. ngx.ctx

`ngx.ctx` 作为请求上下文挂载点。

Worker 级：

```text
Application
Router
Container
Database Manager
Cache Manager
Logger
```

请求级：

```text
Context
Request
Response
Route
Params
Session
User
```

## 26. 明确禁止的设计

禁止：

```lua
_G.current_user
_G.current_route
_G.request
_G.response
```

禁止：

```lua
router.current_route = route
router.args = args
app.current_request = request
```

任何请求状态必须放在 Context / `ngx.ctx` 中。

## 27. 请求处理主链

统一入口：

```lua
Application:handle(ctx)
```

内部：

```text
1. 创建 Context
2. Router match
3. ctx:set_route()
4. Middleware Pipeline
5. Controller Invoker
6. Service
7. Repository
8. Response
```

## 28. 路由示例

```lua
local router = app:router()

router:get("/", "Home@index")
router:get("/users", "User@index")
router:get("/users/{id}", "User@show")
router:post("/users", "User@create")
```

带 Middleware：

```lua
router:get(
    "/admin/users",
    "AdminUser@index",
    {
        "auth",
        "admin"
    }
)
```

## 29. 完整请求示例

```text
GET /users/123
Authorization: Bearer xxx

OpenResty
   ↓
Tilua Application
   ↓
Context
   ↓
Router
   ↓
匹配 /users/{id}
   ↓
ctx.params.id = "123"
   ↓
Auth Middleware
   ↓
UserController@show
   ↓
UserService:get(123)
   ↓
UserRepository:find(123)
   ↓
Database
   ↓
Response JSON
```

## 30. 兼容旧版 Tilua

2.0 不一次性删除所有旧模块，采用 Compatibility Layer。

```text
Tilua 1.x API
      ↓
Compatibility Layer
      ↓
Tilua 2.0
```

旧 `route.lua`、`dispatch.lua`、Model、DB、Cache 等可以在迁移期保留。

旧 API 应逐步映射到新的 Application / Router / Pipeline / Controller / Service API。

## 31. Migration Strategy

采用渐进式迁移：

```text
Phase 0  基础设施
 ↓
Phase 1  Core
 ↓
Phase 2  Router
 ↓
Phase 3  Middleware
 ↓
Phase 4  HTTP
 ↓
Phase 5  Controller
 ↓
Phase 6  Service / Repository
 ↓
Phase 7  Database / Cache
 ↓
Phase 8  Session / Logging
 ↓
Phase 9  Compatibility
 ↓
Phase 10 删除旧架构
```

## 32. Phase 0 —— 基础设施

建立：

```text
tests/
docs/
examples/
```

测试目录：

```text
tests/
├── core/
├── router/
├── middleware/
├── http/
├── database/
└── integration/
```

## 33. Phase 1 —— Core

核心文件：

```text
core/application.lua
core/context.lua
core/container.lua
core/lifecycle.lua
core/config.lua
core/exception.lua
```

目标：稳定 Application、Context、Container、Lifecycle。

## 34. Phase 2 —— Router

目标文件：

```text
router/router.lua
router/route.lua
router/compiler.lua
router/matcher.lua
router/trie.lua
```

重点：

- 无请求级全局状态
- 启动阶段编译
- 参数提取
- Method 匹配
- Route Middleware
- Route Name
- 404
- 405
- 静态路由优化

## 35. Phase 3 —— Middleware

目标：

```text
middleware/middleware.lua
middleware/registry.lua
middleware/compiler.lua
middleware/pipeline.lua
```

然后增加：

```text
CORS
Auth
CSRF
Rate Limit
Session
Logging
```

## 36. Phase 4 —— HTTP

将旧 `request.lua` / `response.lua` 逐步迁移到：

```text
http/request.lua
http/response.lua
```

确保 Request、Response、Context 完全解耦。

## 37. Phase 5 —— Controller

增加：

```text
controller/controller.lua
controller/api_controller.lua
controller/invoker.lua
```

旧 `dispatch.lua` 逐步退化为兼容层。

## 38. Phase 6 —— Service / Repository

建立：

```text
service/
repository/
```

统一业务链：

```text
Controller
    ↓
Service
    ↓
Repository
    ↓
Database
```

## 39. Phase 7 —— Database / Cache

将旧 `db.lua` / `cache.lua` 拆分为：

```text
database/
cache/
```

优先完成：

- MySQL
- Redis
- Transaction
- Connection Pool

## 40. Phase 8 —— Session / Logging

拆分：

```text
session/
logging/
```

增加：

- request_id
- trace_id
- structured logging

## 41. Phase 9 —— Compatibility

迁移期允许：

```text
新代码 → 2.0 API
旧代码 → Compatibility API
```

## 42. Phase 10 —— 删除旧架构

当 Router、Middleware、Controller、HTTP、DB、Cache、Session、Logging 全部由 2.0 接管后，再删除旧 `app.lua`、`route.lua`、`dispatch.lua` 等核心旧实现。

## 43. 测试策略

至少建立四层测试：

### Unit

Router、Matcher、Compiler、Container、Context、Response。

### Integration

Router + Middleware、Controller + Service、Service + Repository、Repository + DB。

### OpenResty

测试 `ngx`、`ngx.ctx`、Worker、Request Lifecycle。

### Stress

测试大量路由、高并发、连接池、Redis 等场景。

## 44. Router 测试重点

测试：

```text
GET /
GET /users
GET /users/123
POST /users
DELETE /users/123
```

以及：

```text
/static
/hello/{name}
/users/{id}/posts/{post_id}
```

异常：

```text
404
405
重复 route
重复 route name
非法 path
非法 method
```

## 45. Context 并发隔离测试

必须保证：

```text
Request A → /users/1
Request B → /users/2
```

结果：

```text
A.ctx.params.id == 1
B.ctx.params.id == 2
```

不能出现请求之间互相覆盖。

## 46. 性能目标

2.0 不应因为分层明显降低 OpenResty 性能。

重点：

```text
Router compile once
Middleware compile once
Application create once
DB connection pool
Cache connection pool
```

请求阶段尽量只做：

```text
Context
Match
Pipeline
Invoke
Response
```

避免每请求重复 `require`、解析路由、解析 Middleware、创建 DB Pool。

## 47. 安全要求

2.0 默认考虑：

- CORS
- CSRF
- Rate Limit
- Session Security
- Cookie Security
- Header Security
- SQL Injection
- Path Traversal
- Request Size
- File Upload
- Authentication
- Authorization

生产环境必须关闭 debug，异常不能泄露内部信息。

## 48. WebSocket

WebSocket 不进入 HTTP Controller 核心链，预留：

```text
websocket/
```

未来可以形成：

```text
WebSocket
 ↓
Context
 ↓
Middleware
 ↓
Handler
```

## 49. OpenAPI

P3 实现。Route 可以携带 metadata：

```lua
router:get(
    "/users/{id}",
    "User@show",
    {
        summary = "Get user",
        tags = {"users"}
    }
)
```

未来自动生成 OpenAPI / Swagger 文档。

## 50. CLI

P3 可增加：

```bash
tilua make:controller User
tilua make:service User
tilua make:repository User
tilua route:list
tilua cache:clear
tilua config:cache
```

## 51. 最终开发体验

业务代码最终只需要关注：

```text
Route
Controller
Service
Repository
```

框架负责：

```text
Request
Router
Middleware
DI
DB
Cache
Session
Logging
Exception
Response
```

## 52. 最终架构图

```text
                         ┌─────────────────┐
                         │    OpenResty    │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │ Tilua Runtime   │
                         └────────┬────────┘
                                  │
                 ┌────────────────┴────────────────┐
                 │                                 │
                 ▼                                 ▼
        ┌─────────────────┐              ┌─────────────────┐
        │   Application   │              │     Context     │
        │   Worker级      │              │    Request级    │
        └────────┬────────┘              └────────┬────────┘
                 │                                │
        ┌────────┼─────────┐                      │
        │        │         │                      │
        ▼        ▼         ▼                      ▼
     Config   Container  Router                Request
                          │                       │
                          ▼                       ▼
                     Middleware               Response
                          │
                          ▼
                     Controller
                          │
                          ▼
                       Service
                          │
                          ▼
                     Repository
                       │     │
                       ▼     ▼
                      DB    Cache
```

## 53. Tilua 2.0 十条铁律

1. **Application 管 Worker，Context 管 Request。**
2. **Router 只负责匹配，不保存当前请求状态。**
3. **Middleware 只负责请求管线。**
4. **Controller 不负责业务和数据库。**
5. **Service 不负责 HTTP。**
6. **Repository 不负责业务。**
7. **Database Manager 管连接，Transaction 管事务。**
8. **Cache 独立于 Model。**
9. **Response 只能在正确的请求阶段发送。**
10. **任何请求状态都不能进入 Worker 级共享变量。**

## 54. 当前实施状态与下一步

当前项目改造应严格按照 Phase 顺序推进。

已建立的 Core 基础：

```text
core/application.lua
core/context.lua
core/container.lua
core/lifecycle.lua
```

下一阶段优先完成 Router 2.0：

```text
router/router.lua
router/route.lua
router/compiler.lua
router/matcher.lua
router/trie.lua
```

Router 完成并通过 Unit / Integration 测试后，再进入 Middleware Pipeline 2.0。

不要在 Router 尚未真正落地前继续扩展上层 Controller / Service 功能，以避免架构返工。
