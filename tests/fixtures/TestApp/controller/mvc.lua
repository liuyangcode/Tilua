--- Fixture controller for the full MVC pipeline.
---
--- Unlike `widget.lua` (which only checks discovery), this controller exercises
--- the runtime path end to end: instantiation, an action running, the controller
--- helpers (`assign` / `display`), and a view rendered with the merged context.
---
--- Reachable two ways, which is the point:
---   * `GET /mvc/index`      conventional path form — instantiates, so the
---                           controller helpers work
---   * no annotation, so discovery also exposes `GET /mvc/index`

local controller = require("Tilua.controller")

local Mvc = controller.define()

--- Renders view/mvc/index.html.
---
--- `assign` first, then `display` with an explicit table: the assigned value
--- must survive the render (it used to be discarded).
function Mvc:index()
    self:assign("title", "assigned title")
    self:assign("marker", "MVC-OK")
    return self:display("mvc/index", { from_action = "passed table" })
end

--- Renders a view whose name differs from the action, using mount_context for
--- a value that must survive `assign`.
function Mvc:mounted()
    self:mount_context("site", "MOUNTED-SITE")
    self:assign("marker", "MOUNT-OK")
    return self:display("mvc/mounted", { title = "mounted title" })
end

--- No explicit context at all: the assigned values are the whole context.
function Mvc:bare()
    self:assign("title", "bare title")
    self:assign("marker", "BARE-OK")
    return self:display("mvc/mounted")
end

--- Returns a table instead of rendering: proves a controller action is just a
--- handler, so JSON and views can coexist in one controller.
function Mvc:json()
    return { controller = "mvc", action = "json" }
end

--- Resolves an application service through `self:service(name)`.
---
--- `Tilua.service` loads lazily from `<App>/service/<Name>.lua` via an
--- overloaded `__index`, so this looks for `TestApp.service.greeter` — there is
--- no such module, and the manager falls back to an empty base service.  A
--- container BINDING is a different namespace: use `self.ctx:make("greeter")`.
--- Both are demonstrated so the difference stays visible.
function Mvc:svc()
    local from_service = self:service("greeter")
    local from_container = self.ctx:make("greeter")
    return {
        service_kind     = type(from_service),
        container_greeting = from_container and from_container.greet("service") or nil,
    }
end

return Mvc
