# Tilua
a simple mvc lua web development kit based on [openresty](https://openresty.org/)
# Status
Pruduction not ready
# Dependencies
* [lua-resty-template](https://github.com/bungle/lua-resty-template)
* [lua-resty-redis](https://github.com/bungle/lua-resty-redis)
* [lua-resty-mysql](https://github.com/bungle/lua-resty-mysql)
* [Penlight - A Portable Lua Library](http://www.penlight.luaforge.net/)
# Demo
nginx/8001.conf
```nginx
lua_package_path '$prefix/../lua/?.lua;$prefix/../lualib/?.lua;;';
lua_shared_dict app_test_cache 10m;
server {
        listen 8001;
        location ~/.*\.(css|js|jpg|jpeg|png).*$ {
                root /var/web;
                add_header Access-Control-Allow-Origin *;
                keepalive_timeout  0;
                expires 7d;
        }
        location / {
                lua_code_cache off;
                content_by_lua_block {
                    require "Test.app"():run()
                }
        }
}
```
Test/app.lua
```lua
local app = require("Tilua.app").derive() 

function app:_init()
    self.module = 'Home'
    self.app_name = "Test"
    self.app_path = "/usr/local/openresty/lua/Test/"
    self.debug = true
    self:super(self)
end
return app
```
路由模式
Test/routes.lua
```lua
local route = require('Tilua.route')
local response = require('Tilua.response')
route.get('/', function()
    return response('hello world!')
end)
route.get('/user/welcome/{name}', function(request,name)
    return response('welcome '..name..'!')
end)
```

控制器模式
Test/Home/controller/index.lua
```lua
local index = require("Tilua.controller").derive()

function index:_init(...)
    self:super(...)
end

function index:index(request,name)
    return 'welcome,'..name
end
return index
```


## License and Copyright

This code is Licensed under the Apache License, Version 2.0

Copyright (C) 2020, by pcode <pcode@sina.com> All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
* Neither the name of the <ORGANIZATION> nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
