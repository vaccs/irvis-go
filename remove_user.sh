#!/bin/bash
set -e

# Get username to remove
USERNAME=${1:-steve}

if [ -z "$USERNAME" ]; then
    echo "Usage: $0 <username>"
    echo "Example: $0 steve"
    exit 1
fi

# MySQL connection info
DB_NAME=${DB_NAME:-irvis}
DB_USER=${DB_USER:-root}

echo "Checking if user '$USERNAME' exists..."

# First check if user exists
USER_COUNT=$(mysql -u "$DB_USER" -p "$DB_NAME" -se "SELECT COUNT(*) FROM users WHERE username = '$USERNAME';")

if [ "$USER_COUNT" -eq 0 ]; then
    echo "User '$USERNAME' not found in database."
    exit 1
fi

echo "Found user '$USERNAME'. Showing user details:"
mysql -u "$DB_USER" -p "$DB_NAME" -e "SELECT id, username, email, is_admin, is_logged_in FROM users WHERE username = '$USERNAME';"

read -p "Are you sure you want to delete user '$USERNAME'? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "User deletion cancelled."
    exit 0
fi

# Delete the user
mysql -u "$DB_USER" -p "$DB_NAME" -e "DELETE FROM users WHERE username = '$USERNAME';"

echo "User '$USERNAME' has been successfully removed from the database."

# Show remaining users
echo "Remaining users in database:"
mysql -u "$DB_USER" -p "$DB_NAME" -e "SELECT id, username, email, is_admin FROM users;"