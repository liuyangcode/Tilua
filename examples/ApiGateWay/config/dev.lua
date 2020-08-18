return {
    redis = {
        host = '32.254.64.119',
        port = 6379
    },
    route = {
    },
    db_type = 'mysql', -- 数据库类型
    db_host = '32.254.64.119', -- 服务器地址
    db_name = 'api', -- 数据库名
    db_user = 'app', -- 用户名
    db_pwd = 'app', -- 密码
    db_port = '3306', -- 端口
    db_debug = true,
    dispatch = 'ApiGateWay.dispatch',
    log = {
        level = "DEBUG,ERROR"
    },
    default_ssl_cert = 'cert/server-root.crt',
    default_ssl_key = 'cert/server.key'
}