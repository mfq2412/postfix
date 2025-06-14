#!/bin/bash

# ==========================================
# NGINX SETUP MODULE
# Nginx autodiscovery configuration
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main Nginx setup function
setup_nginx() {
    log_step "CONFIGURING NGINX FOR EMAIL AUTODISCOVERY"
    
    backup_nginx_config
    configure_nginx_autodiscovery
    test_nginx_config
    
    log_success "Nginx configuration completed"
}

# Backup current nginx configuration
backup_nginx_config() {
    log_info "Backing up Nginx configuration..."
    
    if [ -f /etc/nginx/sites-available/default ]; then
        backup_config "/etc/nginx/sites-available/default"
    fi
}

# Configure nginx for autodiscovery
configure_nginx_autodiscovery() {
    log_info "Configuring Nginx autodiscovery..."
    
    cat > /etc/nginx/sites-available/autodiscover <<EOF
# Email autodiscovery configuration

server {
    listen 80;
    server_name autodiscover.$DOMAIN autoconfig.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name autodiscover.$DOMAIN;
    
    # Basic SSL configuration (will be updated by SSL module)
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location /autodiscover/autodiscover.xml {
        add_header Content-Type "application/xml";
        return 200 '<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/responseschema/2006">
  <Response xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a">
    <Account>
      <AccountType>email</AccountType>
      <Action>settings</Action>
      <Protocol>
        <Type>IMAP</Type>
        <Server>$HOSTNAME</Server>
        <Port>993</Port>
        <DomainRequired>off</DomainRequired>
        <LoginName>%EMAILADDRESS%</LoginName>
        <SPA>off</SPA>
        <SSL>on</SSL>
        <AuthRequired>on</AuthRequired>
      </Protocol>
      <Protocol>
        <Type>SMTP</Type>
        <Server>$HOSTNAME</Server>
        <Port>587</Port>
        <DomainRequired>off</DomainRequired>
        <LoginName>%EMAILADDRESS%</LoginName>
        <SPA>off</SPA>
        <Encryption>TLS</Encryption>
        <AuthRequired>on</AuthRequired>
        <UsePOPAuth>on</UsePOPAuth>
      </Protocol>
    </Account>
  </Response>
</Autodiscover>';
    }
}

server {
    listen 443 ssl http2;
    server_name autoconfig.$DOMAIN;
    
    # Basic SSL configuration
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location /mail/config-v1.1.xml {
        add_header Content-Type "application/xml";
        return 200 '<?xml version="1.0" encoding="UTF-8"?>
<clientConfig version="1.1">
  <emailProvider id="$DOMAIN">
    <domain>$DOMAIN</domain>
    <displayName>$DOMAIN Mail</displayName>
    <displayShortName>$DOMAIN</displayShortName>
    <incomingServer type="imap">
      <hostname>$HOSTNAME</hostname>
      <port>993</port>
      <socketType>SSL</socketType>
      <authentication>password-cleartext</authentication>
      <username>%EMAILADDRESS%</username>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>$HOSTNAME</hostname>
      <port>587</port>
      <socketType>STARTTLS</socketType>
      <authentication>password-cleartext</authentication>
      <username>%EMAILADDRESS%</username>
    </outgoingServer>
  </emailProvider>
</clientConfig>';
    }
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/autodiscover /etc/nginx/sites-enabled/
    
    # Remove default site if it exists
    rm -f /etc/nginx/sites-enabled/default
    
    # Create web directory for Let's Encrypt
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    
    log_success "Nginx autodiscovery configuration created"
}

# Test nginx configuration
test_nginx_config() {
    log_info "Testing Nginx configuration..."
    
    if test_config "nginx"; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration test failed"
        return 1
    fi
}

# Start nginx service
start_nginx() {
    log_info "Starting Nginx service..."
    
    systemctl enable nginx
    if systemctl start nginx; then
        sleep 2
        if systemctl is-active --quiet nginx; then
            log_success "Nginx started successfully"
            
            # Check if ports are listening
            if ss -tuln | grep -q ":80 " && ss -tuln | grep -q ":443 "; then
                log_success "Nginx ports (80, 443) are active"
            else
                log_warning "Nginx ports may not be fully active yet"
            fi
        else
            log_error "Nginx started but then stopped"
            return 1
        fi
    else
        log_error "Failed to start Nginx"
        return 1
    fi
}

# Show nginx status
show_nginx_status() {
    echo "Nginx Status:"
    echo "============="
    
    if systemctl is-active --quiet nginx; then
        echo "✅ Service: Running"
    else
        echo "❌ Service: Not running"
    fi
    
    if ss -tuln | grep -q ":80 "; then
        echo "✅ HTTP port 80: Active"
    else
        echo "❌ HTTP port 80: Inactive"
    fi
    
    if ss -tuln | grep -q ":443 "; then
        echo "✅ HTTPS port 443: Active"
    else
        echo "❌ HTTPS port 443: Inactive"
    fi
    
    if [ -f /etc/nginx/sites-enabled/autodiscover ]; then
        echo "✅ Autodiscovery: Configured"
    else
        echo "❌ Autodiscovery: Not configured"
    fi
}

# Run nginx setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            setup_nginx
            ;;
        "start")
            start_nginx
            ;;
        "status")
            show_nginx_status
            ;;
        *)
            echo "Usage: $0 {setup|start|status}"
            exit 1
            ;;
    esac
fi
