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
    -- second value is a table -> explicit view render
    return "index", { title = "from view" }
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
