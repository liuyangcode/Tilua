local test = require('Tilua.midware').derive()
function test:_init(ctx)
    self:super(ctx)
end

function test:handle(next, ...)
    return next(...)
end

return test