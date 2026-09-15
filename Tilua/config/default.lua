local config = {
    html_cache = true,
    html_cache_path = "html",
    html_cache_time = 60,
    html_cache_rules = {},
    html_cache_file_ext = '.html',
    -- Preferred new keys (middleware_*) + legacy keys (midware_*) for compatibility
    middleware_alias = {
        mvc         = 'Tilua.middleware.mvc_router',
        session     = 'Tilua.middleware.session',
        json        = 'Tilua.middleware.json_response',
        body_parser = 'Tilua.middleware.body_parser',
        html_cache  = 'Tilua.middleware.html_cache',
        csrf        = 'Tilua.middleware.csrf_token',
    },
    midware_alias = {  -- legacy alias
        mvc         = 'Tilua.middleware.mvc_router',
        session     = 'Tilua.middleware.session',
        json        = 'Tilua.middleware.json_response',
        body_parser = 'Tilua.middleware.body_parser',
        html_cache  = 'Tilua.middleware.html_cache',
        csrf        = 'Tilua.middleware.csrf_token',
    },
    middleware_group = {
        api = { 'session', 'json' },
        web = { 'body_parser', 'session', 'json', 'html_cache' },
    },
    midware_group = {  -- legacy
        api = { 'session', 'json' },
        web = { 'body_parser', 'session', 'json', 'html_cache' },
    },

    bodyparser = {

    },
    log = {
        type = 'file',
        path = 'log',
        max_size = 2 * 1024 * 1024,
        -- Prefer INFO or WARN in production
        level = 'DEBUG'
    },
    -- Production-oriented defaults (override in app config)
    request_timeout = 60,          -- seconds hint for upstream / app logic
    body_read_timeout = 10,
    enable_json_errors = false,    -- set true for API apps
    health_path = '/health',

    multipart = {
        field_name_size = 100,
        field_size = '100kb',
        field_value_size_in_memory = '1kb',
        fields = 10,
        file_size = '10mb',
        files = 10,
        file_extensions = {},
        whitelist = {
            '.jpg',
            '.jpeg', '.png', '.gif', '.bmp', '.wbmp', '.webp', '.tif', '.psd', '.svg', '.js', '.jsx',
            '.json',
            '.css', '.less',
            '.html', '.htm',
            '.xml',
            '.zip',
            '.gz', '.tgz', '.gzip',
            '.mp3',
            '.mp4',
            '.avi',
            '.txt'
        },
        chunk_size = 1024,
        tmpdir = '/tmp/Tilua-multipart-tmp/'
    },
    data_cache_handler = 'redis',
    redis = {
        pool_timeout = 60, --连接池配置 闲置时间 单位s
        pool_size = 1000, --连接池大小
        host = '172.17.0.2',
        port = 6379,
        db_index = 0,
        timeout = 2000,
        prefix = 'Tilua:',
        driver = 'Tilua.cache.driver.redis'
    },
    default_charset = 'utf-8', --默认输出编码
    default_content_type = 'text/html', --默认输出编码
    dispatch = 'Tilua.http.dispatcher',  -- new canonical path (shim still works)

    route = {
    },
    SHDICIT_NAME = 'app_test_cache',
    db_type = 'mysql', -- 数据库类型
    db_host = '', -- 服务器地址
    db_name = '', -- 数据库名
    db_user = '', -- 用户名
    db_pwd = '', -- 密码
    db_port = '', -- 端口
    db_prefix = 'Tilua', -- 数据库表前缀
    db_debug = true, -- 数据库调试模式 开启后可以记录SQL日志
    db_fields_cache = true, -- 启用字段缓存
    db_fields_cache_type = 'redis',
    db_fields_cache_prefix = 'Tilua:',
    db_charset = 'utf8', -- 数据库编码默认采用utf8

    -- Extension plugins: "Tilua.openapi", "Tilua.cli", "Tilua.websocket"
    plugins = {},
    health_path = "/health",
}


return config

