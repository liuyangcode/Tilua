
local config = {
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
    redis_db_index = 0,


    route_filter = 'Tilua.route',
    dispatch = 'Tilua.dispatch',
    route = {},
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
    db_deploy_type = 0, -- 数据库部署方式:0 集中式(单一服务器),1 分布式(主从服务器)
    db_rw_separate = false, -- 数据库读写是否分离 主从式有效
    db_master_num = 1, -- 读写分离后 主服务器数量
    db_slave_no = '', -- 指定从服务器序号

}

return config

