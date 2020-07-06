local route = require("Tilua.route")
local lw_util = require("Tilua.util")

local session = { 'session', {
    --cookie_domain = '32.254.48.92'
} }
route.prefix('/user/', 'body_parser', session, 'csrf')
local mid = { session, 'body_parser', 'json', 'Lwhc.midware.session_check' }
route.get('/', function(ctx)
    local user = ctx.session:get('user')
    return 'index.html', {
        url = ctx.request.body.url or '/record/list/current',
        name = user.name
    }
end, mid)

route {
    ['~/user/{action}'] = 'controller.user@$action'
}

route.group(function()
    route {
        ['~/record/{action}'] = 'controller.record@$action'
    }
end, mid)
