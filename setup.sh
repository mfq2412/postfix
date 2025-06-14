#!/bin/bash

# ==========================================
# MODULAR MAIL SERVER SETUP v7.0
# Main orchestration script
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/mail_config.sh"
source "$SCRIPT_DIR/lib/common.sh"

# Basic firewall setup (inline function)
setup_basic_firewall() {
    log_step "CONFIGURING BASIC FIREWALL"
    
    log_info "Setting up UFW firewall..."
    
    # Reset UFW to defaults
    ufw --force reset > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1
    
    # Set default policies
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    
    # Allow essential services
    ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
    ufw allow 25/tcp comment 'SMTP' > /dev/null 2>&1
    ufw allow 587/tcp comment 'SMTP Submission' > /dev/null 2>&1
    ufw allow 465/tcp comment 'SMTPS' > /dev/null 2>&1
    ufw allow 143/tcp comment 'IMAP' > /dev/null 2>&1
    ufw allow 993/tcp comment 'IMAPS' > /dev/null 2>&1
    ufw allow 110/tcp comment 'POP3' > /dev/null 2>&1
    ufw allow 995/tcp comment 'POP3S' > /dev/null 2>&1
    ufw allow 80/tcp comment 'HTTP (Lets Encrypt)' > /dev/null 2>&1
    ufw allow 443/tcp comment 'HTTPS (Autodiscover)' > /dev/null 2>&1
    
    log_success "Basic firewall configured successfully"
}
prompt_configuration() {
    echo ""
    echo "=========================================="
    echo "🔧 MAIL SERVER CONFIGURATION"
    echo "=========================================="
    echo ""
    
    # Prompt for domain
    while true; do
        read -p "📧 Enter your domain name (e.g., example.com): " input_domain
        if [[ "$input_domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
            DOMAIN="$input_domain"
            break
        else
            echo "❌ Invalid domain format. Please enter a valid domain (e.g., example.com)"
        fi
    done
    
    # Prompt for hostname
    echo ""
    read -p "🌐 Enter mail server hostname (default: smtp.$DOMAIN): " input_hostname
    if [ -z "$input_hostname" ]; then
        HOSTNAME="smtp.$DOMAIN"
    else
        HOSTNAME="$input_hostname"
    fi
    
    # Prompt for server IP
    echo ""
    echo "🔍 Server IP Detection:"
    echo "   Leave empty for auto-detection"
    echo "   Or enter your server's public IP address"
    read -p "🌍 Server IP (leave empty for auto-detection): " input_ip
    if [ -n "$input_ip" ]; then
        if [[ "$input_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            SERVER_IP="$input_ip"
        else
            echo "❌ Invalid IP format. Using auto-detection instead."
            SERVER_IP=""
        fi
    else
        SERVER_IP=""
    fi
    
    # Update configuration values
    update_configuration
    
    # Display configuration summary
    display_configuration_summary
    
    # Confirm to proceed
    echo ""
    read -p "✅ Continue with this configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Run the script again to reconfigure."
        exit 0
    fi
}

# Update configuration file with user input
update_configuration() {
    log_info "Updating configuration with user input..."
    
    local config_file="$SCRIPT_DIR/config/mail_config.sh"
    
    # Update domain and hostname
    sed -i "s/DOMAIN=.*/DOMAIN=\"$DOMAIN\"/" "$config_file"
    sed -i "s/HOSTNAME=.*/HOSTNAME=\"$HOSTNAME\"/" "$config_file"
    
    # Update server IP if provided
    if [ -n "$SERVER_IP" ]; then
        sed -i "s/SERVER_IP=.*/SERVER_IP=\"$SERVER_IP\"/" "$config_file"
    fi
    
    # Update email addresses
    sed -i "s/ADMIN_EMAIL=.*/ADMIN_EMAIL=\"admin@$DOMAIN\"/" "$config_file"
    sed -i "s/DISTRO_EMAIL=.*/DISTRO_EMAIL=\"distribution@$DOMAIN\"/" "$config_file"
    
    # Update mail users array with new domain
    sed -i "s/@example\.com/@$DOMAIN/g" "$config_file"
    
    # Re-source the updated configuration
    source "$config_file"
    
    log_success "Configuration updated successfully"
}

# Display configuration summary
display_configuration_summary() {
    echo ""
    echo "=========================================="
    echo "📋 CONFIGURATION SUMMARY"
    echo "=========================================="
    echo "🌐 Domain:           $DOMAIN"
    echo "📧 Mail Hostname:    $HOSTNAME"
    if [ -n "$SERVER_IP" ]; then
        echo "🌍 Server IP:        $SERVER_IP"
    else
        echo "🌍 Server IP:        Auto-detect"
    fi
    echo "👤 Admin Email:      admin@$DOMAIN"
    echo "📮 Distribution:     distribution@$DOMAIN"
    echo ""
    echo "📝 DNS Records Required:"
    echo "   smtp.$DOMAIN     A    $SERVER_IP (or auto-detected IP)"
    echo "   imap.$DOMAIN     A    $SERVER_IP (or auto-detected IP)"
    echo "   mail.$DOMAIN     A    $SERVER_IP (or auto-detected IP)"
    echo "   $DOMAIN          MX   smtp.$DOMAIN"
    echo "=========================================="
}

# Check if this is a restart/resume of installation
check_installation_state() {
    if [ -f "/opt/mailserver/.installation_started" ]; then
        echo ""
        echo "⚠️  Previous installation detected!"
        echo "   Installation marker found at /opt/mailserver/.installation_started"
        echo ""
        read -p "Do you want to (c)ontinue previous installation or (r)estart fresh? (c/r): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Rr]$ ]]; then
            log_info "Cleaning up previous installation..."
            rm -f /opt/mailserver/.installation_started
            # Clean up any partially created users (optional)
            # This allows for a completely fresh start if needed
        else
            log_info "Continuing previous installation..."
        fi
    fi
    
    # Create installation marker
    mkdir -p /opt/mailserver
    touch /opt/mailserver/.installation_started
}

# Set file permissions for all scripts
set_file_permissions() {
    log_info "Setting file permissions for all scripts..."
    
    # Set permissions for configuration and library files
    chmod +x "$SCRIPT_DIR/config/mail_config.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || true
    
    # Set permissions for all module files
    chmod +x "$SCRIPT_DIR/modules"/*.sh 2>/dev/null || true
    
    # Set permissions for setup scripts
    chmod +x "$SCRIPT_DIR/setup.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/quick-setup.sh" 2>/dev/null || true
    
    log_success "File permissions set successfully"
}

# Main execution
main() {
    log_step "STARTING MODULAR MAIL SERVER SETUP v7.0"
    
    # Pre-setup checks
    check_root
    
    # Set file permissions first
    set_file_permissions
    
    # Check installation state
    check_installation_state
    
    # Interactive configuration
    prompt_configuration
    
    # Auto-detect IP if not provided
    if [ -z "$SERVER_IP" ]; then
        detect_server_ip
    fi
    
    # Core setup modules
    log_info "Loading setup modules..."
    
    # System preparation
    "$SCRIPT_DIR/modules/system_setup.sh"
    
    # Service configurations
    "$SCRIPT_DIR/modules/postfix_setup.sh"
    "$SCRIPT_DIR/modules/dovecot_setup.sh"
    "$SCRIPT_DIR/modules/opendkim_setup.sh"
    "$SCRIPT_DIR/modules/postsrsd_setup.sh"
    
    # Mail configuration
    "$SCRIPT_DIR/modules/mail_users_setup.sh"
    "$SCRIPT_DIR/modules/forwarding_setup.sh"
    
    # Basic firewall setup (inline)
    setup_basic_firewall
    
    # Service management
    "$SCRIPT_DIR/modules/service_manager.sh" start_all
    
    # Verification and tools
    "$SCRIPT_DIR/modules/verification.sh"
    "$SCRIPT_DIR/modules/management_tools.sh"
    
    display_completion_summary
    
    # Mark installation as completed
    rm -f /opt/mailserver/.installation_started
    touch /opt/mailserver/.installation_completed
    
    log_success "Modular mail server setup completed successfully!"
}

# Display final summary
display_completion_summary() {
    echo ""
    echo "=========================================="
    echo "🚀 MODULAR MAIL SERVER v7.0 COMPLETED!"
    echo "=========================================="
    echo ""
    echo "📧 Server Information:"
    echo "Domain: $DOMAIN"
    echo "Hostname: $HOSTNAME"
    echo "Server IP: $SERVER_IP"
    echo "Setup completed: $(date)"
    echo ""
    echo "🛠️ Management Commands:"
    echo "/opt/mailserver/bin/mail-status      - Check server status"
    echo "/opt/mailserver/bin/mail-test        - Test all functionality"
    echo "/opt/mailserver/bin/mail-user        - Manage users"
    echo "/opt/mailserver/bin/mail-forward     - Manage forwarding"
    echo "/opt/mailserver/bin/mail-ssl         - SSL management"
    echo "/opt/mailserver/bin/mail-restart     - Restart services"
    echo ""
    echo "✅ All modules installed and configured!"
    echo "Ready for production use."
    echo "=========================================="
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Please run: sudo bash $0"
        exit 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'echo "Error occurred at line $LINENO. Check the log file: $LOG_FILE"' ERR
    main "$@"
fi
