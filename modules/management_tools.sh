#!/bin/bash

# ==========================================
# MANAGEMENT TOOLS MODULE
# Create management scripts and tools
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main function to create all management tools
create_management_tools() {
    log_step "CREATING MANAGEMENT TOOLS"
    
    create_bin_directory
    create_mail_status_tool
    create_mail_test_tool
    create_mail_user_tool
    create_mail_forward_tool
    create_mail_ssl_tool
    create_mail_restart_tool
    create_dkim_test_tool
    create_port_fix_tool
    
    log_success "All management tools created"
}

# Create bin directory
create_bin_directory() {
    mkdir -p "$BIN_DIR"
    chmod 755 "$BIN_DIR"
}

# Create mail status tool
create_mail_status_tool() {
    cat > "$BIN_DIR/mail-status" << 'EOFSTATUS'
#!/bin/bash

# Mail Server Status Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

echo "Mail Server Status Report"
echo "========================"
echo "Generated: $(date)"
echo ""

# Service status
echo "Services:"
echo "---------"
for service in "${SERVICES[@]}"; do
    if is_service_running "$service"; then
        printf "%-12s: ✅ Running\n" "$service"
    else
        printf "%-12s: ❌ Stopped\n" "$service"
    fi
done

echo ""
echo "Ports:"
echo "------"
check_all_ports

echo ""
echo "Connectivity Test:"
echo "-----------------"
for port in "${CRITICAL_PORTS[@]}"; do
    if test_port_connectivity "$port"; then
        echo "✅ Port $port: OK"
    else
        echo "❌ Port $port: Failed"
    fi
done

echo ""
echo "Quick Actions:"
echo "  mail-test     - Run full functionality test"
echo "  mail-restart  - Restart all services"
echo "  mail-user     - Manage users"
echo "  mail-forward  - Manage forwarding"
EOFSTATUS

    chmod +x "$BIN_DIR/mail-status"
}

# Create mail test tool
create_mail_test_tool() {
    cat > "$BIN_DIR/mail-test" << 'EOFTEST'
#!/bin/bash

# Mail Server Test Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

echo "🧪 COMPLETE MAIL SERVER TEST"
echo "============================"

# Test all services
echo ""
echo "Service Test:"
all_services_ok=true
for service in "${SERVICES[@]}"; do
    if is_service_running "$service"; then
        echo "✅ $service: Running"
    else
        echo "❌ $service: Failed"
        all_services_ok=false
    fi
done

# Test all ports
echo ""
echo "Port Test:"
check_all_ports >/dev/null
failed_ports=$?

if [ $failed_ports -eq 0 ]; then
    echo "✅ All ports: Active"
else
    echo "❌ $failed_ports ports: Inactive"
fi

# Test connectivity
echo ""
echo "Connectivity Test:"
all_ports_connected=true
for port in "${CRITICAL_PORTS[@]}"; do
    if test_port_connectivity "$port"; then
        echo "✅ Port $port: Connected"
    else
        echo "❌ Port $port: Connection failed"
        all_ports_connected=false
    fi
done

# Test authentication
echo ""
echo "Authentication Test:"
auth_ok=true
if [ -f /etc/dovecot/users ] && [ -s /etc/dovecot/users ]; then
    echo "✅ User database: Present"
    
    # Test first user if exists
    first_user=$(head -n1 /etc/dovecot/users 2>/dev/null | cut -d: -f1)
    if [ -n "$first_user" ]; then
        echo "✅ Sample user: $first_user"
    fi
else
    echo "❌ User database: Missing"
    auth_ok=false
fi

# Overall result
echo ""
echo "=========================================="
if [ "$all_services_ok" = true ] && [ $failed_ports -eq 0 ] && [ "$all_ports_connected" = true ] && [ "$auth_ok" = true ]; then
    echo "🎉 MAIL SERVER: FULLY OPERATIONAL!"
    echo "✅ All tests passed"
else
    echo "⚠️  MAIL SERVER: ISSUES DETECTED"
    echo ""
    echo "Troubleshooting:"
    [ "$all_services_ok" = false ] && echo "  - Run: mail-restart"
    [ $failed_ports -ne 0 ] && echo "  - Run: /opt/mailserver/bin/fix-ports"
    [ "$all_ports_connected" = false ] && echo "  - Check firewall: ufw status"
    [ "$auth_ok" = false ] && echo "  - Run: mail-user add <email> <password>"
fi
echo "=========================================="
EOFTEST

    chmod +x "$BIN_DIR/mail-test"
}

# Create mail user management tool
create_mail_user_tool() {
    cat > "$BIN_DIR/mail-user" << 'EOFUSER'
#!/bin/bash

# Mail User Management Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

show_usage() {
    echo "Mail User Management Tool"
    echo "========================"
    echo ""
    echo "Usage: $0 {add|list|remove|change-password}"
    echo ""
    echo "Commands:"
    echo "  add <email> <password>        - Add new user"
    echo "  list                          - List all users"
    echo "  remove <email>                - Remove user"
    echo "  change-password <email> <new> - Change password"
    echo ""
    echo "Examples:"
    echo "  $0 add user@$DOMAIN mypassword123"
    echo "  $0 list"
    echo "  $0 remove user@$DOMAIN"
    exit 1
}

add_user() {
    local email="$1"
    local password="$2"
    
    if [ -z "$email" ] || [ -z "$password" ]; then
        echo "Error: Email and password required"
        show_usage
    fi
    
    if ! validate_email "$email"; then
        echo "Error: Invalid email format"
        exit 1
    fi
    
    if [ ${#password} -lt 6 ]; then
        echo "Error: Password must be at least 6 characters"
        exit 1
    fi
    
    # Check if user exists
    if grep -q "^$email:" /etc/dovecot/users 2>/dev/null; then
        echo "Error: User $email already exists"
        exit 1
    fi
    
    username=$(echo "$email" | cut -d'@' -f1)
    user_domain=$(echo "$email" | cut -d'@' -f2)
    
    # Create mailbox directories
    mkdir -p "/var/mail/vhosts/$user_domain/$username"/{cur,new,tmp}
    mkdir -p "/var/mail/vhosts/$user_domain/$username"/.{Drafts,Sent,Trash,Junk}/{cur,new,tmp}
    chown -R vmail:vmail "/var/mail/vhosts/$user_domain"
    
    # Generate password hash
    pass_hash=$(doveadm pw -s CRYPT -p "$password")
    
    # Add to dovecot users
    echo "$email:$pass_hash::::::" >> /etc/dovecot/users
    
    # Add to postfix virtual mailbox
    echo "$email $user_domain/$username/" >> /etc/postfix/vmailbox
    postmap /etc/postfix/vmailbox
    
    # Reload services
    systemctl reload dovecot
    systemctl reload postfix
    
    echo "✅ User $email created successfully"
    echo ""
    echo "Mail client settings:"
    echo "IMAP Server: $HOSTNAME (port 993 SSL)"
    echo "SMTP Server: $HOSTNAME (port 587 STARTTLS)"
    echo "Username: $email"
    echo "Password: $password"
}

list_users() {
    echo "Mail Users:"
    echo "==========="
    if [ -f /etc/dovecot/users ] && [ -s /etc/dovecot/users ]; then
        awk -F: '{print "📧 " $1}' /etc/dovecot/users
    else
        echo "No users found"
    fi
}

remove_user() {
    local email="$1"
    
    if [ -z "$email" ]; then
        echo "Error: Email required"
        show_usage
    fi
    
    if ! grep -q "^$email:" /etc/dovecot/users 2>/dev/null; then
        echo "Error: User $email not found"
        exit 1
    fi
    
    # Remove from dovecot users
    sed -i "/^$email:/d" /etc/dovecot/users
    
    # Remove from postfix virtual mailbox
    sed -i "/^$email /d" /etc/postfix/vmailbox
    postmap /etc/postfix/vmailbox
    
    # Reload services
    systemctl reload dovecot
    systemctl reload postfix
    
    echo "✅ User $email removed successfully"
}

change_password() {
    local email="$1"
    local new_password="$2"
    
    if [ -z "$email" ] || [ -z "$new_password" ]; then
        echo "Error: Email and new password required"
        show_usage
    fi
    
    if [ ${#new_password} -lt 6 ]; then
        echo "Error: Password must be at least 6 characters"
        exit 1
    fi
    
    if ! grep -q "^$email:" /etc/dovecot/users 2>/dev/null; then
        echo "Error: User $email not found"
        exit 1
    fi
    
    # Generate new password hash
    pass_hash=$(doveadm pw -s CRYPT -p "$new_password")
    
    # Update password in dovecot users file
    sed -i "s/^$email:.*/$email:$pass_hash::::::/" /etc/dovecot/users
    
    # Reload dovecot
    systemctl reload dovecot
    
    echo "✅ Password changed for $email"
}

case "${1:-}" in
    "add")
        add_user "$2" "$3"
        ;;
    "list")
        list_users
        ;;
    "remove")
        remove_user "$2"
        ;;
    "change-password")
        change_password "$2" "$3"
        ;;
    *)
        show_usage
        ;;
esac
EOFUSER

    chmod +x "$BIN_DIR/mail-user"
}

# Create remaining tools (forward, ssl, restart, dkim-test, fix-ports)
create_mail_forward_tool() {
    cat > "$BIN_DIR/mail-forward" << 'EOFFORWARD'
#!/bin/bash

# Mail Forwarding Management Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

show_usage() {
    echo "Mail Forwarding Management Tool"
    echo "==============================="
    echo ""
    echo "Usage: $0 {add|list|remove|test}"
    echo ""
    echo "Commands:"
    echo "  add <source> <destination>   - Add forwarding rule"
    echo "  list                         - List all rules"
    echo "  remove <source>              - Remove forwarding rule"
    echo "  test                         - Test configuration"
    echo ""
    exit 1
}

add_forwarding() {
    local source="$1"
    local destination="$2"
    
    if [ -z "$source" ] || [ -z "$destination" ]; then
        echo "Error: Source and destination required"
        show_usage
    fi
    
    echo "$source $destination" >> /etc/postfix/virtual
    postmap /etc/postfix/virtual
    systemctl reload postfix
    
    echo "✅ Forwarding added: $source → $destination"
}

list_forwarding() {
    echo "Email Forwarding Rules:"
    echo "======================"
    if [ -f /etc/postfix/virtual ] && [ -s /etc/postfix/virtual ]; then
        grep -v "^#" /etc/postfix/virtual | grep -v "^$" | while read line; do
            echo "📧 $line"
        done
    else
        echo "No forwarding rules found"
    fi
}

remove_forwarding() {
    local source="$1"
    
    if [ -z "$source" ]; then
        echo "Error: Source email required"
        show_usage
    fi
    
    if [ -f /etc/postfix/virtual ]; then
        sed -i "/^$source /d" /etc/postfix/virtual
        postmap /etc/postfix/virtual
        systemctl reload postfix
        echo "✅ Forwarding removed for: $source"
    else
        echo "Error: No forwarding rules file found"
    fi
}

test_forwarding() {
    echo "Testing Email Forwarding Configuration"
    echo "====================================="
    
    if [ ! -f /etc/postfix/virtual ] || [ ! -s /etc/postfix/virtual ]; then
        echo "❌ Virtual file missing or empty"
        return 1
    fi
    
    if [ ! -f /etc/postfix/virtual.db ]; then
        echo "❌ Virtual database missing"
        echo "Run: postmap /etc/postfix/virtual"
        return 1
    fi
    
    if ! postconf virtual_alias_maps | grep -q virtual; then
        echo "❌ Postfix not configured for virtual aliases"
        return 1
    fi
    
    echo "✅ Virtual file exists and configured"
    echo "✅ Virtual database exists"
    echo "✅ Postfix configured for forwarding"
    
    echo ""
    echo "Active forwarding rules:"
    list_forwarding
}

case "${1:-}" in
    "add")
        add_forwarding "$2" "$3"
        ;;
    "list")
        list_forwarding
        ;;
    "remove")
        remove_forwarding "$2"
        ;;
    "test")
        test_forwarding
        ;;
    *)
        show_usage
        ;;
esac
EOFFORWARD

    chmod +x "$BIN_DIR/mail-forward"
}

# Create SSL management tool
create_mail_ssl_tool() {
    cat > "$BIN_DIR/mail-ssl" << 'EOFSSL'
#!/bin/bash

# SSL Certificate Management Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

obtain_certificates() {
    echo "🔐 Obtaining SSL Certificates"
    echo "============================="
    
    # Stop nginx temporarily
    systemctl stop nginx
    sleep 5
    
    # Build certbot command with all domains
    local certbot_cmd="certbot certonly --standalone"
    for domain in "${SSL_DOMAINS[@]}"; do
        certbot_cmd="$certbot_cmd -d $domain"
    done
    certbot_cmd="$certbot_cmd --email $ADMIN_EMAIL --agree-tos --non-interactive --expand"
    
    if $certbot_cmd; then
        echo "✅ SSL certificates obtained successfully!"
        update_ssl_configs
        setup_auto_renewal
    else
        echo "❌ Failed to obtain SSL certificates"
        systemctl start nginx
        exit 1
    fi
    
    systemctl start nginx
}

update_ssl_configs() {
    echo "Updating SSL configurations..."
    
    # Update Postfix
    postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
    postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$HOSTNAME/privkey.pem"
    
    # Update Dovecot
    sed -i "s|ssl_cert = <.*|ssl_cert = </etc/letsencrypt/live/$HOSTNAME/fullchain.pem|" /etc/dovecot/dovecot.conf
    sed -i "s|ssl_key = <.*|ssl_key = </etc/letsencrypt/live/$HOSTNAME/privkey.pem|" /etc/dovecot/dovecot.conf
    
    # Update Nginx
    if [ -f /etc/nginx/sites-available/autodiscover ]; then
        sed -i "s|ssl_certificate .*|ssl_certificate /etc/letsencrypt/live/$HOSTNAME/fullchain.pem;|" /etc/nginx/sites-available/autodiscover
        sed -i "s|ssl_certificate_key .*|ssl_certificate_key /etc/letsencrypt/live/$HOSTNAME/privkey.pem;|" /etc/nginx/sites-available/autodiscover
    fi
    
    # Reload services
    systemctl reload postfix
    systemctl reload dovecot
    systemctl reload nginx
    
    echo "✅ SSL configurations updated"
}

setup_auto_renewal() {
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/mail-server-reload.sh <<'EOFRENEWAL'
#!/bin/bash
# Auto-reload mail services after certificate renewal

/usr/bin/systemctl reload postfix
/usr/bin/systemctl reload dovecot
/usr/bin/systemctl reload nginx

echo "$(date): Mail server certificates renewed and services reloaded" >> /var/log/letsencrypt-renewal.log
EOFRENEWAL
    
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/mail-server-reload.sh
    
    # Test renewal
    if certbot renew --dry-run; then
        echo "✅ Auto-renewal configured successfully"
    else
        echo "⚠️  Auto-renewal test failed"
    fi
}

check_certificates() {
    echo "SSL Certificate Status"
    echo "====================="
    
    if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
        local expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" | cut -d= -f2)
        echo "✅ Certificate: Valid"
        echo "📅 Expires: $expiry"
        
        echo ""
        echo "Certificate domains:"
        openssl x509 -text -noout -in "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g'
    else
        echo "⚠️  Using self-signed certificates"
        echo "Run: $0 obtain"
    fi
}

case "${1:-}" in
    "obtain")
        obtain_certificates
        ;;
    "status")
        check_certificates
        ;;
    "renew")
        certbot renew
        ;;
    *)
        echo "SSL Certificate Management Tool"
        echo "==============================="
        echo ""
        echo "Usage: $0 {obtain|status|renew}"
        echo ""
        echo "Commands:"
        echo "  obtain  - Obtain SSL certificates"
        echo "  status  - Check certificate status"
        echo "  renew   - Manually renew certificates"
        exit 1
        ;;
esac
EOFSSL

    chmod +x "$BIN_DIR/mail-ssl"
}

# Create restart tool
create_mail_restart_tool() {
    cat > "$BIN_DIR/mail-restart" << 'EOFRESTART'
#!/bin/bash

# Mail Service Restart Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

echo "🔄 Restarting Mail Services"
echo "==========================="

# Use service manager module
/opt/mailserver/modules/service_manager.sh restart_all

echo ""
echo "Final status check:"
/opt/mailserver/bin/mail-status
EOFRESTART

    chmod +x "$BIN_DIR/mail-restart"
}

# Create DKIM test tool
create_dkim_test_tool() {
    cat > "$BIN_DIR/dkim-test" << 'EOFDKIM'
#!/bin/bash

# DKIM Testing Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

echo "🔍 DKIM Configuration Test"
echo "=========================="

# Test OpenDKIM service
echo ""
echo "Service Status:"
if is_service_running "opendkim"; then
    echo "✅ OpenDKIM: Running"
else
    echo "❌ OpenDKIM: Not running"
    echo "Fix: systemctl start opendkim"
fi

# Test DKIM port
echo ""
echo "Port Status:"
if is_port_open "12301"; then
    echo "✅ DKIM port 12301: Open"
else
    echo "❌ DKIM port 12301: Closed"
fi

# Test DKIM keys
echo ""
echo "DKIM Keys:"
if [ -f "/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.private" ]; then
    echo "✅ Private key: Present"
else
    echo "❌ Private key: Missing"
fi

if [ -f "/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.txt" ]; then
    echo "✅ Public key: Present"
    echo ""
    echo "DNS Record for $DKIM_SELECTOR._domainkey.$DOMAIN:"
    echo "================================================"
    cat "/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.txt"
else
    echo "❌ Public key: Missing"
fi

# Test configuration
echo ""
echo "Configuration Test:"
if opendkim -n -f 2>/dev/null; then
    echo "✅ OpenDKIM config: Valid"
else
    echo "❌ OpenDKIM config: Invalid"
fi

# Test Postfix integration
echo ""
echo "Postfix Integration:"
if postconf smtpd_milters | grep -q "12301"; then
    echo "✅ Postfix milter: Configured"
else
    echo "❌ Postfix milter: Not configured"
fi

# Test connectivity
echo ""
echo "Connectivity Test:"
if test_port_connectivity "12301"; then
    echo "✅ DKIM milter: Responding"
else
    echo "❌ DKIM milter: Not responding"
fi
EOFDKIM

    chmod +x "$BIN_DIR/dkim-test"
}

# Create port fix tool
create_port_fix_tool() {
    cat > "$BIN_DIR/fix-ports" << 'EOFPORTS'
#!/bin/bash

# Port Fix Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

echo "🔧 Port Fix Tool"
echo "================"

# Use service manager module
/opt/mailserver/modules/service_manager.sh fix_ports
EOFPORTS

    chmod +x "$BIN_DIR/fix-ports"
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_management_tools
fi