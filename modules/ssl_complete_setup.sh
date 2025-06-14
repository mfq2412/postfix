#!/bin/bash

# ==========================================
# COMPLETE SSL SETUP MODULE
# Comprehensive SSL configuration for all mail services
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main SSL setup function
setup_complete_ssl() {
    log_step "SETTING UP COMPLETE SSL CONFIGURATION"
    
    prepare_ssl_environment
    obtain_letsencrypt_certificates
    configure_postfix_ssl
    configure_dovecot_ssl
    configure_nginx_ssl
    setup_ssl_renewal
    verify_ssl_configuration
    
    log_success "Complete SSL configuration completed"
}

# Prepare SSL environment
prepare_ssl_environment() {
    log_info "Preparing SSL environment..."
    
    # Ensure all DNS domains are properly configured
    local required_domains=(
        "$HOSTNAME"
        "imap.$DOMAIN"
        "mail.$DOMAIN"
        "autodiscover.$DOMAIN"
        "autoconfig.$DOMAIN"
    )
    
    echo "Required DNS A records for SSL certificates:"
    for domain in "${required_domains[@]}"; do
        echo "  $domain IN A $SERVER_IP"
    done
    
    # Stop nginx temporarily for standalone certificate acquisition
    systemctl stop nginx || true
    
    # Create webroot directory for certificate challenges
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    
    log_success "SSL environment prepared"
}

# Obtain Let's Encrypt certificates
obtain_letsencrypt_certificates() {
    log_info "Obtaining Let's Encrypt certificates..."
    
    # Build domain list for certificate
    local domain_args=""
    local ssl_domains=(
        "$HOSTNAME"
        "imap.$DOMAIN"
        "mail.$DOMAIN"
        "autodiscover.$DOMAIN"
        "autoconfig.$DOMAIN"
    )
    
    for domain in "${ssl_domains[@]}"; do
        domain_args="$domain_args -d $domain"
    done
    
    # Try to obtain certificate using standalone method
    log_info "Requesting certificate for domains: ${ssl_domains[*]}"
    
    # Use standalone method initially
    if certbot certonly --standalone \
        $domain_args \
        --email "$ADMIN_EMAIL" \
        --agree-tos \
        --non-interactive \
        --expand \
        --preferred-challenges http; then
        
        log_success "SSL certificates obtained successfully!"
        
        # Set proper permissions
        chmod 755 /etc/letsencrypt/live
        chmod 755 /etc/letsencrypt/archive
        chmod 644 /etc/letsencrypt/live/"$HOSTNAME"/*.pem
        
    else
        log_error "Failed to obtain SSL certificates"
        log_info "Please ensure DNS records are properly configured and propagated"
        log_info "You can run this script again after DNS propagation (usually 5-15 minutes)"
        return 1
    fi
}

# Configure Postfix SSL
configure_postfix_ssl() {
    log_info "Configuring Postfix SSL..."
    
    local cert_path="/etc/letsencrypt/live/$HOSTNAME"
    
    if [ -d "$cert_path" ]; then
        # Update Postfix SSL configuration
        postconf -e "smtpd_tls_cert_file = $cert_path/fullchain.pem"
        postconf -e "smtpd_tls_key_file = $cert_path/privkey.pem"
        postconf -e "smtpd_tls_CApath = /etc/ssl/certs"
        postconf -e "smtpd_tls_CAfile = $cert_path/chain.pem"
        
        # Enhanced TLS settings
        postconf -e "smtpd_tls_security_level = may"
        postconf -e "smtp_tls_security_level = may"
        postconf -e "smtpd_tls_auth_only = yes"
        postconf -e "smtpd_tls_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1"
        postconf -e "smtp_tls_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1"
        postconf -e "smtpd_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1"
        postconf -e "smtp_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1"
        
        # TLS session cache
        postconf -e "smtpd_tls_session_cache_database = btree:/var/lib/postfix/smtpd_scache"
        postconf -e "smtp_tls_session_cache_database = btree:/var/lib/postfix/smtp_scache"
        
        # TLS logging
        postconf -e "smtpd_tls_loglevel = 1"
        postconf -e "smtp_tls_loglevel = 1"
        
        log_success "Postfix SSL configured"
    else
        log_error "SSL certificate directory not found"
        return 1
    fi
}

# Configure Dovecot SSL
configure_dovecot_ssl() {
    log_info "Configuring Dovecot SSL..."
    
    local cert_path="/etc/letsencrypt/live/$HOSTNAME"
    
    if [ -d "$cert_path" ]; then
        # Update Dovecot SSL configuration
        sed -i "s|ssl_cert = <.*|ssl_cert = <$cert_path/fullchain.pem|" /etc/dovecot/dovecot.conf
        sed -i "s|ssl_key = <.*|ssl_key = <$cert_path/privkey.pem|" /etc/dovecot/dovecot.conf
        
        # Enhanced SSL settings
        sed -i "s|ssl_min_protocol = .*|ssl_min_protocol = TLSv1.2|" /etc/dovecot/dovecot.conf
        
        # Add SSL configuration if not present
        if ! grep -q "ssl_prefer_server_ciphers" /etc/dovecot/dovecot.conf; then
            cat >> /etc/dovecot/dovecot.conf <<EOF

# Enhanced SSL configuration
ssl_prefer_server_ciphers = yes
ssl_cipher_list = ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384
ssl_dh = </etc/dovecot/dh.pem
EOF
        fi
        
        # Generate DH parameters if not exist
        if [ ! -f /etc/dovecot/dh.pem ]; then
            log_info "Generating Dovecot DH parameters (this may take a while)..."
            openssl dhparam -out /etc/dovecot/dh.pem 2048
            chown root:dovecot /etc/dovecot/dh.pem
            chmod 640 /etc/dovecot/dh.pem
        fi
        
        log_success "Dovecot SSL configured"
    else
        log_error "SSL certificate directory not found"
        return 1
    fi
}

# Configure Nginx SSL
configure_nginx_ssl() {
    log_info "Configuring Nginx SSL..."
    
    local cert_path="/etc/letsencrypt/live/$HOSTNAME"
    
    if [ -d "$cert_path" ]; then
        # Update Nginx SSL configuration
        sed -i "s|ssl_certificate .*|ssl_certificate $cert_path/fullchain.pem;|" /etc/nginx/sites-available/autodiscover
        sed -i "s|ssl_certificate_key .*|ssl_certificate_key $cert_path/privkey.pem;|" /etc/nginx/sites-available/autodiscover
        
        # Enhanced SSL configuration
        cat > /etc/nginx/conf.d/ssl-params.conf <<'EOF'
# SSL Configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_stapling on;
ssl_stapling_verify on;

# Security headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOF
        
        # Update autodiscover configuration to include SSL params
        if ! grep -q "include /etc/nginx/conf.d/ssl-params.conf" /etc/nginx/sites-available/autodiscover; then
            sed -i '/ssl_protocols/a \    include /etc/nginx/conf.d/ssl-params.conf;' /etc/nginx/sites-available/autodiscover
        fi
        
        log_success "Nginx SSL configured"
    else
        log_error "SSL certificate directory not found"
        return 1
    fi
}

# Setup SSL certificate renewal
setup_ssl_renewal() {
    log_info "Setting up SSL certificate renewal..."
    
    # Create renewal hook script
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/mail-server-reload.sh <<'EOF'
#!/bin/bash
# Auto-reload mail services after certificate renewal

# Log renewal
echo "$(date): SSL certificates renewed for mail server" >> /var/log/ssl-renewal.log

# Reload services
/usr/bin/systemctl reload postfix
/usr/bin/systemctl reload dovecot  
/usr/bin/systemctl reload nginx

# Send notification email
echo "SSL certificates have been renewed for $(hostname)" | \
    mail -s "SSL Certificate Renewal - $(hostname)" admin@${DOMAIN} 2>/dev/null || true

echo "$(date): Mail services reloaded after SSL renewal" >> /var/log/ssl-renewal.log
EOF
    
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/mail-server-reload.sh
    
    # Test renewal process
    log_info "Testing certificate renewal process..."
    if certbot renew --dry-run; then
        log_success "Certificate renewal test passed"
    else
        log_warning "Certificate renewal test failed - manual intervention may be needed"
    fi
    
    # Create custom renewal service for better control
    cat > /etc/systemd/system/certbot-renewal.service <<EOF
[Unit]
Description=Certbot Renewal Service
After=network.target

[Service]
Type=oneshot
ExecStartPre=/bin/systemctl stop nginx
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "/etc/letsencrypt/renewal-hooks/deploy/mail-server-reload.sh"
ExecStartPost=/bin/systemctl start nginx
EOF
    
    cat > /etc/systemd/system/certbot-renewal.timer <<EOF
[Unit]
Description=Certbot Renewal Timer
Requires=certbot-renewal.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable certbot-renewal.timer
    systemctl start certbot-renewal.timer
    
    log_success "SSL renewal configured"
}

# Verify SSL configuration
verify_ssl_configuration() {
    log_info "Verifying SSL configuration..."
    
    local cert_path="/etc/letsencrypt/live/$HOSTNAME"
    
    # Check certificate validity
    if [ -f "$cert_path/fullchain.pem" ]; then
        local expiry=$(openssl x509 -enddate -noout -in "$cert_path/fullchain.pem" | cut -d= -f2)
        local expiry_timestamp=$(date -d "$expiry" +%s)
        local current_timestamp=$(date +%s)
        local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
        
        echo "✅ Certificate Status:"
        echo "  Path: $cert_path"
        echo "  Expires: $expiry"
        echo "  Days until expiry: $days_until_expiry"
        
        # Check certificate domains
        echo ""
        echo "✅ Certificate Domains:"
        openssl x509 -text -noout -in "$cert_path/fullchain.pem" | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g' | tr ',' '\n' | sed 's/^/  /'
        
        if [ $days_until_expiry -lt 30 ]; then
            log_warning "Certificate expires in $days_until_expiry days - consider renewal"
        else
            log_success "Certificate is valid for $days_until_expiry days"
        fi
    else
        log_error "Certificate not found at $cert_path"
        return 1
    fi
    
    # Test SSL connections
    test_ssl_connections
}

# Test SSL connections
test_ssl_connections() {
    log_info "Testing SSL connections..."
    
    local services=(
        "SMTP:$HOSTNAME:587"
        "SMTPS:$HOSTNAME:465"
        "IMAPS:$HOSTNAME:993"
        "POP3S:$HOSTNAME:995"
        "HTTPS:autodiscover.$DOMAIN:443"
        "HTTPS:autoconfig.$DOMAIN:443"
    )
    
    for service_info in "${services[@]}"; do
        local service=$(echo "$service_info" | cut -d: -f1)
        local host=$(echo "$service_info" | cut -d: -f2)
        local port=$(echo "$service_info" | cut -d: -f3)
        
        if timeout 10 openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
            echo "✅ $service ($host:$port): SSL OK"
        else
            echo "❌ $service ($host:$port): SSL Failed"
        fi
    done
}

# Function to check SSL status
check_ssl_status() {
    echo "SSL Configuration Status"
    echo "======================="
    
    local cert_path="/etc/letsencrypt/live/$HOSTNAME"
    
    if [ -d "$cert_path" ]; then
        echo "✅ Let's Encrypt certificates: Present"
        
        local expiry=$(openssl x509 -enddate -noout -in "$cert_path/fullchain.pem" | cut -d= -f2)
        echo "📅 Certificate expires: $expiry"
        
        echo ""
        echo "📋 Service SSL Configuration:"
        
        # Check Postfix
        if postconf smtpd_tls_cert_file | grep -q letsencrypt; then
            echo "✅ Postfix: Using Let's Encrypt"
        else
            echo "❌ Postfix: Not using Let's Encrypt"
        fi
        
        # Check Dovecot
        if grep -q letsencrypt /etc/dovecot/dovecot.conf; then
            echo "✅ Dovecot: Using Let's Encrypt"
        else
            echo "❌ Dovecot: Not using Let's Encrypt"
        fi
        
        # Check Nginx
        if grep -q letsencrypt /etc/nginx/sites-available/autodiscover; then
            echo "✅ Nginx: Using Let's Encrypt"
        else
            echo "❌ Nginx: Not using Let's Encrypt"
        fi
        
    else
        echo "❌ Let's Encrypt certificates: Not found"
        echo "💡 Run: ssl_complete_setup.sh obtain"
    fi
    
    # Check renewal configuration
    if systemctl is-enabled --quiet certbot-renewal.timer; then
        echo "✅ Auto-renewal: Configured"
    else
        echo "❌ Auto-renewal: Not configured"
    fi
}

# Function to force SSL renewal
force_ssl_renewal() {
    log_info "Forcing SSL certificate renewal..."
    
    # Stop services
    systemctl stop nginx postfix dovecot
    
    # Force renewal
    certbot renew --force-renewal
    
    # Reconfigure services
    configure_postfix_ssl
    configure_dovecot_ssl
    configure_nginx_ssl
    
    # Restart services
    systemctl start nginx postfix dovecot
    
    log_success "SSL renewal completed"
}

# Run SSL setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            setup_complete_ssl
            ;;
        "obtain")
            obtain_letsencrypt_certificates
            ;;
        "renew")
            force_ssl_renewal
            ;;
        "status")
            check_ssl_status
            ;;
        "test")
            test_ssl_connections
            ;;
        *)
            echo "Usage: $0 {setup|obtain|renew|status|test}"
            echo ""
            echo "Commands:"
            echo "  setup   - Complete SSL setup for mail server"
            echo "  obtain  - Obtain Let's Encrypt certificates"
            echo "  renew   - Force certificate renewal"
            echo "  status  - Check SSL configuration status"
            echo "  test    - Test SSL connections"
            exit 1
            ;;
    esac
fi
