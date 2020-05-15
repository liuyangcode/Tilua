local config = {
    data_cache_type = 'redis',
    data_cache_prefix = 'Tilua:',
    html_cache = true,
    html_cache_path = "html",
    html_cache_time = 60,
    html_cache_rules = {},
    html_cache_file_ext = '.html',
    midware_alias = {
        mvc = 'Tilua.midware.mvc_router',
        session = 'Tilua.midware.session',
        json = 'Tilua.midware.json_response',
        body_parser = 'Tilua.midware.body_parser',
        html_cache = 'Tilua.midware.html_cache'
    },
    midware_group = {
        api = {
            'session',
            'json'
        },
        mvc = {
            'body_parser',
            'session',
            'mvc',
            'json',
            'html_cache'
        }
    },
    bodyparser = {

    },
    log = {
        type = 'file',
        path = 'log',
        max_size = 2 * 1024 * 1024,
        level = 'DEBUG'
    },
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
    redis_pool_timeout = 60, --连接池配置 闲置时间 单位s
    redis_pool_size = 100, --连接池大小
    redis_host = '172.17.0.2',
    redis_port = 6379,
    redis_db_index = 0,

    default_charset = 'utf-8', --默认输出编码
    default_content_type = 'text/html', --默认输出编码

    dispatch = 'Tilua.dispatch',
    route = {
        ['/'] = "[mvc] /"
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
    db_deploy_type = 0, -- 数据库部署方式:0 集中式(单一服务器),1 分布式(主从服务器)
    db_rw_separate = false, -- 数据库读写是否分离 主从式有效
    db_master_num = 1, -- 读写分离后 主服务器数量
    db_slave_no = '', -- 指定从服务器序号

}

return config

