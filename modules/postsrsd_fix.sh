#!/bin/bash

# ==========================================
# POSTSRSD FIX MODULE
# Fix PostSRSD service issues
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main PostSRSD fix function
fix_postsrsd() {
    log_step "FIXING POSTSRSD SERVICE ISSUES"
    
    stop_postsrsd_service
    fix_permissions_and_directories
    regenerate_configuration
    fix_systemd_service
    start_and_verify_service
    
    log_success "PostSRSD service fix completed"
}

# Stop PostSRSD service
stop_postsrsd_service() {
    log_info "Stopping PostSRSD service..."
    
    systemctl stop postsrsd || true
    pkill -f postsrsd || true
    sleep 3
    
    log_success "PostSRSD service stopped"
}

# Fix permissions and directories
fix_permissions_and_directories() {
    log_info "Fixing PostSRSD permissions and directories..."
    
    # Ensure user exists
    if ! getent passwd postsrsd >/dev/null; then
        useradd --system --home-dir /var/lib/postsrsd --shell /bin/false postsrsd
        log_info "Created postsrsd user"
    fi
    
    # Create and fix directories
    mkdir -p /etc/postsrsd
    mkdir -p /var/lib/postsrsd
    mkdir -p /var/run/postsrsd
    
    # Fix ownership
    chown -R postsrsd:postsrsd /var/lib/postsrsd
    chown -R postsrsd:postsrsd /var/run/postsrsd
    chown root:root /etc/postsrsd
    
    # Fix permissions
    chmod 755 /var/lib/postsrsd
    chmod 755 /var/run/postsrsd
    chmod 755 /etc/postsrsd
    
    # Fix secret file if it exists
    if [ -f /etc/postsrsd/postsrsd.secret ]; then
        chown postsrsd:postsrsd /etc/postsrsd/postsrsd.secret
        chmod 600 /etc/postsrsd/postsrsd.secret
    fi
    
    log_success "Permissions and directories fixed"
}

# Regenerate configuration
regenerate_configuration() {
    log_info "Regenerating PostSRSD configuration..."
    
    # Generate new secret if needed
    if [ ! -f /etc/postsrsd/postsrsd.secret ]; then
        dd if=/dev/urandom bs=18 count=1 2>/dev/null | base64 > /etc/postsrsd/postsrsd.secret
        log_info "Generated new SRS secret"
    fi
    
    # Fix secret file permissions
    chown postsrsd:postsrsd /etc/postsrsd/postsrsd.secret
    chmod 600 /etc/postsrsd/postsrsd.secret
    
    # Create main configuration file
    cat > /etc/postsrsd/postsrsd.conf <<EOF
# PostSRSD Configuration
SRS_DOMAIN=$DOMAIN
SRS_EXCLUDE_DOMAINS=$DOMAIN
SRS_SEPARATOR="="
SRS_SECRET=/etc/postsrsd/postsrsd.secret
SRS_FORWARD_PORT=10001
SRS_REVERSE_PORT=10002
SRS_LISTEN_ADDR=127.0.0.1
CHROOT=/var/lib/postsrsd
RUN_AS=postsrsd
EOF
    
    # Create default configuration
    cat > /etc/default/postsrsd <<EOF
# PostSRSD default configuration
SRS_DOMAIN=$DOMAIN
SRS_EXCLUDE_DOMAINS="$DOMAIN"
SRS_SEPARATOR="="
SRS_SECRET=/etc/postsrsd/postsrsd.secret
SRS_FORWARD_PORT=10001
SRS_REVERSE_PORT=10002
SRS_LISTEN_ADDR=127.0.0.1
CHROOT=/var/lib/postsrsd
RUN_AS=postsrsd
# Additional arguments
POSTSRSD_ARGS="-n"
EOF
    
    # Set proper permissions
    chown root:root /etc/postsrsd/postsrsd.conf /etc/default/postsrsd
    chmod 644 /etc/postsrsd/postsrsd.conf /etc/default/postsrsd
    
    log_success "Configuration regenerated"
}

# Fix systemd service
fix_systemd_service() {
    log_info "Fixing PostSRSD systemd service..."
    
    # Create systemd override directory
    mkdir -p /etc/systemd/system/postsrsd.service.d
    
    # Create service override
    cat > /etc/systemd/system/postsrsd.service.d/override.conf <<EOF
[Unit]
Description=PostSRSD (Sender Rewriting Scheme daemon)
After=network.target

[Service]
Type=forking
User=postsrsd
Group=postsrsd
ExecStartPre=/bin/mkdir -p /var/run/postsrsd
ExecStartPre=/bin/chown postsrsd:postsrsd /var/run/postsrsd
ExecStart=/usr/sbin/postsrsd -f 10001 -r 10002 -d $DOMAIN -s /etc/postsrsd/postsrsd.secret -u postsrsd -c /var/lib/postsrsd -p /var/run/postsrsd/postsrsd.pid -n
PIDFile=/var/run/postsrsd/postsrsd.pid
Restart=on-failure
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    # Alternative: Create a complete service file if the original is problematic
    cat > /etc/systemd/system/postsrsd-fix.service <<EOF
[Unit]
Description=PostSRSD Fix (Sender Rewriting Scheme daemon)
After=network.target
Wants=network.target

[Service]
Type=simple
User=postsrsd
Group=postsrsd
ExecStartPre=/bin/mkdir -p /var/run/postsrsd
ExecStartPre=/bin/chown postsrsd:postsrsd /var/run/postsrsd
ExecStart=/usr/sbin/postsrsd -f 10001 -r 10002 -d $DOMAIN -s /etc/postsrsd/postsrsd.secret -u postsrsd -l 127.0.0.1 -n -D
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log_success "Systemd service configuration fixed"
}

# Start and verify service
start_and_verify_service() {
    log_info "Starting and verifying PostSRSD service..."
    
    # Try the original service first
    if systemctl start postsrsd; then
        sleep 5
        if systemctl is-active --quiet postsrsd; then
            log_success "PostSRSD service started successfully"
            verify_ports
            return 0
        else
            log_warning "PostSRSD service started but stopped, trying alternative..."
        fi
    else
        log_warning "PostSRSD service failed to start, trying alternative..."
    fi
    
    # If original fails, try the fix service
    systemctl stop postsrsd || true
    sleep 2
    
    if systemctl start postsrsd-fix; then
        sleep 5
        if systemctl is-active --quiet postsrsd-fix; then
            log_success "PostSRSD-fix service started successfully"
            systemctl enable postsrsd-fix
            verify_ports
            return 0
        else
            log_error "PostSRSD-fix service also failed"
        fi
    else
        log_error "Both PostSRSD services failed to start"
    fi
    
    # Manual start as last resort
    log_info "Attempting manual start..."
    start_postsrsd_manually
}

# Verify ports are listening
verify_ports() {
    log_info "Verifying PostSRSD ports..."
    
    local attempts=0
    local max_attempts=10
    
    while [ $attempts -lt $max_attempts ]; do
        if ss -tuln | grep -q ":10001 " && ss -tuln | grep -q ":10002 "; then
            log_success "PostSRSD ports (10001, 10002) are active"
            return 0
        fi
        
        attempts=$((attempts + 1))
        log_info "Attempt $attempts/$max_attempts: Waiting for ports..."
        sleep 2
    done
    
    log_warning "PostSRSD ports not active after $max_attempts attempts"
    return 1
}

# Manual start function
start_postsrsd_manually() {
    log_info "Starting PostSRSD manually..."
    
    # Kill any existing processes
    pkill -f postsrsd || true
    sleep 2
    
    # Start manually in background
    sudo -u postsrsd /usr/sbin/postsrsd \
        -f 10001 \
        -r 10002 \
        -d "$DOMAIN" \
        -s /etc/postsrsd/postsrsd.secret \
        -u postsrsd \
        -l 127.0.0.1 \
        -n &
    
    sleep 5
    
    if ss -tuln | grep -q ":10001 " && ss -tuln | grep -q ":10002 "; then
        log_success "PostSRSD started manually and ports are active"
        
        # Create a simple service to manage it
        create_simple_service
    else
        log_error "Manual start also failed"
        return 1
    fi
}

# Create simple service for manual management
create_simple_service() {
    cat > /etc/systemd/system/postsrsd-manual.service <<EOF
[Unit]
Description=PostSRSD Manual Service
After=network.target

[Service]
Type=simple
User=postsrsd
Group=postsrsd
ExecStart=/usr/sbin/postsrsd -f 10001 -r 10002 -d $DOMAIN -s /etc/postsrsd/postsrsd.secret -u postsrsd -l 127.0.0.1 -n -D
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable postsrsd-manual
    log_info "Created manual PostSRSD service"
}

# Function to check PostSRSD status
check_postsrsd_status() {
    echo "PostSRSD Status Check"
    echo "===================="
    
    # Check if any PostSRSD service is running
    local running_service=""
    for service in postsrsd postsrsd-fix postsrsd-manual; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            running_service="$service"
            break
        fi
    done
    
    if [ -n "$running_service" ]; then
        echo "✅ Service: $running_service is running"
    else
        echo "❌ Service: No PostSRSD service is running"
    fi
    
    # Check ports
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
    
    # Check configuration
    if [ -f /etc/postsrsd/postsrsd.secret ] && [ -r /etc/postsrsd/postsrsd.secret ]; then
        echo "✅ Secret file: Present and readable"
    else
        echo "❌ Secret file: Missing or not readable"
    fi
    
    # Check processes
    local process_count=$(pgrep -c postsrsd 2>/dev/null || echo "0")
    echo "📊 Running processes: $process_count"
    
    if [ "$process_count" -gt 0 ]; then
        echo "📋 Process details:"
        ps aux | grep postsrsd | grep -v grep | sed 's/^/  /'
    fi
}

# Function to completely remove and reinstall PostSRSD
reinstall_postsrsd() {
    log_info "Completely reinstalling PostSRSD..."
    
    # Stop all services
    systemctl stop postsrsd postsrsd-fix postsrsd-manual 2>/dev/null || true
    pkill -f postsrsd || true
    
    # Remove package and reinstall
    apt remove --purge -y postsrsd
    apt autoremove -y
    apt update
    apt install -y postsrsd
    
    # Run our fix
    fix_postsrsd
    
    log_success "PostSRSD reinstallation completed"
}

# Run PostSRSD fix if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-fix}" in
        "fix")
            fix_postsrsd
            ;;
        "status")
            check_postsrsd_status
            ;;
        "reinstall")
            reinstall_postsrsd
            ;;
        "manual-start")
            start_postsrsd_manually
            ;;
        *)
            echo "Usage: $0 {fix|status|reinstall|manual-start}"
            echo ""
            echo "Commands:"
            echo "  fix          - Fix PostSRSD configuration and service"
            echo "  status       - Check PostSRSD status"
            echo "  reinstall    - Completely reinstall PostSRSD"
            echo "  manual-start - Start PostSRSD manually"
            exit 1
            ;;
    esac
fi
