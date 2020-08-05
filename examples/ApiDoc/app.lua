local app = require("Tilua.app").derive()

app.name = "ApiDoc"
app.debug = true
app.status = 'dev'

function app:_init()
    self:super(self)
end

return app