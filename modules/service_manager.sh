#!/bin/bash

# ==========================================
# SERVICE MANAGER MODULE
# Centralized service management
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main service management functions
case "${1:-}" in
    "start_all")
        start_all_services
        ;;
    "stop_all")
        stop_all_services
        ;;
    "restart_all")
        restart_all_services
        ;;
    "status")
        show_service_status
        ;;
    "fix_ports")
        fix_all_ports
        ;;
    *)
        show_usage
        ;;
esac

# Start all services in proper order
start_all_services() {
    log_step "STARTING ALL MAIL SERVICES"
    
    # Reload systemd daemon
    systemctl daemon-reload
    
    # Start services in dependency order
    for service in "${SERVICES[@]}"; do
        start_service "$service"
        
        # Special handling for submission ports
        if [ "$service" = "postfix" ]; then
            sleep 5
            log_info "Reloading Postfix to activate submission ports..."
            systemctl reload postfix
            sleep 3
        fi
    done
    
    # Verify critical ports are active
    verify_critical_ports
    
    log_success "All services started successfully"
}

# Stop all services cleanly
stop_all_services() {
    log_step "STOPPING ALL MAIL SERVICES"
    
    # Stop services in reverse order
    local reverse_services=($(printf '%s\n' "${SERVICES[@]}" | tac))
    
    for service in "${reverse_services[@]}"; do
        stop_service "$service"
    done
    
    log_success "All services stopped cleanly"
}

# Restart all services
restart_all_services() {
    log_step "RESTARTING ALL MAIL SERVICES"
    
    stop_all_services
    sleep 3
    start_all_services
}

# Show service status
show_service_status() {
    echo "Service Status:"
    echo "==============="
    
    for service in "${SERVICES[@]}"; do
        if is_service_running "$service"; then
            printf "%-12s: ✅ Running\n" "$service"
        else
            printf "%-12s: ❌ Stopped\n" "$service"
        fi
    done
    
    echo ""
    echo "Port Status:"
    echo "============"
    check_all_ports >/dev/null
    local failed_count=$?
    
    if [ $failed_count -eq 0 ]; then
        echo "✅ All ports active"
    else
        echo "❌ $failed_count ports inactive"
    fi
}

# Fix all ports by restarting services
fix_all_ports() {
    log_step "FIXING ALL PORTS"
    
    log_info "Checking current port status..."
    check_all_ports
    local initial_failed=$?
    
    if [ $initial_failed -eq 0 ]; then
        log_success "All ports are already working!"
        return 0
    fi
    
    log_info "Found $initial_failed inactive ports. Fixing..."
    
    # Stop all services
    stop_all_services
    sleep 3
    
    # Start services with port verification
    start_all_services
    
    # Final verification
    log_info "Verifying port fix..."
    check_all_ports
    local final_failed=$?
    
    if [ $final_failed -eq 0 ]; then
        log_success "All ports fixed successfully!"
    else
        log_warning "$final_failed ports still inactive"
        return 1
    fi
}

# Verify critical ports are working
verify_critical_ports() {
    log_info "Verifying critical ports..."
    
    local attempts=0
    local max_attempts=10
    
    while [ $attempts -lt $max_attempts ]; do
        local all_working=true
        
        for port in "${CRITICAL_PORTS[@]}"; do
            if ! is_port_open "$port"; then
                all_working=false
                break
            fi
        done
        
        if [ "$all_working" = true ]; then
            log_success "All critical ports are active"
            return 0
        fi
        
        attempts=$((attempts + 1))
        log_info "Attempt $attempts/$max_attempts: Waiting for ports to activate..."
        sleep 2
    done
    
    log_warning "Some critical ports may not be active after $max_attempts attempts"
    return 1
}

# Show usage information
show_usage() {
    echo "Service Manager Module"
    echo "====================="
    echo ""
    echo "Usage: $0 {start_all|stop_all|restart_all|status|fix_ports}"
    echo ""
    echo "Commands:"
    echo "  start_all    - Start all mail services in proper order"
    echo "  stop_all     - Stop all mail services cleanly"
    echo "  restart_all  - Restart all mail services"
    echo "  status       - Show service and port status"
    echo "  fix_ports    - Fix inactive ports by restarting services"
    echo ""
    exit 1
}