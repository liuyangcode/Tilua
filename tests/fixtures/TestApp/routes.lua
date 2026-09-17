--- Fixture routes, exercising both registration styles the framework supports.
local route = require("Tilua.http.router")
local response = require("Tilua.http.response")

route.get("/", function()
    return response("home")
end)

route.get("/user/{name}", function(ctx, name)
    return response("hello " .. tostring(name))
end)

route.get("/greeter", function(ctx)
    return { marker = "GREETER", title = ctx:make("config").app_title }
end)

route.get("/text", function()
    return "TEXT-MARKER"
end)

route.get("/text-literal", function()
    return response("TEXT-MARKER")
end)

route.get("/view", function()
    -- second value is a table -> explicit view render (tests/fixtures/.../view/index.html)
    return "index", {
        title = "from view",
        marker = "VIEW-OK",
        unescaped_looking = "<b>&</b>",
    }
end)

route.get("/boom", function()
    error("intentional route failure")
end)

--- Parameter validation uses the DECLARATIVE rule form, because the third
--- whitespace-separated field of a rule is the `<param>:<op>,<value>` spec:
---   route["get /path/{p} p:reg,^[0-9]+$"] = handler
--- (The `route.get(path, handler, expr)` form treats a 3rd string as
--- middleware, so validation must be part of the rule key.)
route["get /num/{id} id:reg,^[0-9]+$"] = function(ctx, id)
    return response("numeric id=" .. tostring(id))
end

route["get /kind/{k} k:eq,ok"] = function(ctx, k)
    return response("kind=" .. tostring(k))
end

--- Full MVC pipeline: a bare action NAME as the handler.
---
--- The handler form matters.  `"index"` (no `@`) makes the dispatcher derive the
--- controller and action from the path and INSTANTIATE the controller, which is
--- what makes `assign` / `display` / `service` available.  The
--- `"<module>@<action>"` form calls the action on the class instead.
route.get("/mvc/index",   "index")
route.get("/mvc/mounted", "mounted")
route.get("/mvc/bare",    "bare")
route.get("/mvc/json",    "json")
route.get("/mvc/svc",     "svc")

--- Two routes sharing the SAME trie shape but different parameter names.  A
--- trie keeps one param slot per node, so the second declaration is shadowed
--- (a documented limitation); the point of these routes is that whichever one
--- wins must still receive its own captured value rather than nil.
route.get("/pair/{a}", function(ctx, a)
    return response("pair-a=" .. tostring(a))
end)
route.get("/pair/{b}", function(ctx, b)
    return response("pair-b=" .. tostring(b))
end)

--- Separate parents must keep separate parameter names.
route.get("/left/{x}", function(ctx, x)
    return response("left-x=" .. tostring(x))
end)
route.get("/right/{y}", function(ctx, y)
    return response("right-y=" .. tostring(y))
end)

--- view:assign() then render with no context table.
route.get("/view-assign", function(ctx)
    local view = ctx:make("view")
    view:assign("title", "assigned title")
    view:assign("marker", "ASSIGN-OK")
    view:assign("unescaped_looking", "<i>raw</i>")
    return view:render("index")
end)

--- Access-phase middleware is declared per-route, so it gates only /admin.
--- The 4th argument is the route's phase config; the 3rd is its content-phase
--- middleware list.
route.get("/admin", function()
    return response("admin area")
end, nil, { phases = { access = { "admin_guard" } } })

return function(app, router)
    -- also exercise the callback form the loader passes in
    router.get("/about", function()
        return response("about")
    end)
end
