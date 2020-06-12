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

 Date: 12/06/2020 18:56:59
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for routes_plugins
-- ----------------------------
DROP TABLE IF EXISTS `routes_plugins`;
CREATE TABLE `routes_plugins` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `routeid` int(10) DEFAULT NULL,
  `mid` int(10) DEFAULT NULL,
  `config` text CHARACTER SET utf8,
  `status` int(1) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `routes_plugins_index` (`routeid`,`mid`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;

SET FOREIGN_KEY_CHECKS = 1;
