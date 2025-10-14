# IRVIS Application Deployment Guide

This guide explains how to deploy the IRVIS Go application to a production server using the automated installation script.

## Prerequisites

Before running the installation script, ensure the following are installed on your target system:

### Required Software
- **Go** (version 1.19 or later)
- **Flutter** (latest stable version)
- **MySQL Server** (running and configured)
- **Apache2** (with mod_ssl, mod_proxy modules)
- **OpenSSL** (for SSL certificate generation)
- **Git** (for cloning repositories)

### System Requirements
- **Operating System**: Ubuntu/Debian Linux (with systemd)
- **User Privileges**: Root/sudo access required for installation
- **Network**: Internet access for downloading dependencies
- **Ports**: 80 (HTTP), 443 (HTTPS), and 8083 (internal Go app) should be available

## Installation Process

### 1. Prepare the Environment

```bash
# Clone the IRVIS Go repository
git clone https://github.com/vaccs/irvis-go.git
cd irvis-go

# Ensure Flutter project is available
# The script expects the Flutter project at ~/irvis_flutter
# Update the FLUTTER_DIR variable in install_irvis.sh if your path is different
```

### 2. Configure the Application

```bash
# Copy the environment template
cp .env.example .env

# Edit the configuration file
nano .env
```

Update the following variables in `.env`:
```env
DB_HOST=localhost
DB_PORT=3306
DB_USER=irvis_user
DB_PASSWORD=your_secure_password
DB_NAME=irvis
GITHUB_TOKEN=your_github_token_here
PORT=8083
HTTPS_PORT=8444
TLS_CERT_FILE=server.crt
TLS_KEY_FILE=server.key
```

### 3. Set Up the Database

```bash
# Import the database schema and data
mysql -u root -p < irvis_database_backup.sql

# Or use the automated backup script
./backup_restore_irvis.sh restore irvis_database_backup.sql
```

### 4. Run the Installation Script

```bash
# Make sure the script is executable
chmod +x install_irvis.sh

# Run the installation (requires sudo)
sudo ./install_irvis.sh
```

## What the Installation Script Does

The `install_irvis.sh` script performs the following steps:

### 1. **Prerequisites Check**
- Verifies Go and Flutter are installed
- Checks if MySQL is running
- Validates Flutter project directory exists

### 2. **Build Flutter Web Application**
- Runs `flutter build web --base-href "/irvis/visual/"`
- Copies build output to the `visual/` directory

### 3. **Compile Go Application**
- Builds the Go application: `go build -o irvis_go ./cmd/server`
- Creates optimized binary for production

### 4. **Install Files**
- Creates `/var/www/html/irvis/` directory
- Copies Go binary, HTML files, Flutter web app
- Copies SSL certificates and environment configuration
- Sets proper file permissions and ownership

### 5. **Create Systemd Service**
- Creates `/etc/systemd/system/irvis-go.service`
- Configures service to run as `www-data` user
- Enables automatic startup on boot
- Includes security hardening settings

### 6. **Configure Apache2**
- Enables required Apache modules (ssl, proxy, proxy_http, headers, rewrite)
- Creates self-signed SSL certificate if needed
- Creates virtual host configuration with HTTPS proxy
- Redirects HTTP to HTTPS automatically
- Configures security headers

### 7. **Start the Service**
- Starts the IRVIS service
- Verifies successful startup
- Displays service status

## Post-Installation

### Service Management

```bash
# Check service status
sudo systemctl status irvis-go

# Start/stop/restart service
sudo systemctl start irvis-go
sudo systemctl stop irvis-go
sudo systemctl restart irvis-go

# View logs
sudo journalctl -u irvis-go -f
```

### Access the Application

- **HTTP**: `http://your-server/irvis` (automatically redirects to HTTPS)
- **HTTPS**: `https://your-server/irvis` (main access point)
- **Direct**: `http://your-server:8083/irvis` (direct Go app access)

### Configuration Files

- **Application**: `/var/www/html/irvis/`
- **Environment**: `/var/www/html/irvis/.env`
- **Service**: `/etc/systemd/system/irvis-go.service`
- **Apache Site**: `/etc/apache2/sites-available/irvis.conf`
- **SSL Certificate**: `/etc/ssl/certs/irvis.crt`
- **SSL Private Key**: `/etc/ssl/private/irvis.key`
- **App Logs**: `journalctl -u irvis-go`
- **Apache Logs**: `/var/log/apache2/irvis_access.log`, `/var/log/apache2/irvis_error.log`

## Uninstallation

To remove the IRVIS application:

```bash
# Run the uninstall script
sudo ./uninstall_irvis.sh
```

This will:
- Stop and remove the systemd service
- Remove Apache virtual host configuration
- Optionally remove SSL certificates
- Delete all application files from `/var/www/html/irvis/`
- Leave database and source code intact

## Troubleshooting

### Service Won't Start
```bash
# Check logs for errors
sudo journalctl -u irvis-go -n 50

# Verify permissions
ls -la /var/www/html/irvis/

# Test configuration
cd /var/www/html/irvis
sudo -u www-data ./irvis_go
```

### Database Connection Issues
```bash
# Test database connection
mysql -u irvis_user -p -D irvis -e "SELECT COUNT(*) FROM users;"

# Check environment file
cat /var/www/html/irvis/.env
```

### Port Conflicts
```bash
# Check what's using the ports
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443
sudo netstat -tlnp | grep :8083

# Update port in .env file and restart service
sudo systemctl restart irvis-go
```

### Apache Issues
```bash
# Check Apache status
sudo systemctl status apache2

# Test Apache configuration
sudo apache2ctl configtest

# Check Apache error logs
sudo tail -f /var/log/apache2/irvis_error.log

# Restart Apache
sudo systemctl restart apache2
```

### Permission Issues
```bash
# Fix file ownership
sudo chown -R www-data:www-data /var/www/html/irvis/

# Fix permissions
sudo chmod -R 755 /var/www/html/irvis/
sudo chmod 600 /var/www/html/irvis/.env
```

## Security Considerations

1. **Change default passwords** in `.env` file
2. **Configure firewall** to restrict access to necessary ports
3. **Use HTTPS** in production with valid SSL certificates
4. **Regular updates** of dependencies and system packages
5. **Monitor logs** for suspicious activity
6. **Backup database** regularly

## Apache2 Integration (Automatic)

The installation script automatically configures Apache2 with:

### Features Configured
- **HTTPS Proxy**: Proxies `/irvis` requests to Go app on port 8083
- **HTTP to HTTPS Redirect**: All HTTP requests redirect to HTTPS
- **SSL/TLS**: Self-signed certificate created automatically
- **Security Headers**: HSTS, X-Frame-Options, X-Content-Type-Options
- **Logging**: Dedicated access and error logs

### Manual Apache Configuration (if needed)
```apache
<VirtualHost *:443>
    ServerName your-domain.com
    
    SSLEngine on
    SSLCertificateFile /path/to/your/certificate.crt
    SSLCertificateKeyFile /path/to/your/private.key
    
    ProxyPreserveHost On
    ProxyPass /irvis http://127.0.0.1:8083/irvis
    ProxyPassReverse /irvis http://127.0.0.1:8083/irvis
    
    # Security headers
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set X-Frame-Options DENY
    Header always set X-Content-Type-Options nosniff
</VirtualHost>
```

### Using Custom SSL Certificates
To replace the self-signed certificate with a proper SSL certificate:

```bash
# Stop Apache
sudo systemctl stop apache2

# Replace certificates
sudo cp your-certificate.crt /etc/ssl/certs/irvis.crt
sudo cp your-private-key.key /etc/ssl/private/irvis.key
sudo chmod 600 /etc/ssl/private/irvis.key

# Start Apache
sudo systemctl start apache2
```