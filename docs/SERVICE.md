# Service 层

业务逻辑放在 Service，Controller 只做参数/响应，Model 只做数据访问。

```
Controller  →  Service  →  Model / DB / Cache
```

## 定义应用 Service

`<app>/service/User.lua`:

```lua
local Base = require("Tilua.service.base")
local UserService = Base.define()

function UserService:create(payload)
    local ok, data = self:validate(payload)
    if not ok then
        return nil, data
    end
    return self:transaction(function()
        return self:model("User"):data(data):add()
    end)
end

function UserService:find_active(id)
    return self:model("User"):where({ status = 1 }):find(id)
end

return UserService
```

## 在 Controller 中使用

```lua
function UserController:store()
    local svc = self:service("User")
    local id, err = svc:create(self.ctx.request:input())
    if not id then
        return self.ctx.response:json({ error = err }, 400)
    end
    return self.ctx.response:json({ id = id }, 201)
end
```

或：

```lua
self.ctx.service.User:find_active(1)
```

## Base API

| 方法 | 说明 |
|------|------|
| `self:model("Name")` | 取模型 |
| `self:db()` / `self:cache()` | 基础设施 |
| `self:config(key)` | 配置 |
| `self:logger()` | 日志 |
| `self:transaction(fn)` | 事务包装 |
| `self:validate(data, rules)` | 可覆盖校验 |

## 注册自定义实例

```lua
ctx.service:register("Billing", my_billing_instance)
```
