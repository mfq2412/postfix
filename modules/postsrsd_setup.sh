#!/bin/bash

# ==========================================
# POSTSRSD SETUP MODULE
# PostSRSD for email forwarding and SRS
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main PostSRSD setup function
setup_postsrsd() {
    log_step "CONFIGURING POSTSRSD FOR EMAIL FORWARDING"
    
    generate_srs_secret
    configure_postsrsd_main
    setup_postsrsd_systemd
    test_postsrsd_config
    
    log_success "PostSRSD configuration completed"
}

# Generate SRS secret
generate_srs_secret() {
    log_info "Generating SRS secret..."
    
    if [ ! -f /etc/postsrsd/postsrsd.secret ]; then
        # Create secret directory
        mkdir -p /etc/postsrsd
        
        # Generate random secret
        dd if=/dev/urandom bs=18 count=1 2>/dev/null | base64 > /etc/postsrsd/postsrsd.secret
        
        # Set proper permissions
        chmod 600 /etc/postsrsd/postsrsd.secret
        chown postsrsd:postsrsd /etc/postsrsd/postsrsd.secret 2>/dev/null || chown root:root /etc/postsrsd/postsrsd.secret
        
        log_success "SRS secret generated"
    else
        log_info "SRS secret already exists"
    fi
}

# Configure main PostSRSD settings
configure_postsrsd_main() {
    log_info "Configuring PostSRSD main settings..."
    
    # First, create the configuration file in the format PostSRSD expects
    cat > /etc/postsrsd/postsrsd.conf <<EOF
# PostSRSD Configuration for Email Forwarding
# Domain to use for SRS rewriting
SRS_DOMAIN=$DOMAIN

# Domains to exclude from SRS rewriting  
SRS_EXCLUDE_DOMAINS=$DOMAIN

# SRS separator character
SRS_SEPARATOR==

# Path to secret file
SRS_SECRET=/etc/postsrsd/postsrsd.secret

# User to run as
RUN_AS=postsrsd

# Chroot directory
CHROOT=/var/lib/postsrsd

# Listening ports
SRS_FORWARD_PORT=10001
SRS_REVERSE_PORT=10002

# Bind to localhost only for security
SRS_LISTEN_ADDR=127.0.0.1
EOF

    # Also create the default configuration file that PostSRSD looks for
    cat > /etc/default/postsrsd <<EOF
# PostSRSD configuration
# Domain for SRS rewriting
SRS_DOMAIN=$DOMAIN

# Exclude domains from rewriting
SRS_EXCLUDE_DOMAINS=$DOMAIN

# SRS separator
SRS_SEPARATOR="="

# Secret file
SRS_SECRET=/etc/postsrsd/postsrsd.secret

# Forward port
SRS_FORWARD_PORT=10001

# Reverse port
SRS_REVERSE_PORT=10002

# Listen address
SRS_LISTEN_ADDR=127.0.0.1

# User
RUN_AS=postsrsd

# Chroot
CHROOT=/var/lib/postsrsd
EOF

    # Set proper permissions
    chown root:postsrsd /etc/postsrsd/postsrsd.conf 2>/dev/null || chown root:root /etc/postsrsd/postsrsd.conf
    chmod 640 /etc/postsrsd/postsrsd.conf
    
    chown root:root /etc/default/postsrsd
    chmod 644 /etc/default/postsrsd
    
    log_success "PostSRSD configuration created"
}

# Setup systemd service
setup_postsrsd_systemd() {
    log_info "Configuring PostSRSD systemd service..."
    
    # Create systemd override directory
    mkdir -p /etc/systemd/system/postsrsd.service.d
    
    # Create override configuration with explicit domain parameter
    cat > /etc/systemd/system/postsrsd.service.d/override.conf <<EOF
[Unit]
Description=PostSRSD (Sender Rewriting Scheme)
After=network.target

[Service]
# Clear any existing ExecStart directives
ExecStart=
# Set our custom ExecStart with explicit domain parameter
ExecStart=/usr/sbin/postsrsd -d $DOMAIN -s /etc/postsrsd/postsrsd.secret -u postsrsd -c /var/lib/postsrsd -f 10001 -r 10002 -a 127.0.0.1
Type=forking
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/run/postsrsd.pid
User=postsrsd
Group=postsrsd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    log_success "PostSRSD systemd service configured"
}

# Test PostSRSD configuration
test_postsrsd_config() {
    log_info "Testing PostSRSD configuration..."
    
    # Check if configuration file exists and is readable
    if [ -f /etc/postsrsd/postsrsd.conf ] && [ -r /etc/postsrsd/postsrsd.conf ]; then
        log_success "PostSRSD configuration file is present and readable"
    else
        log_error "PostSRSD configuration file is missing or not readable"
        return 1
    fi
    
    # Check if secret file exists
    if [ -f /etc/postsrsd/postsrsd.secret ] && [ -r /etc/postsrsd/postsrsd.secret ]; then
        log_success "PostSRSD secret file is present and readable"
    else
        log_error "PostSRSD secret file is missing or not readable"
        return 1
    fi
    
    log_success "PostSRSD configuration tests passed"
}

# Function to start PostSRSD service
start_postsrsd() {
    log_info "Starting PostSRSD service..."
    
    systemctl enable postsrsd
    if systemctl start postsrsd; then
        sleep 2
        if systemctl is-active --quiet postsrsd; then
            log_success "PostSRSD started successfully"
            
            # Check if ports are listening
            sleep 3
            if ss -tuln | grep -q ":10001 " && ss -tuln | grep -q ":10002 "; then
                log_success "PostSRSD ports (10001, 10002) are active"
            else
                log_warning "PostSRSD ports may not be fully active yet"
            fi
        else
            log_error "PostSRSD started but then stopped"
            return 1
        fi
    else
        log_error "Failed to start PostSRSD"
        return 1
    fi
}

# Function to show PostSRSD status
show_postsrsd_status() {
    echo "PostSRSD Status:"
    echo "==============="
    
    if systemctl is-active --quiet postsrsd; then
        echo "✅ Service: Running"
    else
        echo "❌ Service: Not running"
    fi
    
    if ss -tuln | grep -q ":10001 "; then
        echo "✅ Forward port 10001: Active"
    else
        echo "❌ Forward port 10001: Inactive"
    fi
    
    if ss -tuln | grep -q ":10002 "; then
        echo "✅ Reverse port 10002: Active"
    else
        echo "❌ Reverse port 10002: Inactive"
    fi
    
    if [ -f /etc/postsrsd/postsrsd.conf ]; then
        echo "✅ Configuration: Present"
    else
        echo "❌ Configuration: Missing"
    fi
}

# Run PostSRSD setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            setup_postsrsd
            ;;
        "start")
            start_postsrsd
            ;;
        "status")
            show_postsrsd_status
            ;;
        *)
            echo "Usage: $0 {setup|start|status}"
            exit 1
            ;;
    esac
fi
