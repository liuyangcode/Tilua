local app = require("Tilua.app").derive()

app.name = "Test"
app.debug = true
app.status = 'dev'

function app:_init()
    self:super(self)
end

return app