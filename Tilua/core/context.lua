local class = require("Tilua.utils.class")

local Context = class.define()

function Context:_construct(app, request, response)
    self.app = app
    self.request = request
    self.response = response
    self.route = nil
    self.params = {}
    self.state = {}
    self.services = {}
    self.session = nil
    self.finished = false
    self.trace = {
        request_id = nil,
        trace_id = nil
    }
end

function Context:set_route(route)
    self.route = route
    if route and route.params then
        self.params = route.params
    end
    return self
end

function Context:set_param(name, value)
    self.params[name] = value
    return self
end

function Context:param(name, default)
    local value = self.params[name]
    if value == nil then return default end
    return value
end

function Context:set(name, value)
    self.state[name] = value
    return self
end

function Context:get(name, default)
    local value = self.state[name]
    if value == nil then return default end
    return value
end

function Context:has(name)
    return self.state[name] ~= nil
end

function Context:service(name, ...)
    if self.services[name] ~= nil then return self.services[name] end
    local service = self.app:make(name, ...)
    self.services[name] = service
    return service
end

-- Returns a request-scoped database connection, while the manager itself
-- remains application/worker scoped in the container.
function Context:db(name)
    local key = name and ("db.connection." .. name) or "db.connection"
    if self.services[key] then return self.services[key] end

    local manager = self.app:make("db")
    local connection = manager:connection(self, name)
    self.services[key] = connection
    return connection
end

function Context:transaction(name)
    local key = name and ("db.transaction." .. name) or "db.transaction"
    if self.services[key] then return self.services[key] end

    local manager = self.app:make("db")
    local transaction = manager:transaction(self, name)
    self.services[key] = transaction
    return transaction
end

function Context:cache()
    return self:service("cache")
end

function Context:session_manager()
    return self:service("session")
end

function Context:set_session(session)
    self.session = session
    return self
end

function Context:request_id()
    return self.trace.request_id
end

function Context:set_request_id(id)
    self.trace.request_id = id
    return self
end

function Context:trace_id()
    return self.trace.trace_id or self.trace.request_id
end

function Context:set_trace_id(id)
    self.trace.trace_id = id
    return self
end

function Context:json(data, status)
    return self.response:json(data, status)
end

function Context:text(data, status)
    return self.response:text(data, status)
end

function Context:html(data, status)
    return self.response:html(data, status)
end

function Context:redirect(url, status)
    return self.response:redirect(url, status)
end

function Context:finish()
    self.finished = true
    return self
end

function Context:is_finished()
    return self.finished
end

function Context:destroy()
    for _, service in pairs(self.services or {}) do
        if service.close then pcall(service.close, service) end
    end
    self.app = nil
    self.request = nil
    self.response = nil
    self.route = nil
    self.params = nil
    self.state = nil
    self.services = nil
    self.session = nil
    self.trace = nil
end

return Context
