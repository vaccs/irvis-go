#!/bin/bash
# ============================================================
# IRVIS Application Installation Script
# This script installs the IRVIS Go application to /var/www/html/irvis
# ============================================================

set -e  # Exit on any error

# Configuration
APP_NAME="irvis"
INSTALL_DIR="/var/www/html/irvis"
SERVICE_NAME="irvis-go"
SERVICE_USER="www-data"
GO_BINARY_NAME="irvis_go"
FLUTTER_DIR="$HOME/irvis_flutter"
PROJECT_DIR="$(pwd)"
APACHE_SITE_NAME="irvis"
APP_PORT="8083"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if Go is installed
    if ! command -v go &> /dev/null; then
        print_error "Go is not installed. Please install Go first."
        exit 1
    fi
    print_status "Go found: $(go version)"
    
    # Check if Flutter is installed
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter is not installed. Please install Flutter first."
        exit 1
    fi
    print_status "Flutter found: $(flutter --version | head -n1)"
    
    # Check if Flutter project exists
    if [[ ! -d "$FLUTTER_DIR" ]]; then
        print_error "Flutter project not found at: $FLUTTER_DIR"
        print_error "Please ensure the Flutter project exists or update FLUTTER_DIR in this script"
        exit 1
    fi
    print_status "Flutter project found: $FLUTTER_DIR"
    
    # Check if MySQL is running
    if ! systemctl is-active --quiet mysql; then
        print_warning "MySQL service is not running. The app may not start properly."
    else
        print_status "MySQL service is running"
    fi
    
    # Check if Apache2 is installed
    if ! command -v apache2 &> /dev/null; then
        print_error "Apache2 is not installed. Please install Apache2 first."
        exit 1
    fi
    print_status "Apache2 found: $(apache2 -v | head -n1)"
    
    # Check if required Apache modules are enabled
    if ! a2query -m ssl &> /dev/null; then
        print_warning "SSL module not enabled. Will enable it."
    fi
    
    if ! a2query -m proxy &> /dev/null; then
        print_warning "Proxy module not enabled. Will enable it."
    fi
    
    if ! a2query -m proxy_http &> /dev/null; then
        print_warning "Proxy HTTP module not enabled. Will enable it."
    fi
}

# Build Flutter web application
build_flutter() {
    print_header "Building Flutter Web Application"
    
    cd "$FLUTTER_DIR"
    print_status "Building Flutter web app..."
    flutter build web --base-href "/irvis/visual/"
    
    cd "$PROJECT_DIR"
    
    # Create visual directory and copy Flutter build
    mkdir -p visual
    cp -r "$FLUTTER_DIR/build/web/"* visual/
    print_status "Flutter web build copied to visual/"
}

# Compile Go application
compile_go() {
    print_header "Compiling Go Application"
    
    cd "$PROJECT_DIR"
    print_status "Building Go application..."
    go build -o "$GO_BINARY_NAME" ./cmd/server
    
    if [[ ! -f "$GO_BINARY_NAME" ]]; then
        print_error "Failed to build Go application"
        exit 1
    fi
    
    print_status "Go application compiled successfully: $GO_BINARY_NAME"
}

# Create installation directory and copy files
install_files() {
    print_header "Installing Application Files"
    
    # Create installation directory
    print_status "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # Copy Go binary
    print_status "Copying Go binary..."
    cp "$GO_BINARY_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$GO_BINARY_NAME"
    
    # Copy HTML files
    print_status "Copying HTML files..."
    cp -r irvis/ "$INSTALL_DIR/"
    
    # Copy Flutter web build
    print_status "Copying Flutter web application..."
    cp -r visual/ "$INSTALL_DIR/"
    
    # Copy SSL certificates if they exist
    if [[ -f "server.crt" && -f "server.key" ]]; then
        print_status "Copying SSL certificates..."
        cp server.crt server.key "$INSTALL_DIR/"
        chmod 600 "$INSTALL_DIR/server.key"
    else
        print_warning "SSL certificates not found. HTTPS may not work."
    fi
    
    # Copy environment file
    if [[ -f ".env" ]]; then
        print_status "Copying environment configuration..."
        cp .env "$INSTALL_DIR/"
    else
        print_warning ".env file not found. Creating default configuration..."
        cat > "$INSTALL_DIR/.env" << EOF
DB_HOST=localhost
DB_PORT=3306
DB_USER=irvis_user
DB_PASSWORD=password
DB_NAME=irvis
GITHUB_TOKEN=your_github_token_here
PORT=$APP_PORT
HTTPS_PORT=8444
TLS_CERT_FILE=server.crt
TLS_KEY_FILE=server.key
MAX_OPEN_CONNS=20
MAX_IDLE_CONNS=10
CONN_MAX_LIFETIME=3600
EOF
    fi
    
    # Update PORT in existing .env file to use our configured port
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        sed -i "s/^PORT=.*/PORT=$APP_PORT/" "$INSTALL_DIR/.env"
    fi
    
    # Set ownership and permissions
    print_status "Setting file permissions..."
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod 600 "$INSTALL_DIR/.env"
    
    if [[ -f "$INSTALL_DIR/server.key" ]]; then
        chmod 600 "$INSTALL_DIR/server.key"
    fi
}

# Create systemd service
create_service() {
    print_header "Creating Systemd Service"
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=IRVIS Go Application
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$GO_BINARY_NAME
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Environment
Environment=GIN_MODE=release

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$INSTALL_DIR
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

    print_status "Systemd service created: /etc/systemd/system/$SERVICE_NAME.service"
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    print_status "Service enabled to start on boot"
}

# Configure Apache2 virtual host
configure_apache() {
    print_header "Configuring Apache2 Virtual Host"
    
    # Enable required Apache modules
    print_status "Enabling Apache2 modules..."
    a2enmod ssl
    a2enmod proxy
    a2enmod proxy_http
    a2enmod headers
    a2enmod rewrite
    
    # Create SSL certificate if it doesn't exist
    if [[ ! -f "/etc/ssl/certs/irvis.crt" || ! -f "/etc/ssl/private/irvis.key" ]]; then
        print_status "Creating self-signed SSL certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "/etc/ssl/private/irvis.key" \
            -out "/etc/ssl/certs/irvis.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=localhost"
        chmod 600 "/etc/ssl/private/irvis.key"
        print_status "SSL certificate created"
    else
        print_status "SSL certificate already exists"
    fi
    
    # Create Apache virtual host configuration
    cat > "/etc/apache2/sites-available/$APACHE_SITE_NAME.conf" << EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/html
    
    # Redirect HTTP to HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^/irvis(.*) https://%{HTTP_HOST}/irvis\$1 [R=301,L]
    
    # Allow other content to be served normally
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerName localhost
    DocumentRoot /var/www/html
    
    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/irvis.crt
    SSLCertificateKeyFile /etc/ssl/private/irvis.key
    
    # Security headers
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set X-Frame-Options DENY
    Header always set X-Content-Type-Options nosniff
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # Proxy configuration for IRVIS app
    ProxyPreserveHost On
    ProxyRequests Off
    
    # Proxy all /irvis requests to the Go application
    ProxyPass /irvis http://127.0.0.1:$APP_PORT/irvis
    ProxyPassReverse /irvis http://127.0.0.1:$APP_PORT/irvis
    
    # Set proper headers for proxied requests
    ProxyPassReverse /irvis http://127.0.0.1:$APP_PORT/irvis
    ProxyPassReverseRewrite /irvis http://127.0.0.1:$APP_PORT/irvis
    
    # Handle WebSocket connections if needed
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/irvis/(.*) "ws://127.0.0.1:$APP_PORT/irvis/\$1" [P,L]
    
    # Allow other content to be served normally from DocumentRoot
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Exclude /irvis from being served from DocumentRoot
    <LocationMatch "^/irvis">
        ProxyPass http://127.0.0.1:$APP_PORT/irvis
        ProxyPassReverse http://127.0.0.1:$APP_PORT/irvis
    </LocationMatch>
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/irvis_error.log
    CustomLog \${APACHE_LOG_DIR}/irvis_access.log combined
</VirtualHost>
EOF

    print_status "Apache virtual host configuration created"
    
    # Enable the site
    a2ensite "$APACHE_SITE_NAME"
    
    # Test Apache configuration
    if apache2ctl configtest; then
        print_status "Apache configuration test passed"
    else
        print_error "Apache configuration test failed"
        exit 1
    fi
    
    # Reload Apache
    systemctl reload apache2
    print_status "Apache2 reloaded with new configuration"
    
    # Ensure Apache is enabled and started
    systemctl enable apache2
    if ! systemctl is-active --quiet apache2; then
        systemctl start apache2
    fi
    
    print_status "Apache2 virtual host configured successfully"
}

# Start the service
start_service() {
    print_header "Starting IRVIS Service"
    
    # Stop service if it's already running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Stopping existing service..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    # Start the service
    print_status "Starting $SERVICE_NAME service..."
    systemctl start "$SERVICE_NAME"
    
    # Check if service started successfully
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Service started successfully!"
        systemctl status "$SERVICE_NAME" --no-pager -l
    else
        print_error "Service failed to start. Check logs with: journalctl -u $SERVICE_NAME"
        exit 1
    fi
}

# Display post-installation information
post_install_info() {
    print_header "Installation Complete"
    
    echo -e "${GREEN}IRVIS application has been successfully installed!${NC}"
    echo
    echo "Installation Details:"
    echo "  - Installation Directory: $INSTALL_DIR"
    echo "  - Service Name: $SERVICE_NAME"
    echo "  - Binary: $INSTALL_DIR/$GO_BINARY_NAME"
    echo "  - Service User: $SERVICE_USER"
    echo
    echo "Service Management:"
    echo "  - Start:   sudo systemctl start $SERVICE_NAME"
    echo "  - Stop:    sudo systemctl stop $SERVICE_NAME"
    echo "  - Restart: sudo systemctl restart $SERVICE_NAME"
    echo "  - Status:  sudo systemctl status $SERVICE_NAME"
    echo "  - Logs:    sudo journalctl -u $SERVICE_NAME -f"
    echo
    echo "Application URLs:"
    echo "  - HTTP:  http://localhost/irvis (redirects to HTTPS)"
    echo "  - HTTPS: https://localhost/irvis"
    echo "  - Direct: http://localhost:$APP_PORT/irvis (Go app direct access)"
    echo
    echo "Next Steps:"
    echo "  1. Configure your database connection in: $INSTALL_DIR/.env"
    echo "  2. Set up your GitHub token in: $INSTALL_DIR/.env"
    echo "  3. Test the application by visiting https://localhost/irvis"
    echo "  4. Replace the self-signed certificate with a proper SSL certificate if needed"
    echo
    echo "Apache Configuration:"
    echo "  - Virtual Host: /etc/apache2/sites-available/$APACHE_SITE_NAME.conf"
    echo "  - SSL Certificate: /etc/ssl/certs/irvis.crt"
    echo "  - SSL Private Key: /etc/ssl/private/irvis.key"
    echo "  - Error Log: /var/log/apache2/irvis_error.log"
    echo "  - Access Log: /var/log/apache2/irvis_access.log"
    echo
    print_warning "The application is now accessible via Apache2 proxy on standard HTTP/HTTPS ports!"
    print_warning "HTTP requests are automatically redirected to HTTPS for security."
}

# Main installation process
main() {
    print_header "IRVIS Application Installation"
    
    check_root
    check_prerequisites
    build_flutter
    compile_go
    install_files
    create_service
    configure_apache
    start_service
    post_install_info
}

# Run installation
main "$@"