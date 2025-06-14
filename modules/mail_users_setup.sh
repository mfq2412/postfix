#!/bin/bash

# ==========================================
# MAIL USERS SETUP MODULE
# Create and configure mail users
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main mail users setup function
setup_mail_users() {
    log_step "SETTING UP MAIL USERS"
    
    initialize_user_files
    create_default_users
    create_mailbox_directories
    update_postfix_maps
    
    log_success "Mail users setup completed"
}

# Initialize user files
initialize_user_files() {
    log_info "Initializing user files..."
    
    # Clear existing files and recreate
    > /etc/dovecot/users
    > /etc/postfix/vmailbox
    
    # Set proper permissions
    chmod 640 /etc/dovecot/users
    chown root:dovecot /etc/dovecot/users
    
    chmod 644 /etc/postfix/vmailbox
    chown root:root /etc/postfix/vmailbox
}

# Create default mail users
create_default_users() {
    log_info "Creating default mail users..."
    
    for user_pass in "${MAIL_USERS[@]}"; do
        local email=$(echo "$user_pass" | cut -d':' -f1)
        local password=$(echo "$user_pass" | cut -d':' -f2)
        
        create_single_user "$email" "$password"
    done
}

# Create a single mail user
create_single_user() {
    local email="$1"
    local password="$2"
    local username=$(echo "$email" | cut -d'@' -f1)
    local user_domain=$(echo "$email" | cut -d'@' -f2)
    
    log_info "Creating user: $email"
    
    # Validate email format
    if ! validate_email "$email"; then
        log_error "Invalid email format: $email"
        return 1
    fi
    
    # Check if user already exists
    if grep -q "^$email:" /etc/dovecot/users 2>/dev/null; then
        log_warning "User $email already exists, skipping"
        return 0
    fi
    
    # Generate password hash
    local pass_hash=$(doveadm pw -s CRYPT -p "$password")
    
    # Add to dovecot users file
    echo "$email:$pass_hash::::::" >> /etc/dovecot/users
    
    # Add to postfix virtual mailbox
    echo "$email $user_domain/$username/" >> /etc/postfix/vmailbox
    
    log_success "Created user: $email"
}

# Create mailbox directories
create_mailbox_directories() {
    log_info "Creating mailbox directories..."
    
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        local email=$(echo "$line" | cut -d' ' -f1)
        local mailbox_path=$(echo "$line" | cut -d' ' -f2)
        local username=$(echo "$email" | cut -d'@' -f1)
        local user_domain=$(echo "$email" | cut -d'@' -f2)
        
        # Create main mailbox directories
        local mailbox_dir="/var/mail/vhosts/$user_domain/$username"
        mkdir -p "$mailbox_dir"/{cur,new,tmp}
        
        # Create special folders
        local special_folders=("Drafts" "Sent" "Trash" "Junk")
        for folder in "${special_folders[@]}"; do
            mkdir -p "$mailbox_dir/.$folder"/{cur,new,tmp}
        done
        
        # Set ownership and permissions
        chown -R vmail:vmail "/var/mail/vhosts/$user_domain"
        chmod -R 755 "/var/mail/vhosts/$user_domain"
        
    done < /etc/postfix/vmailbox
    
    log_success "Mailbox directories created"
}

# Update Postfix maps
update_postfix_maps() {
    log_info "Updating Postfix maps..."
    
    # Generate virtual mailbox database
    postmap /etc/postfix/vmailbox
    
    # Verify database creation
    if [ -f /etc/postfix/vmailbox.db ]; then
        log_success "Virtual mailbox database created"
    else
        log_error "Failed to create virtual mailbox database"
        return 1
    fi
    
    # Display user summary
    local user_count=$(wc -l < /etc/dovecot/users)
    log_info "Created $user_count mail users"
}

# Function to add a new user (for management script)
add_mail_user() {
    local email="$1"
    local password="$2"
    
    if [ -z "$email" ] || [ -z "$password" ]; then
        log_error "Email and password required"
        return 1
    fi
    
    create_single_user "$email" "$password"
    
    # Create mailbox directory for new user
    local username=$(echo "$email" | cut -d'@' -f1)
    local user_domain=$(echo "$email" | cut -d'@' -f2)
    local mailbox_dir="/var/mail/vhosts/$user_domain/$username"
    
    mkdir -p "$mailbox_dir"/{cur,new,tmp}
    
    local special_folders=("Drafts" "Sent" "Trash" "Junk")
    for folder in "${special_folders[@]}"; do
        mkdir -p "$mailbox_dir/.$folder"/{cur,new,tmp}
    done
    
    chown -R vmail:vmail "/var/mail/vhosts/$user_domain"
    chmod -R 755 "/var/mail/vhosts/$user_domain"
    
    # Update Postfix maps
    postmap /etc/postfix/vmailbox
    
    # Reload services
    systemctl reload dovecot 2>/dev/null || true
    systemctl reload postfix 2>/dev/null || true
    
    log_success "User $email added successfully"
}

# Function to remove a user (for management script)
remove_mail_user() {
    local email="$1"
    
    if [ -z "$email" ]; then
        log_error "Email required"
        return 1
    fi
    
    if ! grep -q "^$email:" /etc/dovecot/users 2>/dev/null; then
        log_error "User $email not found"
        return 1
    fi
    
    # Remove from dovecot users
    sed -i "/^$email:/d" /etc/dovecot/users
    
    # Remove from postfix virtual mailbox
    sed -i "/^$email /d" /etc/postfix/vmailbox
    
    # Update Postfix maps
    postmap /etc/postfix/vmailbox
    
    # Reload services
    systemctl reload dovecot 2>/dev/null || true
    systemctl reload postfix 2>/dev/null || true
    
    log_success "User $email removed successfully"
}

# Function to list all users
list_mail_users() {
    echo "Mail Users:"
    echo "==========="
    
    if [ -f /etc/dovecot/users ] && [ -s /etc/dovecot/users ]; then
        while IFS=: read -r email hash rest; do
            [ -n "$email" ] && echo "📧 $email"
        done < /etc/dovecot/users
    else
        echo "No users found"
    fi
}

# Function to change user password
change_user_password() {
    local email="$1"
    local new_password="$2"
    
    if [ -z "$email" ] || [ -z "$new_password" ]; then
        log_error "Email and new password required"
        return 1
    fi
    
    if ! grep -q "^$email:" /etc/dovecot/users 2>/dev/null; then
        log_error "User $email not found"
        return 1
    fi
    
    # Generate new password hash
    local pass_hash=$(doveadm pw -s CRYPT -p "$new_password")
    
    # Update password in dovecot users file
    sed -i "s/^$email:.*/$email:$pass_hash::::::/" /etc/dovecot/users
    
    # Reload dovecot
    systemctl reload dovecot 2>/dev/null || true
    
    log_success "Password changed for $email"
}

# Run mail users setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            setup_mail_users
            ;;
        "add")
            add_mail_user "$2" "$3"
            ;;
        "remove")
            remove_mail_user "$2"
            ;;
        "list")
            list_mail_users
            ;;
        "change-password")
            change_user_password "$2" "$3"
            ;;
        *)
            echo "Usage: $0 {setup|add|remove|list|change-password}"
            exit 1
            ;;
    esac
fi