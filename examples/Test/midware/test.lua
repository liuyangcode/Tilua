local test = require('Tilua.midware').derive()
function test:_init(ctx)
    self:super(ctx)
end

function test:handle(next, request, ...)
    return next(request, ...)
end

return test