package.path = "./?.lua;./?/init.lua;" .. package.path

local Router = require("Tilua.router.router")

local router = Router()
router:get("/", function() return "root" end, nil, { name = "home" })
router:get("/users", function() return "users" end)
router:get("/users/{id}", function(ctx) return ctx.params.id end)
router:post("/users", function() return "created" end)
router:get("/files/*", function(ctx) return ctx.params.wildcard end)

local result = assert(router:match("GET", "/"))
assert(result.route.name == "home")

result = assert(router:match("GET", "/users/123"))
assert(result.params.id == "123")

result = assert(router:match("GET", "/files/a/b.txt"))
assert(result.params.wildcard == "a/b.txt")

result = assert(router:match("POST", "/users"))
assert(result.route.handler ~= nil)

local _, err = router:match("DELETE", "/users")
assert(err == "method_not_allowed")

local _, not_found = router:match("GET", "/missing")
assert(not_found == "not_found")

print("router_spec: ok")
