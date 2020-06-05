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

 Date: 04/06/2020 16:16:14
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for upstreams
-- ----------------------------
DROP TABLE IF EXISTS `upstreams`;
CREATE TABLE `upstreams` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `algorithm` varchar(255) NOT NULL,
  `name` varchar(255) CHARACTER SET utf8 NOT NULL,
  `hash_on` varchar(255) NOT NULL,
  `slots` int(6) DEFAULT '10000',
  `hash_on_header` varchar(255) DEFAULT NULL,
  `hash_fallback` varchar(255) DEFAULT NULL,
  `hash_on_cookie` varchar(255) DEFAULT NULL,
  `hash_on_cookie_path` varchar(255) DEFAULT NULL,
  `host_header` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `hash_fallback_header` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `upstreams_index` (`name`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

SET FOREIGN_KEY_CHECKS = 1;
