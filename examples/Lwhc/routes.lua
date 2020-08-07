local route = require("Tilua.route")
local lw_util = require("Tilua.utils.util")

local session = { 'session', {
    --cookie_domain = '32.254.48.92'
} }

--local html_cache = {
--    'html_cache',
--    {
--        type = 'redis',
--        --suffix = '.html',
--        enable = true,
--        lifetime = 3600,
--        rules = {
--            --['get /user/login'] = 'user-login',
--            ['get /record/view/{certNo}/{id}'] = 'record-view-$certNo-$id',
--            ['get /record/index/record'] = function(ctx)
--                return ctx.session:get('user').uname .. 'record-list-' .. ctx.request.body.page .. '-' .. ctx.request.body.limit
--            end
--        }
--    }
--}
--route.prefix('/', { html_cache })
local mid = { session, 'body_parser', 'json', 'Lwhc.midware.session_check' }
route.get('=/', function(ctx)
    local user = ctx.session:get('user')
    return 'index.html', {
        url = ctx.request.body.url or '/record/list/current',
        name = user.name
    }
end, mid)

route['~/user/{action}'] = {
    res = 'controller.user@$action',
    mid = { 'body_parser', session, 'csrf' }
}

--route['~^/user/login$'] = 'body_parser controller.user@login'

route['~/record/{action}'] = {
    res = 'controller.record@$action',
    mid = mid
}
--route.group(function()
--    route {
--        ['~/record/{action}'] = 'controller.record@$action'
--    }
--end, mid)
