--- Smoke tests for Tilua.core.errors
local errors = require("Tilua.core.errors")

local function assert_true(cond, msg)
    if not cond then error(msg or "assert failed") end
end

local e = errors.not_found("gone")
assert_true(errors.is_error(e), "should be TiluaError")
assert_true(e.status == 404, "status 404")
assert_true(e.message == "gone", "message")

local e2 = errors.bad_request("bad", "invalid_input", { field = "name" })
assert_true(e2.status == 400)
assert_true(e2.code == "invalid_input")
assert_true(e2.details.field == "name")

local e3 = errors.internal("boom")
assert_true(e3.status == 500)

-- apply to mock response
local resp = { headers = {}, status = 0 }
errors.apply(resp, e, true)
assert_true(resp.status == 404)
assert_true(type(resp.body) == "string")
assert_true(resp.body:find("gone") ~= nil or resp.body:find("404") ~= nil)

print("errors smoke tests passed")
