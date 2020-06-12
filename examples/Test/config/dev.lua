return {
    redis = {
        host = '10.211.55.6',
        port = 6379
    },
    db_type = 'mysql', -- 数据库类型
    db_host = '10.211.55.6', -- 服务器地址
    db_name = 'test', -- 数据库名
    db_user = 'app', -- 用户名
    db_pwd = 'app', -- 密码
    db_port = '3306', -- 端口
    db_debug = true,
    app89 = "mysql://app:app@10.211.55.6:3306/test?debug=true#utf8",
    log = {
        level = "DEBUG,ERROR"
    }
}