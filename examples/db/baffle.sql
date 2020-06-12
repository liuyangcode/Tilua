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

 Date: 11/06/2020 18:47:40
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for baffle
-- ----------------------------
DROP TABLE IF EXISTS `baffle`;
CREATE TABLE `baffle` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8 DEFAULT NULL,
  `header` varchar(255) DEFAULT NULL,
  `body` text CHARACTER SET utf8,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `status` int(1) DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=latin1;

SET FOREIGN_KEY_CHECKS = 1;
