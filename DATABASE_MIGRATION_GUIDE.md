# IRVIS Database Backup and Migration Guide

This directory contains several files to help you backup and restore the IRVIS database on another machine.

## Files Created

1. **`irvis_database_backup.sql`** - Hand-crafted SQL script with current database structure and data
2. **`irvis_mysqldump_backup.sql`** - Complete mysqldump backup with all MySQL metadata
3. **`backup_restore_irvis.sh`** - Automated backup and restore script

## Current Database Schema

The IRVIS database contains one table: `users`

```sql
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
```

## Current Data

The database contains 2 users:
- **steve** (steve.carr@wmich.edu) - Admin user
- **jean** (jmayo@mtu.edu) - Admin user

## Migration Options

### Option 1: Using the Hand-crafted SQL Script (Recommended for new installations)

```bash
# On the target machine:
mysql -u root -p < irvis_database_backup.sql
```

### Option 2: Using mysqldump Backup (Recommended for exact replication)

```bash
# On the target machine:
mysql -u root -p < irvis_mysqldump_backup.sql
```

### Option 3: Using the Automated Script

```bash
# Make executable (if not already):
chmod +x backup_restore_irvis.sh

# Create a new backup:
./backup_restore_irvis.sh backup

# Restore from backup:
./backup_restore_irvis.sh restore <backup_file>

# Test connections:
./backup_restore_irvis.sh test
```

## Prerequisites on Target Machine

1. **MySQL Server** must be installed and running
2. **Root access** to MySQL
3. **MySQL client tools** (mysql, mysqldump)

## Post-Migration Steps

1. **Verify the database:**
   ```bash
   mysql -u irvis_user -ppassword -D irvis -e "SELECT username, email, is_admin FROM users;"
   ```

2. **Test the Go application:**
   - Update the database connection string in your `.env` file if needed
   - Run the Go server: `go run cmd/server/main.go`
   - Test login with existing users

3. **Security considerations:**
   - Change the default password for `irvis_user`
   - Consider creating new admin passwords for security

## Database Connection Details

- **Database Name:** `irvis`
- **Username:** `irvis_user`
- **Password:** `password` (change this for production!)
- **Host:** `localhost`

## Environment Variables

Make sure your `.env` file on the new machine contains:

```env
DB_HOST=localhost
DB_PORT=3306
DB_USER=irvis_user
DB_PASSWORD=password
DB_NAME=irvis
```

## Troubleshooting

1. **Connection denied errors:**
   - Ensure MySQL is running: `sudo systemctl status mysql`
   - Check user privileges: `SHOW GRANTS FOR 'irvis_user'@'localhost';`

2. **Database doesn't exist:**
   - Verify database creation: `SHOW DATABASES;`
   - Check if irvis database exists: `USE irvis; SHOW TABLES;`

3. **Authentication issues:**
   - Reset user password: `ALTER USER 'irvis_user'@'localhost' IDENTIFIED BY 'newpassword';`
   - Update `.env` file with new password