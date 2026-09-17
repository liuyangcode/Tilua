--- Api application entry point.
---
--- Shows the container-based style: the application *is* an IoC container, so
--- services are registered rather than looked up through globals.

local App = require("Tilua.app").define()

--- Class fields (read by the constructor before `_construct` runs).
App.name   = "Api"
App.status = "dev"
App.debug  = true

--- Worker-lifetime singletons (shared by every request).
function App:_construct(opts)
    --- A tiny in-memory store so the example needs no database.
    ---
    --- `singleton` = one instance per worker.  It survives across requests,
    --- which is exactly what a datastore stub needs.  Swap this binding for a
    --- real repository and nothing else has to change.
    self:singleton("todo_store", function(c)
        local items, next_id = {}, 1

        local store = {}

        function store:all()
            local out = {}
            for _, v in ipairs(items) do
                out[#out + 1] = v
            end
            return out
        end

        function store:get(id)
            for _, v in ipairs(items) do
                if v.id == id then
                    return v
                end
            end
            return nil
        end

        function store:add(title)
            local todo = {
                id        = next_id,
                title     = tostring(title),
                done      = false,
                created_at = ngx.time(),
            }
            next_id = next_id + 1
            items[#items + 1] = todo
            return todo
        end

        function store:remove(id)
            for i, v in ipairs(items) do
                if v.id == id then
                    table.remove(items, i)
                    return true
                end
            end
            return false
        end

        function store:count()
            return #items
        end

        return store
    end)

    --- Worker boot timestamp, used for the uptime figure.
    self:singleton("boot_time", function()
        return ngx.now()
    end)

    --- A REQUEST-SCOPED service.
    ---
    --- `scoped` = one instance per request, released by the container when the
    --- request ends (App:flush_scope from log_by_lua).  `close()` is called on
    --- release if the object defines it, which is where you would flush
    --- buffers, return a connection to a pool, and so on.
    self:scoped("request_log", function(c)
        local entries = {}
        return {
            add = function(what)
                entries[#entries + 1] = what
            end,
            entries = entries,
            close = function()
                -- Runs at end of request.  Nothing to assert here; the demo is
                -- that this is called exactly once per request, not per worker.
                c.logger:debug("request_log released with ", #entries, " entries")
            end,
        }
    end)

    return self
end

return App
