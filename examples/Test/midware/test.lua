local test = require('Tilua.midware').derive()
test.alias = 'test'
function test:_init(ctx,config)
    self.config = config
    self:super(ctx)
end

function test:handle(next, ...)
    return next(...)
end

return test