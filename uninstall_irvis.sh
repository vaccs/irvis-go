#!/bin/bash
# ============================================================
# IRVIS Application Uninstall Script
# This script removes the IRVIS Go application from /var/www/html/irvis
# ============================================================

set -e  # Exit on any error

# Configuration
APP_NAME="irvis"
INSTALL_DIR="/var/www/html/irvis"
SERVICE_NAME="irvis-go"
APACHE_SITE_NAME="irvis"

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

# Stop and remove service
remove_service() {
    print_header "Removing IRVIS Service"
    
    # Stop service if running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Stopping $SERVICE_NAME service..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    # Disable service
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_status "Disabling $SERVICE_NAME service..."
        systemctl disable "$SERVICE_NAME"
    fi
    
    # Remove service file
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        print_status "Removing service file..."
        rm "/etc/systemd/system/$SERVICE_NAME.service"
        systemctl daemon-reload
    fi
    
    print_status "Service removed successfully"
}

# Remove Apache configuration
remove_apache_config() {
    print_header "Removing Apache Configuration"
    
    # Disable the site if it exists
    if [[ -f "/etc/apache2/sites-available/$APACHE_SITE_NAME.conf" ]]; then
        print_status "Disabling Apache site: $APACHE_SITE_NAME"
        a2dissite "$APACHE_SITE_NAME" || true
        
        print_status "Removing Apache site configuration..."
        rm "/etc/apache2/sites-available/$APACHE_SITE_NAME.conf"
        
        # Test and reload Apache configuration
        if apache2ctl configtest; then
            systemctl reload apache2
            print_status "Apache configuration reloaded"
        else
            print_warning "Apache configuration test failed, but continuing..."
        fi
    else
        print_warning "Apache site configuration not found"
    fi
    
    # Ask about SSL certificate removal
    if [[ -f "/etc/ssl/certs/irvis.crt" && -f "/etc/ssl/private/irvis.key" ]]; then
        echo
        read -p "Remove SSL certificates? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "/etc/ssl/certs/irvis.crt"
            rm -f "/etc/ssl/private/irvis.key"
            print_status "SSL certificates removed"
        else
            print_status "SSL certificates kept"
        fi
    fi
    
    print_status "Apache configuration removed successfully"
}

# Remove application files
remove_files() {
    print_header "Removing Application Files"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        print_status "Removing installation directory: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
        print_status "Application files removed successfully"
    else
        print_warning "Installation directory not found: $INSTALL_DIR"
    fi
}

# Confirmation prompt
confirm_uninstall() {
    print_header "IRVIS Application Uninstall"
    print_warning "This will completely remove the IRVIS application and all its files."
    print_warning "The database and user data will NOT be removed."
    echo
    echo "This will remove:"
    echo "  - Service: $SERVICE_NAME"
    echo "  - Files: $INSTALL_DIR"
    echo "  - Systemd service configuration"
    echo "  - Apache virtual host configuration"
    echo "  - SSL certificates (optional)"
    echo
    
    read -p "Are you sure you want to uninstall IRVIS? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Uninstall cancelled."
        exit 0
    fi
}

# Main uninstall process
main() {
    check_root
    confirm_uninstall
    remove_service
    remove_apache_config
    remove_files
    
    print_header "Uninstall Complete"
    echo -e "${GREEN}IRVIS application has been successfully uninstalled!${NC}"
    echo
    echo "Note: The following were NOT removed:"
    echo "  - MySQL database and user data"
    echo "  - Source code in your development directory"
    echo "  - Flutter project directory"
    echo "  - Apache2 modules (ssl, proxy, etc.) - still enabled"
    echo "  - Other Apache sites and configurations"
    echo
    print_status "Uninstall completed successfully"
}

# Run uninstall
main "$@"