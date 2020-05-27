local app = require("Tilua.app").derive()

app.name = "Test"
app.path = "/usr/local/openresty/lua/Test/"
app.debug = true
app.status = 'dev'

function app:_init()
    self:super(self)
end

return app