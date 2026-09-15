--- Session smoke tests (memory handler; no Redis required)
-- Note: requires ngx stub for memory handler timestamps when run outside OpenResty.
-- Under resty: resty -I Tilua/../ tests/test_session.lua

-- minimal ngx stub for pure-lua run
if not ngx then
    _G.ngx = {
        time = os.time,
        now = function() return os.time() + 0.1 end,
        md5 = function(s)
            -- weak stub
            return tostring(#s) .. tostring(s:byte(1) or 0)
        end,
        cookie_time = function(t) return tostring(t) end,
        worker = { pid = function() return 1 end },
        log = function() end,
    }
end

package.path = "./?.lua;./?/init.lua;" .. package.path

local session = require("Tilua.session")
local memory = require("Tilua.session.memory")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed") end
end

local handler = memory.new({ logger = { debug = function() end, error = function() end, record = function() end } })
local cfg = {
    name = "TESTSESS",
    use_cookies = true,
    use_only_cookies = true,
    lazy_write = 1,
    gc_maxlifetime = 60,
    gc_probability = 0,
    cookie_path = "/",
    cookie_http_only = true,
    save_handler = handler,
}

local fake_request = {
    cookie = {},
    header = {},
    body = {},
}

local sess = session(cfg, { logger = cfg.save_handler.log })
assert_true(sess:start(fake_request), "start ok")
assert_true(sess.id ~= nil and #sess.id >= 8, "id generated")
sess:set("user", "alice")
assert_true(sess:get("user") == "alice", "get user")
sess:close()

-- resume
fake_request.cookie.TESTSESS = sess.id
local sess2 = session(cfg, { logger = cfg.save_handler.log })
assert_true(sess2:start(fake_request), "resume start")
assert_true(sess2:get("user") == "alice", "session persisted in memory")

sess2:unset("user")
sess2:set("role", "admin")
sess2:close()

local sess3 = session(cfg, { logger = cfg.save_handler.log })
assert_true(sess3:start(fake_request), "resume 2")
assert_true(sess3:get("user") == nil, "unset works")
assert_true(sess3:get("role") == "admin", "role set")

assert_true(sess3:valid_key("abcd1234") == true)
assert_true(sess3:valid_key("") == false)
assert_true(sess3:valid_key("short") == false)

print("session smoke tests passed")
