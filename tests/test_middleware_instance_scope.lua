--- Regression: middleware instances must be bound to the request that uses them.
---
--- `Tilua.middleware.instance()` memoised instances in a cache keyed only by the
--- middleware reference, and built them with the manager's own `self.ctx`.  The
--- manager is the worker-scoped container singleton "middleware", created during
--- worker boot, so `self.ctx` is the boot/class context forever — every request
--- re-entered the middleware with a stale ctx (and the cache made the first
--- request's instance permanent).
---
--- Middleware keep per-request state on `self` (mvc_router stores
--- controller/action, session stores the session handle, guards store their
--- ctx), so this is a real cross-request leak: the same defect class as the
--- dispatcher's old cached `self.ctx`.
---
--- This test resolves the same middleware reference for two different request
--- contexts through the same manager and asserts each instance sees its own.

local mw = require("Tilua.middleware")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s (expected %s, got %s)",
            msg or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

mw.load({ middleware_phases = { content = {} } })

-- The manager is a *singleton*, created once per worker with the boot context.
local boot_ctx = { name = "TestApp", tag = "boot" }
local manager  = mw(boot_ctx)

local ctx_a = { name = "TestApp", tag = "A" }
local ctx_b = { name = "TestApp", tag = "B" }

-- A real fixture middleware that stores `self.ctx = ctx` (admin_guard).
local REF = "TestApp.middleware.admin_guard"

local mid_a = manager:instance({ REF }, ctx_a)
assert_eq(mid_a.ctx, ctx_a, "request A must get an instance bound to ctx A")

local mid_b = manager:instance({ REF }, ctx_b)
assert_eq(mid_b.ctx, ctx_b, "request B must get an instance bound to ctx B")
assert_eq(mid_b.ctx.tag, "B", "request B's instance must not see request A")

print("middleware instance-scope tests passed")
