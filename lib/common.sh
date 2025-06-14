#!/bin/bash

# ==========================================
# COMMON FUNCTIONS LIBRARY
# Shared functions used across all modules
# ==========================================

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

log_step() {
    echo ""
    echo "=========================================="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $1"
    echo "=========================================="
}

# Generate secure random password
generate_password() {
    local length=${1:-25}
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-$length
}

# Auto-detect server IP
detect_server_ip() {
    if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "62.171.187.28" ]; then
        log_info "Auto-detecting server IP address..."
        local ip_services=("ipv4.icanhazip.com" "ifconfig.me" "ipinfo.io/ip" "checkip.amazonaws.com")
        
        for service in "${ip_services[@]}"; do
            DETECTED_IP=$(timeout 10 curl -s "$service" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
            if [ -n "$DETECTED_IP" ]; then
                SERVER_IP="$DETECTED_IP"
                log_info "Detected server IP: $SERVER_IP"
                return 0
            fi
        done
        
        log_warning "Could not auto-detect server IP. Using default: ${SERVER_IP:-62.171.187.28}"
        SERVER_IP="${SERVER_IP:-62.171.187.28}"
    fi
}

# Check if service is running
is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service"
}

# Start service with verification
start_service() {
    local service="$1"
    local timeout="${2:-30}"
    
    log_info "Starting $service..."
    systemctl enable "$service" >/dev/null 2>&1
    
    if timeout "$timeout" systemctl start "$service"; then
        sleep 2
        if is_service_running "$service"; then
            log_success "$service started successfully"
            return 0
        else
            log_error "$service started but then stopped"
            journalctl -u "$service" --no-pager -l -n 5
            return 1
        fi
    else
        log_error "$service failed to start within timeout"
        journalctl -u "$service" --no-pager -l -n 5
        return 1
    fi
}

# Stop service safely
stop_service() {
    local service="$1"
    
    if is_service_running "$service"; then
        log_info "Stopping $service..."
        systemctl stop "$service" || true
        
        # Kill hanging processes if needed
        case "$service" in
            "postfix") pkill -f postfix || true ;;
            "dovecot") pkill -f dovecot || true ;;
            "opendkim") pkill -f opendkim || true ;;
            "postsrsd") pkill -f postsrsd || true ;;
        esac
        
        sleep 2
        log_success "$service stopped"
    fi
}

# Check if port is open
is_port_open() {
    local port="$1"
    ss -tuln | grep -q ":$port "
}

# Test port connectivity
test_port_connectivity() {
    local port="$1"
    local timeout="${2:-3}"
    timeout "$timeout" bash -c "</dev/tcp/localhost/$port" 2>/dev/null
}

# Check all required ports
check_all_ports() {
    local failed_ports=()
    local success_ports=()
    
    for port in "${!REQUIRED_PORTS[@]}"; do
        local desc="${REQUIRED_PORTS[$port]}"
        if is_port_open "$port"; then
            success_ports+=("$port:$desc")
        else
            failed_ports+=("$port:$desc")
        fi
    done
    
    # Display results
    for port_desc in "${success_ports[@]}"; do
        local port=$(echo "$port_desc" | cut -d':' -f1)
        local desc=$(echo "$port_desc" | cut -d':' -f2)
        printf "%-6s %-15s: ✅ ACTIVE\n" "$port" "$desc"
    done
    
    for port_desc in "${failed_ports[@]}"; do
        local port=$(echo "$port_desc" | cut -d':' -f1)
        local desc=$(echo "$port_desc" | cut -d':' -f2)
        printf "%-6s %-15s: ❌ INACTIVE\n" "$port" "$desc"
    done
    
    return ${#failed_ports[@]}
}

# DNS checking function
check_dns() {
    local domain="$1"
    local expected_ip="$2"
    local record_type="${3:-A}"
    
    log_info "Checking $record_type record for $domain..."
    
    local resolved_ip=""
    local dns_tools=("dig" "nslookup" "host")
    
    for tool in "${dns_tools[@]}"; do
        case $tool in
            "dig")
                resolved_ip=$(timeout 10 dig +short +time=5 +tries=2 "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
                ;;
            "nslookup")
                resolved_ip=$(timeout 10 nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
                ;;
            "host")
                resolved_ip=$(timeout 10 host "$domain" 2>/dev/null | awk '/has address/ { print $4 }' | head -n1)
                ;;
        esac
        
        if [ -n "$resolved_ip" ]; then
            break
        fi
    done
    
    if [ "$resolved_ip" = "$expected_ip" ]; then
        log_info "DNS for $domain correctly points to $expected_ip"
        return 0
    else
        log_warning "DNS for $domain not properly configured (got: '$resolved_ip', expected: '$expected_ip')"
        return 1
    fi
}

# Create backup of configuration file
backup_config() {
    local config_file="$1"
    local backup_suffix="${2:-$(date +%s)}"
    
    if [ -f "$config_file" ]; then
        local backup_file="${config_file}.backup.${backup_suffix}"
        cp "$config_file" "$backup_file"
        log_info "Backed up $config_file to $backup_file"
    fi
}

# Create directory structure
create_directory_structure() {
    log_info "Creating directory structure..."
    
    mkdir -p "$MAILSERVER_DIR"/{bin,config,logs,backups}
    mkdir -p "$CONFIG_DIR/templates"
    
    # Set permissions
    chmod 755 "$MAILSERVER_DIR"
    chmod 755 "$BIN_DIR"
    chmod 644 "$CONFIG_DIR"
    chmod 600 "$LOG_DIR"
    chmod 600 "$BACKUP_DIR"
    
    log_success "Directory structure created"
}

# Validate email format
validate_email() {
    local email="$1"
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Check if user exists in system
user_exists() {
    local user="$1"
    id "$user" &>/dev/null
}

# Create system user if doesn't exist
create_system_user() {
    local username="$1"
    local uid="$2"
    local home_dir="$3"
    local shell="${4:-/bin/false}"
    
    if ! user_exists "$username"; then
        if [ -n "$uid" ]; then
            useradd -u "$uid" -d "$home_dir" -s "$shell" "$username"
        else
            useradd --system -d "$home_dir" -s "$shell" "$username"
        fi
        log_info "Created system user: $username"
    else
        log_info "System user $username already exists"
        
        # Update user properties if needed
        if [ -n "$home_dir" ]; then
            usermod -d "$home_dir" "$username" 2>/dev/null || true
        fi
        if [ -n "$shell" ]; then
            usermod -s "$shell" "$username" 2>/dev/null || true
        fi
    fi
}

# Test configuration file syntax
test_config() {
    local service="$1"
    local config_file="$2"
    
    case "$service" in
        "postfix")
            postfix check
            ;;
        "dovecot")
            doveconf -n > /dev/null 2>&1
            ;;
        "opendkim")
            opendkim -n -f
            ;;
        "nginx")
            nginx -t 2>/dev/null
            ;;
        *)
            log_warning "No syntax test available for $service"
            return 0
            ;;
    esac
}

# Initialize common functions
init_common() {
    init_logging
    create_directory_structure
}

# Export functions for use in other scripts
export -f log_info log_error log_warning log_success log_step
export -f generate_password detect_server_ip
export -f is_service_running start_service stop_service
export -f is_port_open test_port_connectivity check_all_ports
export -f check_dns backup_config validate_email user_exists create_system_user test_config
