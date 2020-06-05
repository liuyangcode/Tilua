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

 Date: 03/06/2020 17:08:09
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for targets
-- ----------------------------
DROP TABLE IF EXISTS `targets`;
CREATE TABLE `targets` (
  `id` int(10) NOT NULL,
  `host` varchar(255) NOT NULL,
  `port` int(6) NOT NULL,
  `weight` int(5) NOT NULL,
  `upstreamid` int(10) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `upstream` (`upstreamid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

SET FOREIGN_KEY_CHECKS = 1;
