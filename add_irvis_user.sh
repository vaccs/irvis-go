#!/bin/bash
set -e

# Prompt for user info
read -p "Username: " USERNAME
read -p "Email: " EMAIL
read -s -p "Password: " PASSWORD
echo
read -s -p "Confirm Password: " PASSWORD_CONFIRM
echo

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
  echo "Error: Passwords do not match."
  exit 1
fi

# Hash password (SHA256)
HASHED_PASSWORD=$(echo -n "$PASSWORD" | openssl dgst -sha256 | awk '{print $2}')

# Ask if user should be an admin
read -p "Should this user be an administrator? (y/N): " IS_ADMIN_INPUT
IS_ADMIN="FALSE"
if [[ "$IS_ADMIN_INPUT" =~ ^[Yy]$ ]]; then
  IS_ADMIN="TRUE"
fi

# MySQL connection info
DB_NAME=${DB_NAME:-irvis}
DB_USER=${DB_USER:-root}

# Insert user
mysql -u "$DB_USER" -p "$DB_NAME" <<SQL
INSERT INTO users (username, email, hashed_password, is_logged_in, is_admin)
VALUES ('$USERNAME', '$EMAIL', '$HASHED_PASSWORD', FALSE, $IS_ADMIN);
SQL

echo "User '$USERNAME' added to $DB_NAME.users (Admin: $IS_ADMIN)."
