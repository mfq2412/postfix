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
    
    # Try to
