#!/bin/bash
# ============================================================
# IRVIS Application Installation Script
# This script installs the IRVIS Go application to /var/www/html/irvis
# 
# Usage: ./install_irvis.sh
# Note: Script will use sudo automatically when needed for system operations
# ============================================================

set -e  # Exit on any error

# Configuration
APP_NAME="irvis"
INSTALL_DIR="/var/www/html/irvis"
SERVICE_NAME="irvis-go"
SERVICE_USER="www-data"
GO_BINARY_NAME="irvis_go"
FLUTTER_DIR="$HOME/irvis_flutter"
# Update this path to match your Flutter installation
FLUTTER_BIN="${FLUTTER_BIN:-$HOME/development/flutter/bin/flutter}"
PROJECT_DIR="$(pwd)"

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

# Helper function to run commands with sudo only when necessary
run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        # Already running as root
        "$@"
    else
        # Use sudo
        sudo "$@"
    fi
}

# Check if we can write to system directories
check_permissions() {
    print_status "Checking permissions..."
    
    # Check if we can write to /var/www/html (needed for installation)
    if [[ ! -w "/var/www/html" ]] && [[ $EUID -ne 0 ]]; then
        print_warning "Need root privileges to write to $INSTALL_DIR"
        print_status "Some operations will require sudo"
    fi
    
    # Check if we can manage systemd services
    if ! systemctl --user list-units &>/dev/null && [[ $EUID -ne 0 ]]; then
        print_warning "Need root privileges to manage systemd services"
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
    if [[ ! -f "$FLUTTER_BIN" ]]; then
        print_error "Flutter not found at: $FLUTTER_BIN"
        print_error "Please update FLUTTER_BIN path in this script or install Flutter"
        exit 1
    fi
    print_status "Flutter found: $($FLUTTER_BIN --version | head -n1)"
    
    # Check if Flutter project exists
    if [[ ! -d "$FLUTTER_DIR" ]]; then
        print_error "Flutter project not found at: $FLUTTER_DIR"
        print_error "Please ensure the Flutter project exists or update FLUTTER_DIR in this script"
        exit 1
    fi
    print_status "Flutter project found: $FLUTTER_DIR"
    
    # Check if MySQL is running
    if ! run_as_root systemctl is-active --quiet mysql; then
        print_warning "MySQL service is not running. The app may not start properly."
    else
        print_status "MySQL service is running"
    fi
}

# Build Flutter web application
build_flutter() {
    print_header "Building Flutter Web Application"
    
    cd "$FLUTTER_DIR"
    print_status "Building Flutter web app..."
    "$FLUTTER_BIN" build web --base-href "/irvis/visual/"
    
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
    run_as_root mkdir -p "$INSTALL_DIR"
    
    # Copy Go binary
    print_status "Copying Go binary..."
    run_as_root cp "$GO_BINARY_NAME" "$INSTALL_DIR/"
    run_as_root chmod +x "$INSTALL_DIR/$GO_BINARY_NAME"
    
    # Copy HTML files
    print_status "Copying HTML files..."
    run_as_root cp -r irvis/ "$INSTALL_DIR/"
    
    # Copy Flutter web build
    print_status "Copying Flutter web application..."
    run_as_root cp -r visual/ "$INSTALL_DIR/"
    
    # Copy SSL certificates if they exist
    if [[ -f "server.crt" && -f "server.key" ]]; then
        print_status "Copying SSL certificates..."
        run_as_root cp server.crt server.key "$INSTALL_DIR/"
        run_as_root chmod 600 "$INSTALL_DIR/server.key"
    else
        print_warning "SSL certificates not found. HTTPS may not work."
    fi
    
    # Copy environment file
    if [[ -f ".env" ]]; then
        print_status "Copying environment configuration..."
        run_as_root cp .env "$INSTALL_DIR/"
    else
        print_warning ".env file not found. Creating default configuration..."
        run_as_root tee "$INSTALL_DIR/.env" > /dev/null << 'EOF'
DB_HOST=localhost
DB_PORT=3306
DB_USER=irvis_user
DB_PASSWORD=password
DB_NAME=irvis
GITHUB_TOKEN=your_github_token_here
PORT=8080
HTTPS_PORT=8443
TLS_CERT_FILE=server.crt
TLS_KEY_FILE=server.key
MAX_OPEN_CONNS=20
MAX_IDLE_CONNS=10
CONN_MAX_LIFETIME=3600
EOF
    fi
    
    # Set ownership and permissions
    print_status "Setting file permissions..."
    run_as_root chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    run_as_root chmod -R 755 "$INSTALL_DIR"
    run_as_root chmod 600 "$INSTALL_DIR/.env"
    
    if [[ -f "$INSTALL_DIR/server.key" ]]; then
        run_as_root chmod 600 "$INSTALL_DIR/server.key"
    fi
}

# Create systemd service
create_service() {
    print_header "Creating Systemd Service"
    
    run_as_root tee "/etc/systemd/system/$SERVICE_NAME.service" > /dev/null << EOF
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
    run_as_root systemctl daemon-reload
    run_as_root systemctl enable "$SERVICE_NAME"
    print_status "Service enabled to start on boot"
}

# Start the service
start_service() {
    print_header "Starting IRVIS Service"
    
    # Stop service if it's already running
    if run_as_root systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Stopping existing service..."
        run_as_root systemctl stop "$SERVICE_NAME"
    fi
    
    # Start the service
    print_status "Starting $SERVICE_NAME service..."
    run_as_root systemctl start "$SERVICE_NAME"
    
    # Check if service started successfully
    sleep 2
    if run_as_root systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Service started successfully!"
        run_as_root systemctl status "$SERVICE_NAME" --no-pager -l
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
    echo "Next Steps:"
    echo "  1. Configure your database connection in: $INSTALL_DIR/.env"
    echo "  2. Set up your GitHub token in: $INSTALL_DIR/.env"
    echo "  3. Configure your web server (Apache/Nginx) if needed"
    echo "  4. Test the application by visiting the URL above"
    echo
    print_warning "Don't forget to configure your firewall to allow access to ports 8080/8443!"
}

# Main installation process
main() {
    print_header "IRVIS Application Installation"
    
    check_permissions
    check_prerequisites
    build_flutter
    compile_go
    install_files
    create_service
    start_service
    post_install_info
}

# Run installation
main "$@"