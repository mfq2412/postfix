#!/bin/bash

# ==========================================
# OPENDKIM SETUP MODULE
# DKIM signing configuration
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main OpenDKIM setup function
setup_opendkim() {
    log_step "CONFIGURING OPENDKIM FOR DKIM SIGNING"
    
    generate_dkim_keys
    configure_opendkim_main
    create_opendkim_tables
    setup_systemd_service
    test_opendkim_config
    
    log_success "OpenDKIM configuration completed"
}

# Generate DKIM keys
generate_dkim_keys() {
    log_info "Generating DKIM keys..."
    
    local key_dir="/etc/opendkim/keys/$DOMAIN"
    
    if [ ! -f "$key_dir/$DKIM_SELECTOR.private" ]; then
        log_info "Creating DKIM key pair..."
        cd "$key_dir"
        opendkim-genkey -b 2048 -d "$DOMAIN" -s "$DKIM_SELECTOR"
        
        # Set proper ownership and permissions
        chown opendkim:opendkim "$key_dir/$DKIM_SELECTOR".*
        chmod 600 "$key_dir/$DKIM_SELECTOR.private"
        chmod 644 "$key_dir/$DKIM_SELECTOR.txt"
        
        log_success "DKIM keys generated successfully"
    else
        log_info "DKIM keys already exist"
    fi
}

# Configure main OpenDKIM settings
configure_opendkim_main() {
    log_info "Configuring OpenDKIM main settings..."
    
    cat > /etc/opendkim.conf <<EOF
# OpenDKIM Configuration for DKIM Signing

# Basic settings
Syslog                  yes
UMask                   002
Domain                  $DOMAIN
KeyFile                 /etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.private
Selector                $DKIM_SELECTOR
Socket                  inet:12301@localhost
UserID                  opendkim:opendkim
Mode                    sv

# Canonicalization and algorithms
Canonicalization        relaxed/simple
SignatureAlgorithm      rsa-sha256
MinimumKeyBits          1024
RequireSafeKeys         no

# Tables and lists
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable

# Logging and monitoring
LogWhy                  yes
PidFile                 /run/opendkim/opendkim.pid
AlwaysAddARHeader       yes
AutoRestart             yes
AutoRestartRate         10/1h
SendReports             yes
ReportAddress           $ADMIN_EMAIL

# Signing configuration
OversignHeaders         From
EOF
}

# Create OpenDKIM tables
create_opendkim_tables() {
    log_info "Creating OpenDKIM tables..."
    
    # Create TrustedHosts
    cat > /etc/opendkim/TrustedHosts <<EOF
# Trusted hosts for DKIM signing
127.0.0.1
localhost
$SERVER_IP
*.$DOMAIN
$DOMAIN
imap.$DOMAIN
mail.$DOMAIN
smtp.$DOMAIN
0.0.0.0/0
EOF

    # Create KeyTable
    cat > /etc/opendkim/KeyTable <<EOF
# DKIM key table
$DKIM_SELECTOR._domainkey.$DOMAIN $DOMAIN:$DKIM_SELECTOR:/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.private
EOF

    # Create SigningTable
    cat > /etc/opendkim/SigningTable <<EOF
# DKIM signing table
*@$DOMAIN $DKIM_SELECTOR._domainkey.$DOMAIN
$DOMAIN $DKIM_SELECTOR._domainkey.$DOMAIN
*.$DOMAIN $DKIM_SELECTOR._domainkey.$DOMAIN
$ADMIN_EMAIL $DKIM_SELECTOR._domainkey.$DOMAIN
EOF

    # Set permissions
    chown -R opendkim:opendkim /etc/opendkim
    chmod 644 /etc/opendkim/TrustedHosts
    chmod 644 /etc/opendkim/KeyTable
    chmod 644 /etc/opendkim/SigningTable
}

# Setup systemd service
setup_systemd_service() {
    log_info "Configuring OpenDKIM systemd service..."
    
    mkdir -p /etc/systemd/system/opendkim.service.d
    cat > /etc/systemd/system/opendkim.service.d/override.conf <<EOF
[Unit]
After=network.target

[Service]
ExecStartPre=/bin/mkdir -p /run/opendkim
ExecStartPre=/bin/chown opendkim:opendkim /run/opendkim
PIDFile=/run/opendkim/opendkim.pid
User=opendkim
Group=opendkim
Restart=on-failure
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

# Test OpenDKIM configuration
test_opendkim_config() {
    log_info "Testing OpenDKIM configuration..."
    
    if test_config "opendkim"; then
        log_success "OpenDKIM configuration is valid"
        
        # Display public key for DNS
        if [ -f "/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.txt" ]; then
            log_info "DKIM public key for DNS:"
            echo "=========================="
            cat "/etc/opendkim/keys/$DOMAIN/$DKIM_SELECTOR.txt"
            echo "=========================="
        fi
    else
        log_error "OpenDKIM configuration test failed"
        exit 1
    fi
}

# Run OpenDKIM setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_opendkim
fi