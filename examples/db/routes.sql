/*
 Navicat Premium Data Transfer

 Source Server         : openresty
 Source Server Type    : MariaDB
 Source Server Version : 50564
 Source Host           : openresty:3306
 Source Schema         : test

 Target Server Type    : MariaDB
 Target Server Version : 50564
 File Encoding         : 65001

 Date: 17/05/2020 16:30:57
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for routes
-- ----------------------------
DROP TABLE IF EXISTS `routes`;
CREATE TABLE `routes` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `protocols` varchar(255) DEFAULT NULL COMMENT 'http',
  `methods` varchar(255) DEFAULT NULL COMMENT 'get,post',
  `hosts` varchar(255) DEFAULT NULL,
  `paths` varchar(255) DEFAULT NULL,
  `headers` varchar(255) DEFAULT NULL,
  `service` int(10) DEFAULT NULL COMMENT '关联的服务',
  `strip_path` int(1) DEFAULT '0' COMMENT '匹配到路由时是否删除前缀，默认不删除',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

SET FOREIGN_KEY_CHECKS = 1;
