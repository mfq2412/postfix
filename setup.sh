#!/bin/bash

# ==========================================
# MODULAR MAIL SERVER SETUP v7.1
# Main orchestration script with new modules
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/mail_config.sh"
source "$SCRIPT_DIR/lib/common.sh"

# Service management with PostSRSD fallback
start_all_services_with_fallback() {
    log_step "STARTING ALL MAIL SERVICES"
    
    # Reload systemd daemon
    systemctl daemon-reload
    
    # Essential services (must work)
    local essential_services=("opendkim" "postfix" "dovecot")
    local optional_services=("postsrsd" "nginx")
    
    # Start essential services first
    for service in "${essential_services[@]}"; do
        log_info "Starting $service..."
        systemctl enable "$service" > /dev/null 2>&1
        
        if systemctl start "$service"; then
            sleep 2
            if systemctl is-active --quiet "$service"; then
                log_success "$service started successfully"
            else
                log_error "$service started but then stopped"
                return 1
            fi
        else
            log_error "CRITICAL: $service failed to start"
            return 1
        fi
        
        # Special handling for submission ports
        if [ "$service" = "postfix" ]; then
            sleep 5
            log_info "Reloading Postfix to activate submission ports..."
            systemctl reload postfix
            sleep 3
        fi
    done
    
    # Start optional services (can fail)
    for service in "${optional_services[@]}"; do
        log_info "Starting $service..."
        systemctl enable "$service" > /dev/null 2>&1
        
        if systemctl start "$service"; then
            sleep 2
            if systemctl is-active --quiet "$service"; then
                log_success "$service started successfully"
            else
                log_warning "$service started but then stopped (optional service)"
            fi
        else
            log_warning "$service failed to start (optional service, continuing...)"
        fi
    done
    
    # Try to start nginx if it was configured
    if [ -f /etc/nginx/sites-available/autodiscover ]; then
        log_info "Starting nginx..."
        systemctl enable nginx > /dev/null 2>&1
        if systemctl start nginx; then
            sleep 2
            if systemctl is-active --quiet nginx; then
                log_success "nginx started successfully"
            else
                log_warning "nginx started but then stopped (optional service)"
            fi
        else
            log_warning "nginx failed to start (optional service, continuing...)"
        fi
    fi
    
    log_success "All essential services started successfully"
}

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

# Set file permissions for all scripts (UPDATED)
set_file_permissions() {
    log_info "Setting file permissions for all scripts..."
    
    # Set permissions for configuration and library files
    chmod +x "$SCRIPT_DIR/config/mail_config.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || true
    
    # Set permissions for all module files (including new ones)
    chmod +x "$SCRIPT_DIR/modules"/*.sh 2>/dev/null || true
    
    # Set permissions for setup scripts
    chmod +x "$SCRIPT_DIR/setup.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/quick-setup.sh" 2>/dev/null || true
    
    # Set permissions for new fix modules
    chmod +x "$SCRIPT_DIR/modules/logging_setup.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/modules/postsrsd_fix.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/modules/ssl_complete_setup.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/modules/email_delivery_test.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/modules/comprehensive_mail_fix.sh" 2>/dev/null || true
    
    log_success "File permissions set successfully"
}

# Main execution (UPDATED)
main() {
    log_step "STARTING MODULAR MAIL SERVER SETUP v7.1"
    
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
    
    # Phase 1: System preparation
    "$SCRIPT_DIR/modules/system_setup.sh"
    
    # Phase 2: Service configurations
    "$SCRIPT_DIR/modules/postfix_setup.sh"
    "$SCRIPT_DIR/modules/dovecot_setup.sh"
    "$SCRIPT_DIR/modules/opendkim_setup.sh"
    
    # Phase 3: PostSRSD setup with enhanced error handling
    if "$SCRIPT_DIR/modules/postsrsd_setup.sh"; then
        log_success "PostSRSD configured successfully"
    else
        log_warning "PostSRSD configuration failed, attempting fix..."
        if [ -f "$SCRIPT_DIR/modules/postsrsd_fix.sh" ]; then
            "$SCRIPT_DIR/modules/postsrsd_fix.sh" fix
        else
            log_info "Email forwarding will work without SRS rewriting"
        fi
    fi
    
    # Phase 4: Nginx setup with error handling (optional)
    if [ -f "$SCRIPT_DIR/modules/nginx_setup.sh" ]; then
        if "$SCRIPT_DIR/modules/nginx_setup.sh"; then
            log_success "Nginx configured successfully"
        else
            log_warning "Nginx configuration failed, but continuing setup..."
            log_info "Email autodiscovery will require manual client setup"
        fi
    else
        log_info "Nginx setup module not found, skipping autodiscovery configuration"
    fi
    
    # Phase 5: Mail configuration
    "$SCRIPT_DIR/modules/mail_users_setup.sh"
    "$SCRIPT_DIR/modules/forwarding_setup.sh"
    
    # Phase 6: Logging setup (NEW)
    if [ -f "$SCRIPT_DIR/modules/logging_setup.sh" ]; then
        log_info "Setting up mail logging..."
        if "$SCRIPT_DIR/modules/logging_setup.sh" setup; then
            log_success "Mail logging configured"
        else
            log_warning "Mail logging setup failed, continuing..."
        fi
    else
        log_info "Setting up basic mail logging..."
        setup_basic_logging
    fi
    
    # Phase 7: Basic firewall setup (inline)
    setup_basic_firewall
    
    # Phase 8: Service management with PostSRSD error handling
    start_all_services_with_fallback
    
    # Phase 9: Verification and tools
    "$SCRIPT_DIR/modules/verification.sh"
    "$SCRIPT_DIR/modules/management_tools.sh"
    
    # Phase 10: Create new management tools (NEW)
    create_enhanced_management_tools
    
    # Phase 11: Initial testing (NEW)
    run_initial_tests
    
    display_completion_summary
    
    # Mark installation as completed
    rm -f /opt/mailserver/.installation_started
    touch /opt/mailserver/.installation_completed
    
    log_success "Modular mail server setup completed successfully!"
}

# Setup basic logging if module not available
setup_basic_logging() {
    log_info "Setting up basic mail logging..."
    
    # Configure rsyslog
    cat > /etc/rsyslog.d/50-mail.conf <<'EOF'
# Mail logging configuration
mail.*                          /var/log/mail.log
mail.err                        /var/log/mail.err
mail.warn                       /var/log/mail.warn

# Service-specific logging
:programname, isequal, "postfix" /var/log/mail.log
:programname, isequal, "dovecot" /var/log/mail.log
:programname, isequal, "opendkim" /var/log/mail.log
:programname, isequal, "postsrsd" /var/log/mail.log
EOF
    
    # Create log files
    touch /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    chown syslog:adm /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    chmod 644 /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    
    # Restart rsyslog
    systemctl restart rsyslog
    
    log_success "Basic mail logging configured"
}

# Create enhanced management tools (NEW)
create_enhanced_management_tools() {
    log_info "Creating enhanced management tools..."
    
    # Create mail-fix tool
    cat > "$BIN_DIR/mail-fix" << 'EOFFIX'
#!/bin/bash
# Quick access to comprehensive fix
cd /opt/mailserver/modules
if [ -f comprehensive_mail_fix.sh ]; then
    exec ./comprehensive_mail_fix.sh "$@"
else
    echo "Comprehensive fix module not found"
    exit 1
fi
EOFFIX
    
    # Create mail-logs tool
    cat > "$BIN_DIR/mail-logs" << 'EOFLOGS'
#!/bin/bash
# Quick access to mail log monitoring
case "${1:-tail}" in
    "tail")
        if [ -f /var/log/mail.log ]; then
            tail -f /var/log/mail.log
        else
            echo "Mail log not found. Run: mail-fix logging"
        fi
        ;;
    "errors")
        if [ -f /var/log/mail.err ]; then
            tail -20 /var/log/mail.err
        else
            echo "No error log found"
        fi
        ;;
    "analyze")
        if [ -f /var/log/mail.log ]; then
            echo "Recent mail activity:"
            tail -50 /var/log/mail.log | grep -E "(delivered|bounced|deferred)" | tail -10
        else
            echo "Mail log not found"
        fi
        ;;
    *)
        echo "Usage: $0 {tail|errors|analyze}"
        ;;
esac
EOFLOGS
    
    # Create comprehensive test tool
    cat > "$BIN_DIR/mail-test-all" << 'EOFTEST'
#!/bin/bash
# Comprehensive mail server testing
cd /opt/mailserver/modules
if [ -f email_delivery_test.sh ]; then
    exec ./email_delivery_test.sh comprehensive
else
    echo "Running basic tests..."
    /opt/mailserver/bin/mail-test
fi
EOFTEST
    
    # Create DNS guide tool
    cat > "$BIN_DIR/mail-dns-guide" << 'EOFDNS'
#!/bin/bash
source /opt/mailserver/config/mail_config.sh

echo "🌐 DNS CONFIGURATION GUIDE FOR $DOMAIN"
echo "======================================"
echo ""
echo "Required DNS Records:"
echo "--------------------"
echo "smtp.$DOMAIN.         IN A  $SERVER_IP"
echo "imap.$DOMAIN.         IN A  $SERVER_IP"
echo "mail.$DOMAIN.         IN A  $SERVER_IP"
echo "autodiscover.$DOMAIN. IN A  $SERVER_IP"
echo "autoconfig.$DOMAIN.   IN A  $SERVER_IP"
echo ""
echo "$DOMAIN.              IN MX 10 smtp.$DOMAIN."
echo ""
echo "$DOMAIN.              IN TXT \"v=spf1 ip4:$SERVER_IP -all\""
echo "_dmarc.$DOMAIN.       IN TXT \"v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN\""
echo ""
echo "DKIM Record (add after setup):"
if [ -f "/etc/opendkim/keys/$DOMAIN/default.txt" ]; then
    cat "/etc/opendkim/keys/$DOMAIN/default.txt"
else
    echo "Run 'dkim-test' to get your DKIM record"
fi
echo ""
echo "After adding DNS records:"
echo "1. Wait 15-30 minutes for propagation"
echo "2. Run: mail-fix ssl"
echo "3. Run: mail-test-all"
EOFDNS
    
    # Make all tools executable
    chmod +x "$BIN_DIR/mail-fix"
    chmod +x "$BIN_DIR/mail-logs"
    chmod +x "$BIN_DIR/mail-test-all"
    chmod +x "$BIN_DIR/mail-dns-guide"
    
    log_success "Enhanced management tools created"
}

# Run initial tests (NEW)
run_initial_tests() {
    log_info "Running initial mail server tests..."
    
    # Test basic functionality
    if echo "Initial setup test $(date)" | mail -s "Setup Test" "admin@$DOMAIN" 2>/dev/null; then
        log_success "Basic email functionality working"
    else
        log_warning "Basic email test failed (may need DNS configuration)"
    fi
    
    # Test logging
    if [ -f /var/log/mail.log ]; then
        log_success "Mail logging is active"
        # Send test log message
        logger -p mail.info "Mail server setup completed - $(date)"
        sleep 2
        if grep -q "Mail server setup completed" /var/log/mail.log; then
            log_success "Mail logging verified"
        fi
    else
        log_warning "Mail logging not configured"
    fi
}

# Display final summary (UPDATED)
display_completion_summary() {
    echo ""
    echo "=========================================="
    echo "🚀 MODULAR MAIL SERVER v7.1 COMPLETED!"
    echo "=========================================="
    echo ""
    echo "📧 Server Information:"
    echo "Domain: $DOMAIN"
    echo "Hostname: $HOSTNAME"
    echo "Server IP: $SERVER_IP"
    echo "Setup completed: $(date)"
    echo ""
    echo "🛠️ Core Management Commands:"
    echo "/opt/mailserver/bin/mail-status      - Check server status"
    echo "/opt/mailserver/bin/mail-test        - Test basic functionality"
    echo "/opt/mailserver/bin/mail-user        - Manage users"
    echo "/opt/mailserver/bin/mail-forward     - Manage forwarding"
    echo "/opt/mailserver/bin/mail-ssl         - SSL management"
    echo "/opt/mailserver/bin/mail-restart     - Restart services"
    echo ""
    echo "🔧 New Enhanced Tools:"
    echo "/opt/mailserver/bin/mail-fix         - Comprehensive fixes"
    echo "/opt/mailserver/bin/mail-logs        - Log monitoring"
    echo "/opt/mailserver/bin/mail-test-all    - Complete testing"
    echo "/opt/mailserver/bin/mail-dns-guide   - DNS setup guide"
    echo ""
    echo "📋 IMPORTANT NEXT STEPS:"
    echo "========================"
    echo "1. 🌐 Configure DNS records:"
    echo "   Run: mail-dns-guide"
    echo ""
    echo "2. ⏰ Wait 15-30 minutes for DNS propagation"
    echo ""
    echo "3. 🔒 Set up SSL certificates:"
    echo "   Run: mail-fix ssl"
    echo ""
    echo "4. 🧪 Run comprehensive tests:"
    echo "   Run: mail-test-all"
    echo ""
    echo "5. 📧 Test email with external clients"
    echo ""
    echo "🚨 TROUBLESHOOTING:"
    echo "==================="
    echo "• Check logs: mail-logs tail"
    echo "• Fix issues: mail-fix comprehensive"
    echo "• Monitor: tail -f /var/log/mail.log"
    echo ""
    echo "✅ All modules installed and configured!"
    echo "Mail server is ready for DNS configuration and SSL setup."
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
