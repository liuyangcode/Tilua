local route = require("Tilua.route")

route {
    ['=/api/v2'] = function(ctx)
        ---@type response
        local response = ctx.response
        response.body = ngx.config.subsystem
        --response.cookie = {
        --    name = 'username',
        --    value = 'liuyang'
        --}
        --response.cookie = {
        --    name = 'username',
        --    value = 'liuyang2'
        --}
    end
}

--route['=/api/v2'] = function(ctx)
--    local http = require "resty.http"
--    local httpc = http.new()
--
--    httpc:set_timeout(500)
--    local ok, err = httpc:connect('32.254.48.88', 80)
--
--    if not ok then
--        ngx.log(ngx.ERR, err)
--        return
--    end
--    httpc:set_timeout(2000)
--    httpc:proxy_response(httpc:proxy_request())
--    httpc:set_keepalive()
--end

route.get('~/user/get/{uid}', function(ctx, uid)
    local user = ctx.model.user
    local data = user:save({
        name = "刘洋2"
    }, {
        where = {
            uid = { 'eq', uid }
        },
        limit = 1
    })
    ctx.response.body = user:getLastSql()
end, "[api]")

route.rest('/posts', 'controller.posts')

route.get('/user/login.html', function(ctx)
    local request, response = ctx:unpack()
    response:render('index/login.html')
end)

route.get('~/user/find/{uid}/{name}', function(ctx, uid, name)
    ctx.response.body = { uid, name, ctx.midware.test.config }
end, { { 'Test.midware.test', { a = 1, b = 1 } }, 'json' })

