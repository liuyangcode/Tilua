
local config = {
    app_name = "app name",
    view_dir = '',


    default_ajax_return = "JSON",

    data_cache_prefix = 'Tilua:',
    html_cache = true,
    html_cache_path = "html",
    html_cache_time = 60,
    html_cache_rules = {},
    html_cache_file_ext = '.html',
    default_midware = {
        'Tilua.midware.session'
    },
    session = {
        use_strict_mode = true,
        use_cookies = true,
        gc_maxlifetime = 300,
        gc_divisor = 100,
        name = 'ACCESSTOKEN',
        save_handler = 'Tilua.session.session_redis_hanler',
        serialize_handler = nil,
        use_only_cookies = true,
        referer_check = "",
        lazy_write = 1, --延迟写入
        gc_probability = 1,
        cookie_path = '/',
        cookie_domain = 'centos-7',
        cookie_expires = 30,
        cookie_http_only = true
    },
    redis_pool_timeout = 60, --连接池配置 闲置时间 单位s
    redis_pool_size = 100, --连接池大小
    redis_host = '172.17.0.2',
    redis_port = 6379,

    route_filter = 'Tilua.route',
    dispatch = 'Tilua.dispatch',
    route = {},
    SHDICIT_NAME = 'app_test_cache',
    DB_TYPE = 'mysql', -- 数据库类型
    DB_HOST = '', -- 服务器地址
    DB_NAME = '', -- 数据库名
    DB_USER = '', -- 用户名
    DB_PWD = '', -- 密码
    DB_PORT = '', -- 端口
    DB_PREFIX = 'Tilua', -- 数据库表前缀
    DB_PARAMS = {}, -- 数据库连接参数
    DB_DEBUG = true, -- 数据库调试模式 开启后可以记录SQL日志
    DB_FIELDS_CACHE = true, -- 启用字段缓存
    DB_FIELDS_CACHE_TYPE = 'redis',
    DB_FIELDS_CACHE_PREFIX = 'Tilua:',

    DB_CHARSET = 'utf8', -- 数据库编码默认采用utf8
    DB_DEPLOY_TYPE = 0, -- 数据库部署方式:0 集中式(单一服务器),1 分布式(主从服务器)
    DB_RW_SEPARATE = false, -- 数据库读写是否分离 主从式有效
    DB_MASTER_NUM = 1, -- 读写分离后 主服务器数量
    DB_SLAVE_NO = '', -- 指定从服务器序号

}

return config

