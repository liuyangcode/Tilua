local app = require("Tilua.app").derive()

app.name = "ApiDoc"
app.path = "/usr/local/openresty/lua/ApiDoc/"
app.debug = true
app.status = 'dev'

function app:_init()
    self:super(self)
end

return app