# Add these tools to the existing management_tools.sh or create separate scripts

# Create comprehensive mail fix tool
create_mail_fix_tool() {
    cat > "$BIN_DIR/mail-fix" << 'EOFFIX'
#!/bin/bash

# Comprehensive Mail Fix Tool
source /opt/mailserver/config/mail_config.sh
source /opt/mailserver/lib/common.sh

show_usage() {
    echo "Comprehensive Mail Fix Tool"
    echo "=========================="
    echo ""
    echo "Usage: $0 {comprehensive|quick|logging|postsrsd|ssl|status}"
    echo ""
    echo "Commands:"
    echo "  comprehensive  - Run complete mail server fix"
    echo "  quick         - Apply quick fixes only"
    echo "  logging       - Fix mail logging issues"
    echo "  postsrsd      - Fix PostSRSD service"
    echo "  ssl           - Set up SSL certificates"
    echo "  status        - Show current status"
    echo ""
    exit 1
}

fix_logging() {
    echo "🔧 Fixing Mail Logging"
    echo "======================"
    
    # Configure rsyslog
    cat > /etc/rsyslog.d/50-mail.conf <<'EOF'
mail.*                          /var/log/mail.log
mail.err                        /var/log/mail.err
mail.warn                       /var/log/mail.warn
:programname, isequal, "postfix" /var/log/mail.log
:programname, isequal, "dovecot" /var/log/mail.log
:programname, isequal, "opendkim" /var/log/mail.log
EOF
    
    # Create log files
    touch /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    chown syslog:adm /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    chmod 644 /var/log/mail.log /var/log/mail.err /var/log/mail.warn
    
    # Restart rsyslog
    systemctl restart rsyslog
    
    echo "✅ Mail logging configured"
    echo "Monitor with: tail -f /var/log/mail.log"
}

fix_postsrsd() {
    echo "🔧 Fixing PostSRSD Service"
    echo "=========================="
    
    # Stop service
    systemctl stop postsrsd || true
    pkill -f postsrsd || true
    
    # Ensure user exists
    if ! getent passwd postsrsd >/dev/null; then
        useradd --system --home-dir /var/lib/postsrsd --shell /bin/false postsrsd
        echo "Created postsrsd user"
    fi
    
    # Fix directories
    mkdir -p /etc/postsrsd /var/lib/postsrsd /var/run/postsrsd
    chown -R postsrsd:postsrsd /var/lib/postsrsd /var/run/postsrsd
    chmod 755 /var/lib/postsrsd /var/run/postsrsd /etc/postsrsd
    
    # Generate secret
    if [ ! -f /etc/postsrsd/postsrsd.secret ]; then
        dd if=/dev/urandom bs=18 count=1 2>/dev/null | base64 > /etc/postsrsd/postsrsd.secret
    fi
    chown postsrsd:postsrsd /etc/postsrsd/postsrsd.secret
    chmod 600 /etc/postsrsd/postsrsd.secret
    
    # Create configuration
    cat > /etc/default/postsrsd <<EOF
SRS_DOMAIN=$DOMAIN
SRS_EXCLUDE_DOMAINS="$DOMAIN"
SRS_SEPARATOR="="
SRS_SECRET=/etc/postsrsd/postsrsd.secret
SRS_FORWARD_PORT=10001
SRS_REVERSE_PORT=10002
SRS_LISTEN_ADDR=127.0.0.1
CHROOT=/var/lib/postsrsd
RUN_AS=postsrsd
EOF
    
    # Try to start
    systemctl daemon-reload
    if systemctl start postsrsd; then
        sleep 5
        if systemctl is-active --quiet postsrsd; then
            echo "✅ PostSRSD service fixed"
        else
            echo "⚠️  PostSRSD started but stopped, creating manual service"
            create_manual_postsrsd
        fi
    else
        echo "⚠️  PostSRSD failed to start, creating manual service"
        create_manual_postsrsd
    fi
}

create_manual_postsrsd() {
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
    systemctl start postsrsd-manual
    
    if systemctl is-active --quiet postsrsd-manual; then
        echo "✅ Manual PostSRSD service started"
    else
        echo "❌ Manual PostSRSD service also failed"
    fi
}

setup_ssl() {
    echo "🔧 Setting Up SSL Certificates"
    echo "=============================="
    
    # Check DNS first
    echo "Checking DNS configuration..."
    local dns_ok=true
    
    for record in smtp.$DOMAIN imap.$DOMAIN mail.$DOMAIN; do
        local resolved_ip=$(dig +short "$record" 2>/dev/null | head -1)
        if [ "$resolved_ip" = "$SERVER_IP" ]; then
            echo "✅ $record resolves correctly"
        else
            echo "❌ $record does not resolve to $SERVER_IP"
            dns_ok=false
        fi
    done
    
    if [ "$dns_ok" = false ]; then
        echo ""
        echo "❌ DNS not properly configured. Required records:"
        echo "  smtp.$DOMAIN    IN A  $SERVER_IP"
        echo "  imap.$DOMAIN    IN A  $SERVER_IP"
        echo "  mail.$DOMAIN    IN A  $SERVER_IP"
        echo "  $DOMAIN         IN MX smtp.$DOMAIN"
        echo ""
        echo "Wait 15-30 minutes after DNS changes, then try again"
        return 1
    fi
    
    echo "DNS looks good, obtaining certificates..."
    
    # Stop nginx for standalone
    systemctl stop nginx
    
    # Get certificate
    if certbot certonly --standalone \
        -d smtp.$DOMAIN \
        -d imap.$DOMAIN \
        -d mail.$DOMAIN \
        --email admin@$DOMAIN \
        --agree-tos \
        --non-interactive; then
        
        echo "✅ SSL certificates obtained"
        
        # Update configurations
        local cert_path="/etc/letsencrypt/live/smtp.$DOMAIN"
        
        # Update Postfix
        postconf -e "smtpd_tls_cert_file = $cert_path/fullchain.pem"
        postconf -e "smtpd_tls_key_file = $cert_path/privkey.pem"
        
        # Update Dovecot
        sed -i "s|ssl_cert = <.*|ssl_cert = <$cert_path/fullchain.pem|" /etc/dovecot/dovecot.conf
        sed -i "s|ssl_key = <.*|ssl_key = <$cert_path/privkey.pem|" /etc/dovecot/dovecot.conf
        
        # Restart services
        systemctl start nginx
        systemctl reload postfix
        systemctl reload dovecot
        
        echo "✅ SSL configuration updated"
    else
        echo "❌ Failed to obtain SSL certificates"
        systemctl start nginx
        return 1
    fi
}

comprehensive_fix() {
    echo "🔧 COMPREHENSIVE MAIL SERVER FIX"
    echo "================================"
    echo "Starting comprehensive fix at $(date)"
    echo ""
    
    # Phase 1: Fix logging
    echo "Phase 1: Fixing logging..."
    fix_logging
    echo ""
    
    # Phase 2: Fix PostSRSD
    echo "Phase 2: Fixing PostSRSD..."
    fix_postsrsd
    echo ""
    
    # Phase 3: Fix ownership and restart services
    echo "Phase 3: Fixing services..."
    chown -R postfix:postfix /var/spool/postfix
    chmod 755 /var/spool/postfix
    
    # Restart services in order
    systemctl restart opendkim
    sleep 3
    systemctl restart postfix
    sleep 3
    systemctl reload postfix
    sleep 3
    systemctl restart dovecot
    sleep 3
    
    echo "✅ Services restarted"
    echo ""
    
    # Phase 4: Test basic functionality
    echo "Phase 4: Testing basic functionality..."
    if echo "Comprehensive fix test $(date)" | mail -s "Fix Test" admin@$DOMAIN; then
        echo "✅ Test email sent successfully"
    else
        echo "⚠️  Test email failed"
    fi
    echo ""
    
    # Phase 5: SSL if DNS ready
    echo "Phase 5: SSL setup (if DNS ready)..."
    setup_ssl || echo "⚠️  SSL setup skipped (DNS not ready)"
    echo ""
    
    # Final status
    echo "🏁 COMPREHENSIVE FIX COMPLETED"
    echo "=============================="
    show_status
}

quick_fix() {
    echo "⚡ QUICK MAIL SERVER FIX"
    echo "======================="
    
    # Fix immediate issues
    fix_logging
    
    # Fix Postfix ownership
    chown -R postfix:postfix /var/spool/postfix
    
    # Restart essential services
    systemctl restart opendkim postfix dovecot
    sleep 5
    systemctl reload postfix
    
    echo ""
    echo "✅ Quick fix completed"
    show_status
}

show_status() {
    echo ""
    echo "📊 Current Status:"
    echo "=================="
    
    # Services
    for service in opendkim postfix dovecot; do
        if systemctl is-active --quiet "$service"; then
            echo "✅ $service: Running"
        else
            echo "❌ $service: Not running"
        fi
    done
    
    # PostSRSD
    if systemctl is-active --quiet postsrsd || systemctl is-active --quiet postsrsd-manual; then
        echo "✅ PostSRSD: Running"
    else
        echo "⚠️  PostSRSD: Not running"
    fi
    
    # Ports
    for port in 25 587 465 993; do
        if ss -tuln | grep -q ":$port "; then
            echo "✅ Port $port: Active"
        else
            echo "❌ Port $port: Inactive"
        fi
    done
    
    # Logging
    if [ -f /var/log/mail.log ]; then
        echo "✅ Mail logging: Active"
    else
        echo "❌ Mail logging: Not configured"
    fi
    
    # SSL
    if [ -f "/etc/letsencrypt/live/smtp.$DOMAIN/fullchain.pem" ]; then
        echo "✅ SSL: Let's Encrypt certificates"
    else
        echo "⚠️  SSL: Self-signed certificates"
    fi
    
    echo ""
    echo "💡 Next steps:"
    echo "   • Monitor: tail -f /var/log/mail.log"
    echo "   • Test: mail-test"
    echo "   • Manage: mail-user, mail-forward"
}

case "${1:-comprehensive}" in
    "comprehensive")
        comprehensive_fix
        ;;
    "quick")
        quick_fix
        ;;
    "logging")
        fix_logging
        ;;
    "postsrsd")
        fix_postsrsd
        ;;
    "ssl")
        setup_ssl
        ;;
    "status")
        show_status
        ;;
    *)
        show_usage
        ;;
esac
EOFFIX

    chmod +x "$BIN_DIR/mail-fix"
}

# Create mail log monitoring tool
create_mail_logs_tool() {
    cat > "$BIN_DIR/mail-logs" << 'EOFLOGS'
#!/bin/bash

# Mail Log Monitoring Tool
source /opt/mailserver/config/mail_config.sh

show_usage() {
    echo "Mail Log Monitoring Tool"
    echo "======================="
    echo ""
    echo "Usage: $0 {tail|analyze|errors|search|test}"
    echo ""
    echo "Commands:"
    echo "  tail         - Monitor logs in real-time"
    echo "  analyze      - Analyze recent activity"
    echo "  errors       - Show recent errors"
    echo "  search <term> - Search for specific term"
    echo "  test         - Test logging configuration"
    echo ""
    exit 1
}

tail_logs() {
    echo "📡 Real-time Mail Log Monitoring"
    echo "Press Ctrl+C to stop"
    echo "================================"
    
    if [ -f /var/log/mail.log ]; then
        tail -f /var/log/mail.log | while read line; do
            if echo "$line" | grep -q "status=delivered"; then
                echo "✅ $line"
            elif echo "$line" | grep -q "status=bounced"; then
                echo "❌ $line"
            elif echo "$line" | grep -q "status=deferred"; then
                echo "⏸️  $line"
            elif echo "$line" | grep -q "reject"; then
                echo "🚫 $line"
            else
                echo "   $line"
            fi
        done
    else
        echo "❌ Mail log not found. Run: mail-fix logging"
    fi
}

analyze_logs() {
    echo "📊 Mail Log Analysis"
    echo "==================="
    
    if [ ! -f /var/log/mail.log ]; then
        echo "❌ Mail log not found"
        return 1
    fi
    
    echo "Recent activity (last hour):"
    echo "----------------------------"
    
    local total=$(grep "$(date '+%b %d')" /var/log/mail.log | wc -l)
    local delivered=$(grep "status=delivered" /var/log/mail.log | grep "$(date '+%b %d')" | wc -l)
    local bounced=$(grep "status=bounced" /var/log/mail.log | grep "$(date '+%b %d')" | wc -l)
    local deferred=$(grep "status=deferred" /var/log/mail.log | grep "$(date '+%b %d')" | wc -l)
    
    echo "Total events: $total"
    echo "Delivered: $delivered"
    echo "Bounced: $bounced"
    echo "Deferred: $deferred"
    
    echo ""
    echo "Recent entries:"
    echo "--------------"
    tail -20 /var/log/mail.log
}

show_errors() {
    echo "⚠️  Recent Mail Errors"
    echo "====================="
    
    if [ -f /var/log/mail.err ]; then
        echo "Error log entries:"
        tail -20 /var/log/mail.err
    fi
    
    if [ -f /var/log/mail.log ]; then
        echo ""
        echo "Recent warnings and errors from main log:"
        grep -E "(error|warning|fail|reject)" /var/log/mail.log | tail -10
    fi
}

search_logs() {
    local search_term="$1"
    
    if [ -z "$search_term" ]; then
        echo "Usage: $0 search <search_term>"
        return 1
    fi
    
    echo "🔍 Searching for: $search_term"
    echo "=============================="
    
    if [ -f /var/log/mail.log ]; then
        grep -i "$search_term" /var/log/mail.log | tail -20
    else
        echo "❌ Mail log not found"
    fi
}

test_logging() {
    echo "🧪 Testing Mail Logging"
    echo "======================="
    
    # Send test log message
    logger -p mail.info "Mail logging test - $(date)"
    
    sleep 2
    
    if [ -f /var/log/mail.log ] && grep -q "Mail logging test" /var/log/mail.log; then
        echo "✅ Mail logging is working"
        echo "Recent test entry:"
        grep "Mail logging test" /var/log/mail.log | tail -1
    else
        echo "❌ Mail logging is not working"
        echo "Run: mail-fix logging"
    fi
}

case "${1:-tail}" in
    "tail")
        tail_logs
        ;;
    "analyze")
        analyze_logs
        ;;
    "errors")
        show_errors
        ;;
    "search")
        search_logs "$2"
        ;;
    "test")
        test_logging
        ;;
    *)
        show_usage
        ;;
esac
EOFLOGS

    chmod +x "$BIN_DIR/mail-logs"
}

# Create comprehensive mail test tool
create_comprehensive_test_tool() {
    cat > "$BIN_DIR/mail-test-comprehensive" << 'EOFTEST'
#!/bin/bash

# Comprehensive Mail Test Tool
source /opt/mailserver/config/mail_config.sh

echo "🧪 COMPREHENSIVE MAIL SERVER TEST"
echo "================================="
echo "Domain: $DOMAIN"
echo "Server: $HOSTNAME"
echo "IP: $SERVER_IP"
echo "Started: $(date)"
echo ""

# Test 1: Service Status
echo "1. Service Status"
echo "----------------"
for service in opendkim postfix dovecot postsrsd nginx; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: Running"
    else
        echo "❌ $service: Not running"
    fi
done
echo ""

# Test 2: Port Status
echo "2. Port Status"
echo "-------------"
local ports=(25 587 465 143 993 110 995 80 443 12301 10001 10002)
for port in "${ports[@]}"; do
    if ss -tuln | grep -q ":$port "; then
        echo "✅ Port $port: Listening"
    else
        echo "❌ Port $port: Not listening"
    fi
done
echo ""

# Test 3: DNS Configuration
echo "3. DNS Configuration"
echo "-------------------"
# Check MX record
local mx_record=$(dig +short MX "$DOMAIN" 2>/dev/null)
if echo "$mx_record" | grep -q "smtp.$DOMAIN"; then
    echo "✅ MX record: Configured"
else
    echo "❌ MX record: Not configured"
fi

# Check A records
for record in smtp.$DOMAIN imap.$DOMAIN mail.$DOMAIN; do
    local resolved_ip=$(dig +short "$record" 2>/dev/null | head -1)
    if [ "$resolved_ip" = "$SERVER_IP" ]; then
        echo "✅ $record: Resolves correctly"
    else
        echo "❌ $record: Does not resolve to $SERVER_IP"
    fi
done

# Check SPF record
local spf_record=$(dig +short TXT "$DOMAIN" | grep "v=spf1" | head -1)
if [ -n "$spf_record" ]; then
    echo "✅ SPF record: Present"
else
    echo "⚠️  SPF record: Missing"
fi

# Check DMARC record
local dmarc_record=$(dig +short TXT "_dmarc.$DOMAIN" | grep "v=DMARC1" | head -1)
if [ -n "$dmarc_record" ]; then
    echo "✅ DMARC record: Present"
else
    echo "⚠️  DMARC record: Missing"
fi
echo ""

# Test 4: DKIM Configuration
echo "4. DKIM Configuration"
echo "--------------------"
if systemctl is-active --quiet opendkim; then
    echo "✅ OpenDKIM service: Running"
else
    echo "❌ OpenDKIM service: Not running"
fi

if ss -tuln | grep -q ":12301 "; then
    echo "✅ DKIM port 12301: Active"
else
    echo "❌ DKIM port 12301: Inactive"
fi

if [ -f "/etc/opendkim/keys/$DOMAIN/default.private" ]; then
    echo "✅ DKIM private key: Present"
else
    echo "❌ DKIM private key: Missing"
fi

if [ -f "/etc/opendkim/keys/$DOMAIN/default.txt" ]; then
    echo "✅ DKIM public key: Present"
else
    echo "❌ DKIM public key: Missing"
fi
echo ""

# Test 5: SSL Configuration
echo "5. SSL Configuration"
echo "-------------------"
if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
    echo "✅ Let's Encrypt certificates: Present"
    local expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" | cut -d= -f2)
    echo "📅 Certificate expires: $expiry"
else
    echo "⚠️  Using self-signed certificates"
fi

# Test SSL connections
echo ""
echo "SSL Connection Tests:"
local ssl_services=("SMTP:$HOSTNAME:587" "IMAPS:$HOSTNAME:993")
for service_info in "${ssl_services[@]}"; do
    local service=$(echo "$service_info" | cut -d: -f1)
    local host=$(echo "$service_info" | cut -d: -f2)
    local port=$(echo "$service_info" | cut -d: -f3)
    
    if timeout 5 openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        echo "✅ $service SSL: Valid"
    else
        echo "⚠️  $service SSL: Issues detected"
    fi
done
echo ""

# Test 6: Email Delivery
echo "6. Email Delivery Test"
echo "---------------------"
echo "Sending test emails..."

# Internal test
if echo "Internal test $(date)" | mail -s "Internal Test" "admin@$DOMAIN"; then
    echo "✅ Internal delivery: Sent"
else
    echo "❌ Internal delivery: Failed"
fi

# Forwarding test
if echo "Forwarding test $(date)" | mail -s "Forward Test" "info@$DOMAIN"; then
    echo "✅ Forwarding test: Sent"
else
    echo "❌ Forwarding test: Failed"
fi

# External test (if configured)
if [ -n "$MEMBER_EMAILS" ]; then
    local first_member=$(echo "$MEMBER_EMAILS" | cut -d',' -f1)
    if echo "External test from $DOMAIN $(date)" | mail -s "External Test" "$first_member"; then
        echo "✅ External delivery: Sent to $first_member"
    else
        echo "❌ External delivery: Failed"
    fi
fi
echo ""

# Test 7: Authentication
echo "7. Authentication Test"
echo "---------------------"
if [ -f /etc/dovecot/users ] && [ -s /etc/dovecot/users ]; then
    local user_count=$(wc -l < /etc/dovecot/users)
    echo "✅ User database: $user_count users configured"
else
    echo "❌ User database: Missing or empty"
fi

# Test IMAP connection
if timeout 5 telnet "$HOSTNAME" 993 2>/dev/null | grep -q "OK"; then
    echo "✅ IMAP connection: Available"
else
    echo "❌ IMAP connection: Failed"
fi

# Test SMTP submission
if timeout 5 telnet "$HOSTNAME" 587 2>/dev/null | grep -q "220"; then
    echo "✅ SMTP submission: Available"
else
    echo "❌ SMTP submission: Failed"
fi
echo ""

# Test 8: Mail Queue
echo "8. Mail Queue Status"
echo "-------------------"
local queue_count=$(postqueue -p | grep -c "^[A-F0-9]" 2>/dev/null || echo "0")
if [ "$queue_count" -eq 0 ]; then
    echo "✅ Mail queue: Empty"
else
    echo "📬 Mail queue: $queue_count messages"
    if [ "$queue_count" -gt 10 ]; then
        echo "⚠️  Large queue detected - possible delivery issues"
    fi
fi
echo ""

# Test 9: Logging
echo "9. Logging Configuration"
echo "-----------------------"
if [ -f /var/log/mail.log ]; then
    echo "✅ Mail logging: Configured"
    local recent_entries=$(tail -10 /var/log/mail.log | wc -l)
    echo "📊 Recent log entries: $recent_entries"
else
    echo "❌ Mail logging: Not configured"
fi
echo ""

# Overall Summary
echo "🏁 TEST SUMMARY"
echo "==============="

# Count results
local total_tests=0
local passed_tests=0

# Count service tests
for service in opendkim postfix dovecot; do
    total_tests=$((total_tests + 1))
    if systemctl is-active --quiet "$service"; then
        passed_tests=$((passed_tests + 1))
    fi
done

# Count port tests (critical ports only)
for port in 25 587 465 993; do
    total_tests=$((total_tests + 1))
    if ss -tuln | grep -q ":$port "; then
        passed_tests=$((passed_tests + 1))
    fi
done

# Count other critical tests
total_tests=$((total_tests + 4))  # DKIM, SSL, Auth, Logging

if systemctl is-active --quiet opendkim && ss -tuln | grep -q ":12301 "; then
    passed_tests=$((passed_tests + 1))
fi

if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ] || [ -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
    passed_tests=$((passed_tests + 1))
fi

if [ -f /etc/dovecot/users ] && [ -s /etc/dovecot/users ]; then
    passed_tests=$((passed_tests + 1))
fi

if [ -f /var/log/mail.log ]; then
    passed_tests=$((passed_tests + 1))
fi

local success_rate=0
if [ $total_tests -gt 0 ]; then
    success_rate=$(( (passed_tests * 100) / total_tests ))
fi

echo "Tests passed: $passed_tests/$total_tests ($success_rate%)"

if [ $success_rate -ge 90 ]; then
    echo "🎉 EXCELLENT: Mail server is fully operational!"
elif [ $success_rate -ge 75 ]; then
    echo "✅ GOOD: Mail server is mostly working"
elif [ $success_rate -ge 50 ]; then
    echo "⚠️  WARNING: Mail server has significant issues"
else
    echo "❌ CRITICAL: Mail server needs immediate attention"
fi

echo ""
echo "📝 Recommendations:"
if [ $success_rate -lt 100 ]; then
    echo "   • Run: mail-fix comprehensive"
    echo "   • Check: mail-logs errors"
    echo "   • Monitor: mail-logs tail"
fi

if [ ! -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
    echo "   • Configure DNS records and run: mail-fix ssl"
fi

if [ ! -f /var/log/mail.log ]; then
    echo "   • Fix logging: mail-fix logging"
fi

echo ""
echo "✅ Comprehensive test completed at $(date)"
EOFTEST

    chmod +x "$BIN_DIR/mail-test-comprehensive"
}

# Create DNS setup guide tool
create_dns_guide_tool() {
    cat > "$BIN_DIR/mail-dns-guide" << 'EOFDNS'
#!/bin/bash

# DNS Setup Guide Tool
source /opt/mailserver/config/mail_config.sh

echo "🌐 DNS CONFIGURATION GUIDE"
echo "=========================="
echo "Domain: $DOMAIN"
echo "Server IP: $SERVER_IP"
echo ""

echo "REQUIRED DNS RECORDS:"
echo "===================="
echo ""

echo "1. A RECORDS (Essential for mail services):"
echo "   smtp.$DOMAIN.         IN A  $SERVER_IP"
echo "   imap.$DOMAIN.         IN A  $SERVER_IP"
echo "   mail.$DOMAIN.         IN A  $SERVER_IP"
echo ""

echo "2. MX RECORD (Required for receiving email):"
echo "   $DOMAIN.              IN MX 10 smtp.$DOMAIN."
echo ""

echo "3. A RECORDS (For SSL certificates and autodiscovery):"
echo "   autodiscover.$DOMAIN. IN A  $SERVER_IP"
echo "   autoconfig.$DOMAIN.   IN A  $SERVER_IP"
echo ""

echo "4. SPF RECORD (Recommended for delivery):"
echo "   $DOMAIN.              IN TXT \"v=spf1 ip4:$SERVER_IP -all\""
echo ""

echo "5. DMARC RECORD (Recommended for security):"
echo "   _dmarc.$DOMAIN.       IN TXT \"v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN\""
echo ""

echo "6. DKIM RECORD (Add after mail server setup):"
if [ -f "/etc/opendkim/keys/$DOMAIN/default.txt" ]; then
    echo "   Copy this record to your DNS:"
    echo ""
    cat "/etc/opendkim/keys/$DOMAIN/default.txt"
else
    echo "   Run 'dkim-test' after mail server setup to get your DKIM record"
fi

echo ""
echo "DNS PROVIDER EXAMPLES:"
echo "====================="
echo ""

echo "Cloudflare:"
echo "----------"
echo "Type  | Name              | Content"
echo "------|-------------------|------------------"
echo "A     | smtp              | $SERVER_IP"
echo "A     | imap              | $SERVER_IP"
echo "A     | mail              | $SERVER_IP"
echo "A     | autodiscover      | $SERVER_IP"
echo "A     | autoconfig        | $SERVER_IP"
echo "MX    | @                 | smtp.$DOMAIN"
echo "TXT   | @                 | v=spf1 ip4:$SERVER_IP -all"
echo "TXT   | _dmarc            | v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN"
echo ""

echo "NameCheap/GoDaddy:"
echo "------------------"
echo "Type  | Host              | Value"
echo "------|-------------------|------------------"
echo "A     | smtp              | $SERVER_IP"
echo "A     | imap              | $SERVER_IP"
echo "A     | mail              | $SERVER_IP"
echo "A     | autodiscover      | $SERVER_IP"
echo "A     | autoconfig        | $SERVER_IP"
echo "MX    | @                 | smtp.$DOMAIN"
echo "TXT   | @                 | v=spf1 ip4:$SERVER_IP -all"
echo "TXT   | _dmarc            | v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN"
echo ""

echo "VERIFICATION:"
echo "============"
echo "After adding DNS records, verify with these commands:"
echo ""
echo "Check A records:"
echo "  dig smtp.$DOMAIN"
echo "  dig imap.$DOMAIN"
echo "  dig mail.$DOMAIN"
echo ""
echo "Check MX record:"
echo "  dig MX $DOMAIN"
echo ""
echo "Check TXT records:"
echo "  dig TXT $DOMAIN"
echo "  dig TXT _dmarc.$DOMAIN"
echo ""

echo "PROPAGATION:"
echo "==========="
echo "• DNS changes typically propagate within 15-30 minutes"
echo "• Some providers may take up to 24 hours"
echo "• Use online DNS checkers to verify propagation"
echo "• Run 'mail-fix ssl' after DNS propagation to get SSL certificates"
echo ""

echo "TROUBLESHOOTING:"
echo "==============="
echo "If DNS doesn't propagate:"
echo "• Double-check record syntax"
echo "• Ensure no typos in domain names"
echo "• Contact your DNS provider support"
echo "• Use 'nslookup' or 'dig' to test"
echo ""

echo "NEXT STEPS:"
echo "=========="
echo "1. Add all DNS records to your provider"
echo "2. Wait 15-30 minutes for propagation"
echo "3. Run: mail-fix ssl"
echo "4. Run: mail-test-comprehensive"
echo "5. Add DKIM record from 'dkim-test' output"
EOFDNS

    chmod +x "$BIN_DIR/mail-dns-guide"
}

# Main function to create all updated tools
create_all_updated_tools() {
    log_info "Creating updated management tools..."
    
    create_mail_fix_tool
    create_mail_logs_tool
    create_comprehensive_test_tool
    create_dns_guide_tool
    
    log_success "Updated management tools created"
    
    echo ""
    echo "🛠️  NEW MANAGEMENT TOOLS AVAILABLE:"
    echo "   mail-fix              - Comprehensive mail server fix"
    echo "   mail-logs             - Mail log monitoring and analysis"
    echo "   mail-test-comprehensive - Complete system testing"
    echo "   mail-dns-guide        - DNS configuration guide"
    echo ""
    echo "🔧 USAGE EXAMPLES:"
    echo "   sudo mail-fix comprehensive    # Fix all issues"
    echo "   sudo mail-fix quick           # Quick fixes only"
    echo "   mail-logs tail                # Monitor logs live"
    echo "   mail-test-comprehensive       # Run all tests"
    echo "   mail-dns-guide                # Show DNS setup guide"
}

# Run the tool creation if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_all_updated_tools
fi
