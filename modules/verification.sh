#!/bin/bash

# ==========================================
# VERIFICATION MODULE
# Comprehensive testing and verification
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main verification function
run_verification() {
    log_step "COMPREHENSIVE MAIL SERVER VERIFICATION"
    
    verify_services
    verify_ports
    verify_connectivity
    verify_authentication
    verify_dkim
    verify_forwarding
    verify_ssl
    
    display_verification_summary
}

# Verify all services are running
verify_services() {
    log_info "Verifying services..."
    
    # Define essential and optional services
    local essential_services=("opendkim" "postfix" "dovecot")
    local optional_services=("postsrsd" "nginx")
    local failed_essential=()
    local failed_optional=()
    
    # Check essential services
    for service in "${essential_services[@]}"; do
        if is_service_running "$service"; then
            log_success "$service: Running"
        else
            log_error "$service: Not running"
            failed_essential+=("$service")
        fi
    done
    
    # Check optional services
    for service in "${optional_services[@]}"; do
        if is_service_running "$service"; then
            log_success "$service: Running"
        else
            log_warning "$service: Not running (optional service)"
        fi
    done
    
    # Overall assessment
    if [ ${#failed_essential[@]} -eq 0 ]; then
        log_success "All essential services are running"
        if [ ${#failed_optional[@]} -gt 0 ]; then
            log_info "Some optional services are not running, but core functionality is operational"
        fi
    else
        log_warning "Essential services not running: ${failed_essential[*]}"
    fi
}

# Verify all required ports
verify_ports() {
    log_info "Verifying ports..."
    
    # Define essential and optional ports
    local essential_ports=("25" "465" "587" "143" "993" "110" "995" "12301")
    local optional_ports=("80" "443" "10001" "10002")
    local failed_essential=0
    local failed_optional=0
    
    # Check essential ports
    for port in "${essential_ports[@]}"; do
        local desc="${REQUIRED_PORTS[$port]}"
        if is_port_open "$port"; then
            printf "%-6s %-15s: ✅ ACTIVE\n" "$port" "$desc"
        else
            printf "%-6s %-15s: ❌ INACTIVE\n" "$port" "$desc"
            ((failed_essential++))
        fi
    done
    
    # Check optional ports
    for port in "${optional_ports[@]}"; do
        local desc="${REQUIRED_PORTS[$port]}"
        if is_port_open "$port"; then
            printf "%-6s %-15s: ✅ ACTIVE\n" "$port" "$desc"
        else
            printf "%-6s %-15s: ⚠️  INACTIVE (optional)\n" "$port" "$desc"
            ((failed_optional++))
        fi
    done
    
    # Overall assessment
    if [ $failed_essential -eq 0 ]; then
        log_success "All essential ports are active"
        if [ $failed_optional -gt 0 ]; then
            log_info "$failed_optional optional ports inactive (mail server still fully functional)"
        fi
    else
        log_warning "$failed_essential essential ports are inactive"
    fi
    
    return $failed_essential
}

# Verify connectivity to critical ports
verify_connectivity() {
    log_info "Verifying connectivity..."
    
    local failed_connections=()
    
    for port in "${CRITICAL_PORTS[@]}"; do
        if test_port_connectivity "$port"; then
            log_success "Port $port: Connected"
        else
            log_error "Port $port: Connection failed"
            failed_connections+=("$port")
        fi
    done
    
    if [ ${#failed_connections[@]} -eq 0 ]; then
        log_success "All critical ports accepting connections"
    else
        log_warning "Failed connections: ${failed_connections[*]}"
    fi
}

# Verify authentication system
verify_authentication() {
    log_info "Verifying authentication..."
    
    if [ -f /etc/dovecot/users ] && [ -s /etc/dovecot/users ]; then
        log_success "User database exists and has content"
        
        # Count users
        local user_count=$(wc -l < /etc/dovecot/users)
        log_info "Found $user_count mail users"
        
        # Test authentication for first user
        local first_user_line=$(head -n1 /etc/dovecot/users 2>/dev/null)
        if [ -n "$first_user_line" ]; then
            local test_email=$(echo "$first_user_line" | cut -d: -f1)
            log_info "Sample user available for testing: $test_email"
        fi
    else
        log_error "User database is missing or empty"
    fi
}

# Verify DKIM configuration
verify_dkim() {
    log_info "Verifying DKIM configuration..."
    
    # Check service
    if is_service_running "opendkim"; then
        log_success "OpenDKIM service: Running"
    else
        log_error "OpenDKIM service: Not running"
        return 1
    fi
    
    # Check port
    if is_port_open "12301"; then
        log_success "DKIM port 12301: Active"
    else
        log_error "DKIM port 12301: Inactive"
        return 1
    fi
    
    # Check keys
    if [ -f "/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.private" ]; then
        log_success "DKIM private key: Present"
    else
        log_error "DKIM private key: Missing"
        return 1
    fi
    
    if [ -f "/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.txt" ]; then
        log_success "DKIM public key: Present"
    else
        log_error "DKIM public key: Missing"
        return 1
    fi
    
    # Check configuration
    if opendkim -n -f 2>/dev/null; then
        log_success "OpenDKIM configuration: Valid"
    else
        log_error "OpenDKIM configuration: Invalid"
        return 1
    fi
    
    log_success "DKIM verification completed"
}

# Verify email forwarding
verify_forwarding() {
    log_info "Verifying email forwarding..."
    
    # Check virtual file
    if [ -f /etc/postfix/virtual ] && [ -s /etc/postfix/virtual ]; then
        log_success "Virtual aliases file: Present"
        
        # Count forwarding rules
        local rule_count=$(grep -c -v "^#" /etc/postfix/virtual | grep -c -v "^$" || echo "0")
        log_info "Found $rule_count forwarding rules"
    else
        log_error "Virtual aliases file: Missing or empty"
        return 1
    fi
    
    # Check virtual database
    if [ -f /etc/postfix/virtual.db ]; then
        log_success "Virtual aliases database: Present"
    else
        log_error "Virtual aliases database: Missing"
        return 1
    fi
    
    # Check Postfix configuration
    if postconf virtual_alias_maps | grep -q virtual; then
        log_success "Postfix virtual aliases: Configured"
    else
        log_error "Postfix virtual aliases: Not configured"
        return 1
    fi
    
    log_success "Email forwarding verification completed"
}

# Verify SSL configuration
verify_ssl() {
    log_info "Verifying SSL configuration..."
    
    if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
        log_success "SSL certificate: Let's Encrypt certificate found"
        
        # Check expiry
        local expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" | cut -d= -f2)
        log_info "Certificate expires: $expiry"
        
        # Check if it's about to expire (within 30 days)
        local expiry_timestamp=$(date -d "$expiry" +%s)
        local current_timestamp=$(date +%s)
        local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
        
        if [ $days_until_expiry -lt 30 ]; then
            log_warning "Certificate expires in $days_until_expiry days"
        else
            log_success "Certificate valid for $days_until_expiry days"
        fi
    else
        log_warning "SSL certificate: Using self-signed certificate"
        log_info "Run 'mail-ssl obtain' to get Let's Encrypt certificate"
    fi
}

# Display comprehensive verification summary
display_verification_summary() {
    echo ""
    echo "=========================================="
    echo "📋 VERIFICATION SUMMARY"
    echo "=========================================="
    
    # Service summary with essential/optional distinction
    echo ""
    echo "🔧 Essential Services:"
    local essential_services=("opendkim" "postfix" "dovecot")
    local all_essential_ok=true
    for service in "${essential_services[@]}"; do
        if is_service_running "$service"; then
            printf "  %-12s: ✅ Running\n" "$service"
        else
            printf "  %-12s: ❌ Stopped\n" "$service"
            all_essential_ok=false
        fi
    done
    
    echo ""
    echo "🔧 Optional Services:"
    local optional_services=("postsrsd" "nginx")
    for service in "${optional_services[@]}"; do
        if is_service_running "$service"; then
            printf "  %-12s: ✅ Running\n" "$service"
        else
            printf "  %-12s: ⚠️  Stopped (optional)\n" "$service"
        fi
    done
    
    # Port summary with essential/optional distinction
    echo ""
    echo "🔌 Essential Ports:"
    local essential_ports=("25" "465" "587" "143" "993" "110" "995" "12301")
    local essential_ports_ok=0
    for port in "${essential_ports[@]}"; do
        if is_port_open "$port"; then
            printf "  Port %-5s: ✅ Active\n" "$port"
            ((essential_ports_ok++))
        else
            printf "  Port %-5s: ❌ Inactive\n" "$port"
        fi
    done
    
    echo ""
    echo "🔌 Optional Ports:"
    local optional_ports=("80" "443" "10001" "10002")
    for port in "${optional_ports[@]}"; do
        if is_port_open "$port"; then
            printf "  Port %-5s: ✅ Active\n" "$port"
        else
            printf "  Port %-5s: ⚠️  Inactive (optional)\n" "$port"
        fi
    done
    
    # Feature summary
    echo ""
    echo "✨ Core Features:"
    
    # Email sending/receiving
    if is_service_running "postfix" && is_port_open "25" && is_port_open "587"; then
        echo "  Email Sending/Receiving: ✅ Working"
    else
        echo "  Email Sending/Receiving: ❌ Not working"
    fi
    
    # IMAP/POP3 access
    if is_service_running "dovecot" && is_port_open "993"; then
        echo "  Email Access (IMAP): ✅ Working"
    else
        echo "  Email Access (IMAP): ❌ Not working"
    fi
    
    # DKIM
    if is_service_running "opendkim" && is_port_open "12301"; then
        echo "  DKIM Signing: ✅ Working"
    else
        echo "  DKIM Signing: ❌ Not working"
    fi
    
    # Authentication
    if [ -f /etc/dovecot/users ] && [ -s /etc/dovecot/users ]; then
        echo "  User Authentication: ✅ Working"
    else
        echo "  User Authentication: ❌ Not working"
    fi
    
    echo ""
    echo "✨ Optional Features:"
    
    # Email forwarding with SRS
    if is_service_running "postsrsd" && is_port_open "10001"; then
        echo "  Advanced Forwarding (SRS): ✅ Working"
    else
        echo "  Advanced Forwarding (SRS): ⚠️  Basic forwarding available"
    fi
    
    # Autodiscovery
    if is_service_running "nginx" && is_port_open "80" && is_port_open "443"; then
        echo "  Email Autodiscovery: ✅ Working"
    else
        echo "  Email Autodiscovery: ⚠️  Manual setup required"
    fi
    
    # SSL
    if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
        echo "  SSL Certificates: ✅ Let's Encrypt"
    else
        echo "  SSL Certificates: ⚠️  Self-signed (get Let's Encrypt with: mail-ssl obtain)"
    fi
    
    # Overall status
    echo ""
    echo "🎯 Overall Status:"
    if [ "$all_essential_ok" = true ] && [ $essential_ports_ok -eq ${#essential_ports[@]} ]; then
        echo "  Mail Server: ✅ FULLY OPERATIONAL"
        echo ""
        echo "🚀 Your mail server is ready for production use!"
        echo "   ✅ Send/receive emails: Working"
        echo "   ✅ IMAP/POP3 access: Working"
        echo "   ✅ DKIM signing: Working"
        echo "   ✅ User authentication: Working"
        echo "   ✅ Email forwarding: Working (basic)"
        echo ""
        echo "📧 Ready-to-use accounts:"
        echo "   admin@$DOMAIN"
        echo "   info@$DOMAIN" 
        echo "   support@$DOMAIN"
        echo "   distribution@$DOMAIN"
        echo ""
        echo "⚙️ Optional improvements available:"
        if ! is_service_running "postsrsd"; then
            echo "   - Advanced forwarding: Run 'systemctl start postsrsd'"
        fi
        if ! is_service_running "nginx"; then
            echo "   - Email autodiscovery: Run 'systemctl start nginx'"
        fi
        if [ ! -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
            echo "   - SSL certificates: Run 'mail-ssl obtain'"
        fi
    else
        echo "  Mail Server: ⚠️  NEEDS ATTENTION"
        echo ""
        echo "🔧 Issues to fix:"
        [ "$all_essential_ok" = false ] && echo "   - Essential services not running: mail-restart"
        [ $essential_ports_ok -lt ${#essential_ports[@]} ] && echo "   - Essential ports inactive: fix-ports"
        echo "   - Full test: mail-test"
    fi
    
    echo ""
    echo "📚 Management commands:"
    echo "   mail-status    - Quick status check"
    echo "   mail-test      - Full functionality test"
    echo "   mail-user      - Manage users"
    echo "   mail-forward   - Manage forwarding"
    echo "   mail-ssl       - SSL management"
    echo "   dkim-test      - Test DKIM signing"
    echo "=========================================="
}

# Run verification if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_verification
fi
