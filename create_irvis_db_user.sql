CREATE USER IF NOT EXISTS 'irvis_user'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON irvis.* TO 'irvis_user'@'localhost';
FLUSH PRIVILEGES;
