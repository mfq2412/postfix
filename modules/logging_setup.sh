#!/bin/bash

# ==========================================
# LOGGING SETUP MODULE
# Configure proper mail logging
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main logging setup function
setup_mail_logging() {
    log_step "CONFIGURING MAIL LOGGING"
    
    configure_rsyslog
    create_log_rotation
    restart_logging_services
    test_logging
    
    log_success "Mail logging configuration completed"
}

# Configure rsyslog for mail
configure_rsyslog() {
    log_info "Configuring rsyslog for mail logging..."
    
    # Create mail logging configuration
    cat > /etc/rsyslog.d/50-mail.conf <<'EOF'
# Mail logging configuration
mail.*                          /var/log/mail.log
mail.err                        /var/log/mail.err
mail.warn                       /var/log/mail.warn

# Postfix logging
:programname, isequal, "postfix" /var/log/mail.log
:programname, isequal, "postfix" ~

# Dovecot logging
:programname, isequal, "dovecot" /var/log/mail.log
:programname, isequal, "dovecot" ~

# OpenDKIM logging
:programname, isequal, "opendkim" /var/log/mail.log
:programname, isequal, "opendkim" ~

# PostSRSD logging
:programname, isequal, "postsrsd" /var/log/mail.log
:programname, isequal, "postsrsd" ~
EOF
    
    log_success "Rsyslog mail configuration created"
}

# Create log rotation configuration
create_log_rotation() {
    log_info "Setting up log rotation..."
    
    cat > /etc/logrotate.d/mail <<'EOF'
/var/log/mail.log
/var/log/mail.err
/var/log/mail.warn
{
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 syslog adm
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log_success "Log rotation configured"
}

# Restart logging services
restart_logging_services() {
    log_info "Restarting logging services..."
    
    # Create initial log files with correct permissions
    touch /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    chown syslog:adm /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    chmod 644 /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    
    # Restart rsyslog
    systemctl restart rsyslog
    
    log_success "Logging services restarted"
}

# Test logging functionality
test_logging() {
    log_info "Testing mail logging..."
    
    # Send test message to mail facility
    logger -p mail.info "Mail server logging test - $(date)"
    
    # Wait a moment for log to be written
    sleep 2
    
    # Check if log file exists and has content
    if [ -f /var/log/mail.log ] && [ -s /var/log/mail.log ]; then
        log_success "Mail logging is working"
        log_info "Recent mail log entries:"
        tail -5 /var/log/mail.log | sed 's/^/  /'
    else
        log_error "Mail logging is not working properly"
        return 1
    fi
}

# Function to enable verbose logging for debugging
enable_debug_logging() {
    log_info "Enabling debug logging for mail services..."
    
    # Enable Postfix debug logging
    postconf -e "debug_peer_level = 2"
    postconf -e "debug_peer_list = all"
    
    # Enable Dovecot debug logging
    sed -i 's/^#auth_debug = no/auth_debug = yes/' /etc/dovecot/dovecot.conf
    sed -i 's/^#auth_debug_passwords = no/auth_debug_passwords = yes/' /etc/dovecot/dovecot.conf
    sed -i 's/^#mail_debug = no/mail_debug = yes/' /etc/dovecot/dovecot.conf
    
    # Enable OpenDKIM debug logging
    sed -i 's/^LogWhy.*yes$/LogWhy yes/' /etc/opendkim.conf
    
    log_success "Debug logging enabled"
}

# Function to disable debug logging
disable_debug_logging() {
    log_info "Disabling debug logging..."
    
    # Disable Postfix debug logging
    postconf -e "debug_peer_level = 0"
    postconf -e "debug_peer_list ="
    
    # Disable Dovecot debug logging
    sed -i 's/^auth_debug = yes/#auth_debug = no/' /etc/dovecot/dovecot.conf
    sed -i 's/^auth_debug_passwords = yes/#auth_debug_passwords = no/' /etc/dovecot/dovecot.conf
    sed -i 's/^mail_debug = yes/#mail_debug = no/' /etc/dovecot/dovecot.conf
    
    log_success "Debug logging disabled"
}

# Function to monitor mail logs in real-time
monitor_mail_logs() {
    echo "Monitoring mail logs in real-time (Press Ctrl+C to stop)..."
    echo "============================================================"
    
    if [ -f /var/log/mail.log ]; then
        tail -f /var/log/mail.log
    else
        echo "Mail log file not found. Setting up logging first..."
        setup_mail_logging
        tail -f /var/log/mail.log
    fi
}

# Function to analyze recent mail activity
analyze_mail_logs() {
    local hours="${1:-1}"
    
    echo "Mail Activity Analysis (Last $hours hour(s))"
    echo "============================================="
    
    if [ ! -f /var/log/mail.log ]; then
        echo "Mail log file not found. Please run setup first."
        return 1
    fi
    
    local since_time=$(date -d "$hours hours ago" '+%Y-%m-%d %H:%M:%S')
    
    echo ""
    echo "📊 Summary:"
    echo "----------"
    echo "Total mail events: $(grep "$(date '+%b %d')" /var/log/mail.log | wc -l)"
    echo "Postfix events: $(grep "postfix" /var/log/mail.log | grep "$(date '+%b %d')" | wc -l)"
    echo "Dovecot events: $(grep "dovecot" /var/log/mail.log | grep "$(date '+%b %d')" | wc -l)"
    echo "OpenDKIM events: $(grep "opendkim" /var/log/mail.log | grep "$(date '+%b %d')" | wc -l)"
    
    echo ""
    echo "🔍 Recent Activity:"
    echo "------------------"
    tail -20 /var/log/mail.log
    
    echo ""
    echo "⚠️  Recent Errors:"
    echo "-----------------"
    if [ -f /var/log/mail.err ]; then
        tail -10 /var/log/mail.err
    else
        echo "No error log found"
    fi
}

# Run logging setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            setup_mail_logging
            ;;
        "enable-debug")
            enable_debug_logging
            ;;
        "disable-debug")
            disable_debug_logging
            ;;
        "monitor")
            monitor_mail_logs
            ;;
        "analyze")
            analyze_mail_logs "${2:-1}"
            ;;
        "test")
            test_logging
            ;;
        *)
            echo "Usage: $0 {setup|enable-debug|disable-debug|monitor|analyze|test}"
            echo ""
            echo "Commands:"
            echo "  setup         - Configure mail logging"
            echo "  enable-debug  - Enable debug logging"
            echo "  disable-debug - Disable debug logging"
            echo "  monitor       - Monitor logs in real-time"
            echo "  analyze [hrs] - Analyze recent activity"
            echo "  test          - Test logging functionality"
            exit 1
            ;;
    esac
fi
