#!/bin/bash
# ============================================================
# IRVIS Database Backup and Restore Script
# Generated on: October 14, 2025
# ============================================================

set -e  # Exit on any error

# Database configuration
DB_NAME="irvis"
DB_USER="irvis_user"
DB_PASS="password"
BACKUP_FILE="irvis_complete_backup_$(date +%Y%m%d_%H%M%S).sql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create a complete database backup
create_backup() {
    print_status "Creating complete database backup..."
    
    # Check if mysqldump is available
    if ! command -v mysqldump &> /dev/null; then
        print_error "mysqldump command not found. Please install MySQL client tools."
        exit 1
    fi
    
    # Create the backup with complete structure and data
    mysqldump -u root -p \
        --single-transaction \
        --routines \
        --triggers \
        --lock-tables=false \
        --add-drop-database \
        --databases $DB_NAME > "$BACKUP_FILE"
    
    # Add user creation to the backup file
    cat >> "$BACKUP_FILE" << 'EOF'

-- ============================================================
-- Create database user and grant privileges
-- ============================================================
CREATE USER IF NOT EXISTS 'irvis_user'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON irvis.* TO 'irvis_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    print_status "Backup created successfully: $BACKUP_FILE"
    
    # Display backup file size
    backup_size=$(du -h "$BACKUP_FILE" | cut -f1)
    print_status "Backup file size: $backup_size"
}

# Function to restore database from backup
restore_backup() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        print_error "Please provide backup file path"
        echo "Usage: $0 restore <backup_file>"
        exit 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    print_status "Restoring database from: $backup_file"
    print_warning "This will overwrite the existing irvis database if it exists."
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Restore cancelled."
        exit 0
    fi
    
    # Restore the database
    mysql -u root -p < "$backup_file"
    
    print_status "Database restored successfully!"
    
    # Verify the restore
    print_status "Verifying restore..."
    user_count=$(mysql -u root -p -D $DB_NAME -se "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
    print_status "Total users in restored database: $user_count"
}

# Function to test database connection
test_connection() {
    print_status "Testing database connection..."
    
    # Test root connection
    if mysql -u root -p -e "SELECT 1;" &>/dev/null; then
        print_status "Root connection: OK"
    else
        print_error "Root connection: FAILED"
        exit 1
    fi
    
    # Test irvis_user connection
    if mysql -u $DB_USER -p$DB_PASS -D $DB_NAME -e "SELECT COUNT(*) FROM users;" &>/dev/null; then
        print_status "irvis_user connection: OK"
        user_count=$(mysql -u $DB_USER -p$DB_PASS -D $DB_NAME -se "SELECT COUNT(*) FROM users;" 2>/dev/null)
        print_status "Users in database: $user_count"
    else
        print_warning "irvis_user connection: FAILED (user may not exist yet)"
    fi
}

# Function to show usage
show_usage() {
    echo "IRVIS Database Backup and Restore Script"
    echo
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  backup              Create a complete database backup"
    echo "  restore <file>      Restore database from backup file"
    echo "  test                Test database connections"
    echo "  help                Show this help message"
    echo
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 restore irvis_backup_20251014_120000.sql"
    echo "  $0 test"
}

# Main script logic
case "${1:-help}" in
    backup)
        create_backup
        ;;
    restore)
        restore_backup "$2"
        ;;
    test)
        test_connection
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac