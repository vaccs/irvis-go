-- ============================================================
-- IRVIS Database Complete Backup Script
-- Generated on: October 14, 2025
-- This script recreates the complete irvis database with all data
-- ============================================================

-- Create the database
CREATE DATABASE IF NOT EXISTS irvis;
USE irvis;

-- ============================================================
-- Table structure for table `users`
-- ============================================================

DROP TABLE IF EXISTS `users`;

CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `email` varchar(255) NOT NULL,
  `hashed_password` varchar(255) NOT NULL,
  `is_logged_in` tinyint(1) NOT NULL DEFAULT '0',
  `is_admin` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ============================================================
-- Dumping data for table `users`
-- ============================================================

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;

INSERT INTO `users` (`id`, `username`, `email`, `hashed_password`, `is_logged_in`, `is_admin`) VALUES
(2, 'steve', 'steve.carr@wmich.edu', 'f25390ec361b0fea72acb069f4ffac759e465c5fe82af4dbe63e1dd1db362040', 0, 1),
(3, 'jean', 'jmayo@mtu.edu', '644b7b79714b5f4a35a4242eb6049852585b332f3eef014b8839060c0db0f1b5', 0, 1);

/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

-- ============================================================
-- Create database user and grant privileges
-- Note: Run this section as MySQL root user
-- ============================================================

-- Create the irvis_user account
CREATE USER IF NOT EXISTS 'irvis_user'@'localhost' IDENTIFIED BY 'password';

-- Grant all privileges on the irvis database to irvis_user
GRANT ALL PRIVILEGES ON irvis.* TO 'irvis_user'@'localhost';

-- Apply the privilege changes
FLUSH PRIVILEGES;

-- ============================================================
-- Verification queries (optional)
-- ============================================================

-- Check that the table was created correctly
-- SELECT COUNT(*) as total_users FROM users;
-- SELECT username, email, is_admin FROM users;

-- ============================================================
-- Instructions for use:
-- 
-- 1. Copy this file to the target machine
-- 2. Run: mysql -u root -p < irvis_database_backup.sql
-- 3. Verify the database was created: mysql -u irvis_user -ppassword -D irvis -e "SELECT * FROM users;"
-- 
-- Note: Make sure MySQL is installed and running on the target machine
-- ============================================================