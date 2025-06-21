#!/bin/bash

# ==========================================
# SYSTEM SETUP MODULE
# System preparation and package installation
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main system setup function
setup_system() {
    log_step "SYSTEM SETUP AND PACKAGE INSTALLATION"
    
    stop_conflicting_services
    install_packages
    configure_system_settings
    setup_users_and_groups
    setup_directory_permissions
    
    log_success "System setup completed"
}

# Stop any conflicting services
stop_conflicting_services() {
    log_info "Stopping conflicting services..."
    
    for service in "${SERVICES[@]}"; do
        stop_service "$service"
    done
    
    # Wait for processes to terminate
    sleep 3
    log_success "All services stopped cleanly"
}

# Install required packages
install_packages() {
    log_info "Installing required packages..."
    
    # Fix broken package configuration
    dpkg --configure -a || {
        log_error "dpkg configuration failed"
        exit 1
    }

    # Update package lists
    apt update || {
        log_error "Failed to update package lists"
        exit 1
    }

    # Install packages with non-interactive frontend
    DEBIAN_FRONTEND=noninteractive apt install -y "${REQUIRED_PACKAGES[@]}" || {
        log_error "Failed to install packages"
        exit 1
    }
      
    log_success "All required packages installed successfully"
}

# Configure system settings
configure_system_settings() {
    log_info "Configuring system settings..."
    
    # Set hostname
    echo "$HOSTNAME" > /etc/hostname
    hostnamectl set-hostname "$HOSTNAME"

    # Configure hosts file
    cat > /etc/hosts <<EOF
127.0.0.1 localhost
$SERVER_IP $HOSTNAME imap.$DOMAIN mail.$DOMAIN autodiscover.$DOMAIN autoconfig.$DOMAIN
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

    # Set mail name
    echo "$DOMAIN" > /etc/mailname
    
    log_success "System settings configured"
}

# Setup required users and groups
setup_users_and_groups() {
    log_info "Setting up users and groups..."
    
    # Create syslog user for logging (fixes logging issues)
    if ! getent passwd syslog >/dev/null; then
        useradd --system --home /var/log --shell /bin/false syslog
        log_info "Created syslog user"
    else
        log_info "syslog user already exists"
    fi
    
    # Create adm group for log file access
    if ! getent group adm >/dev/null; then
        groupadd adm
        log_info "Created adm group"
    else
        log_info "adm group already exists"
    fi
    
    # Create vmail group and user for virtual mailboxes
    if ! getent group vmail >/dev/null; then
        groupadd -g 5000 vmail
        log_info "Created vmail group"
    else
        log_info "vmail group already exists"
    fi
    
    # Create vmail user with proper handling
    if ! getent passwd vmail >/dev/null; then
        useradd -u 5000 -g vmail -d /var/mail -s /bin/false vmail
        log_info "Created vmail user"
    else
        log_info "vmail user already exists"
        # Ensure user is in correct group
        usermod -g vmail vmail 2>/dev/null || log_warning "Could not update vmail user group"
    fi
    
    # Create PostSRSD user
    if ! getent passwd postsrsd >/dev/null; then
        create_system_user "postsrsd" "" "/var/lib/postsrsd" "/bin/false"
        log_info "Created postsrsd user"
    else
        log_info "postsrsd user already exists"
    fi
    
    # Create OpenDKIM user if doesn't exist
    if ! getent passwd opendkim >/dev/null; then
        create_system_user "opendkim" "" "/var/lib/opendkim" "/bin/false"
        log_info "Created opendkim user"
    else
        log_info "opendkim user already exists"
    fi
    
    log_success "Users and groups configured"
}

# Setup directory permissions
setup_directory_permissions() {
    log_info "Setting up directory permissions..."
    
    # Postfix directories
    setup_postfix_directories
    
    # Dovecot directories
    setup_dovecot_directories
    
    # OpenDKIM directories
    setup_opendkim_directories
    
    # PostSRSD directories
    setup_postsrsd_directories
    
    log_success "Directory permissions configured"
}

# Setup Postfix directories
setup_postfix_directories() {
    local postfix_dirs=(
        "private" "public" "maildrop" "hold" "incoming" 
        "active" "deferred" "corrupt" "bounce" "defer" "trace" "flush"
    )
    
    mkdir -p /var/spool/postfix
    for dir in "${postfix_dirs[@]}"; do
        mkdir -p "/var/spool/postfix/$dir"
    done
    
    # Fix ownership issues that cause warnings
    chown -R postfix:postfix /var/spool/postfix
    chmod 755 /var/spool/postfix
    chmod 700 /var/spool/postfix/private
    chmod 710 /var/spool/postfix/public
    chmod 730 /var/spool/postfix/maildrop
    
    # Fix postdrop group ownership for specific directories
    chgrp postdrop /var/spool/postfix/public /var/spool/postfix/maildrop
    
    # Ensure proper ownership of system files in chroot
    if [ -d /var/spool/postfix/etc ]; then
        chown -R root:root /var/spool/postfix/etc
    fi
    if [ -d /var/spool/postfix/lib ]; then
        chown -R root:root /var/spool/postfix/lib
    fi
    if [ -d /var/spool/postfix/usr ]; then
        chown -R root:root /var/spool/postfix/usr
    fi
}

# Setup Dovecot directories
setup_dovecot_directories() {
    mkdir -p /var/run/dovecot
    mkdir -p "/var/mail/vhosts/$DOMAIN"
    
    chown dovecot:dovecot /var/run/dovecot
    chown -R vmail:vmail /var/mail
    chmod 755 /var/run/dovecot
    chmod -R 755 /var/mail
}

# Setup OpenDKIM directories
setup_opendkim_directories() {
    mkdir -p /var/run/opendkim
    mkdir -p "/etc/opendkim/keys/$DOMAIN"
    mkdir -p /var/lib/opendkim
    
    chown -R opendkim:opendkim /var/run/opendkim
    chown -R opendkim:opendkim /etc/opendkim
    chown -R opendkim:opendkim /var/lib/opendkim
    chmod 755 /var/run/opendkim
    chmod -R 755 /etc/opendkim
    chmod -R 700 /etc/opendkim/keys
}

# Setup PostSRSD directories
setup_postsrsd_directories() {
    mkdir -p /etc/postsrsd
    mkdir -p /var/lib/postsrsd
    chown postsrsd:postsrsd /var/lib/postsrsd
}

# Run system setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_system
fi
