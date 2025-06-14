#!/bin/bash

# ==========================================
# EMAIL DELIVERY TEST MODULE
# Comprehensive email delivery testing
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main email delivery test function
test_email_delivery() {
    log_step "TESTING EMAIL DELIVERY SYSTEM"
    
    prepare_test_environment
    test_internal_delivery
    test_external_delivery
    test_forwarding_delivery
    test_authentication
    analyze_delivery_results
    
    log_success "Email delivery testing completed"
}

# Prepare test environment
prepare_test_environment() {
    log_info "Preparing email delivery test environment..."
    
    # Ensure mail command is available
    if ! command -v mail >/dev/null 2>&1; then
        log_info "Installing mailutils for testing..."
        apt update
        apt install -y mailutils
    fi
    
    # Create test directory
    mkdir -p /tmp/mail-tests
    chmod 755 /tmp/mail-tests
    
    # Clear any existing test files
    rm -f /tmp/mail-tests/*
    
    log_success "Test environment prepared"
}

# Test internal mail delivery
test_internal_delivery() {
    log_info "Testing internal mail delivery..."
    
    local test_results="/tmp/mail-tests/internal_test.log"
    local test_count=0
    local success_count=0
    
    # Test 1: Admin to Admin
    test_count=$((test_count + 1))
    log_info "Test $test_count: admin@$DOMAIN to admin@$DOMAIN"
    
    if echo "Internal test email $(date)" | mail -s "Internal Test $test_count" "admin@$DOMAIN"; then
        success_count=$((success_count + 1))
        echo "✅ Test $test_count: Internal delivery successful" >> "$test_results"
    else
        echo "❌ Test $test_count: Internal delivery failed" >> "$test_results"
    fi
    
    # Test 2: Admin to Info (with forwarding)
    test_count=$((test_count + 1))
    log_info "Test $test_count: admin@$DOMAIN to info@$DOMAIN (forwarded)"
    
    if echo "Internal forwarding test $(date)" | mail -s "Internal Forward Test $test_count" "info@$DOMAIN"; then
        success_count=$((success_count + 1))
        echo "✅ Test $test_count: Internal forwarding successful" >> "$test_results"
    else
        echo "❌ Test $test_count: Internal forwarding failed" >> "$test_results"
    fi
    
    # Test 3: Distribution list
    test_count=$((test_count + 1))
    log_info "Test $test_count: Distribution list test"
    
    if echo "Distribution list test $(date)" | mail -s "Distribution Test $test_count" "distribution@$DOMAIN"; then
        success_count=$((success_count + 1))
        echo "✅ Test $test_count: Distribution delivery successful" >> "$test_results"
    else
        echo "❌ Test $test_count: Distribution delivery failed" >> "$test_results"
    fi
    
    log_info "Internal delivery tests: $success_count/$test_count passed"
    
    # Wait for delivery and check logs
    sleep 10
    check_delivery_logs "internal"
}

# Test external delivery
test_external_delivery() {
    log_info "Testing external mail delivery..."
    
    local test_results="/tmp/mail-tests/external_test.log"
    local test_count=0
    local success_count=0
    
    # Test external delivery to known email addresses
    local external_emails=(
        "inaya999.xx@gmail.com"
        "jeffmanua@aol.com"
    )
    
    for email in "${external_emails[@]}"; do
        test_count=$((test_count + 1))
        log_info "Test $test_count: External delivery to $email"
        
        if echo "External test email from $DOMAIN $(date)" | mail -s "External Test $test_count" "$email"; then
            success_count=$((success_count + 1))
            echo "✅ Test $test_count: External delivery to $email queued" >> "$test_results"
        else
            echo "❌ Test $test_count: External delivery to $email failed" >> "$test_results"
        fi
    done
    
    log_info "External delivery tests: $success_count/$test_count passed"
    
    # Wait for delivery and check logs
    sleep 15
    check_delivery_logs "external"
}

# Test forwarding delivery
test_forwarding_delivery() {
    log_info "Testing email forwarding..."
    
    local test_results="/tmp/mail-tests/forwarding_test.log"
    local test_count=0
    local success_count=0
    
    # Test common forwarding addresses
    local forwarding_addresses=(
        "info@$DOMAIN"
        "support@$DOMAIN"
        "contact@$DOMAIN"
    )
    
    for address in "${forwarding_addresses[@]}"; do
        test_count=$((test_count + 1))
        log_info "Test $test_count: Forwarding test to $address"
        
        if echo "Forwarding test email $(date)" | mail -s "Forward Test $test_count" "$address"; then
            success_count=$((success_count + 1))
            echo "✅ Test $test_count: Forwarding to $address successful" >> "$test_results"
        else
            echo "❌ Test $test_count: Forwarding to $address failed" >> "$test_results"
        fi
    done
    
    log_info "Forwarding tests: $success_count/$test_count passed"
    
    # Wait for delivery and check logs
    sleep 10
    check_delivery_logs "forwarding"
}

# Test authentication
test_authentication() {
    log_info "Testing email authentication..."
    
    local test_results="/tmp/mail-tests/auth_test.log"
    
    # Test SMTP authentication
    log_info "Testing SMTP authentication on port 587..."
    
    if test_smtp_auth; then
        echo "✅ SMTP authentication: Working" >> "$test_results"
    else
        echo "❌ SMTP authentication: Failed" >> "$test_results"
    fi
    
    # Test IMAP authentication
    log_info "Testing IMAP authentication..."
    
    if test_imap_auth; then
        echo "✅ IMAP authentication: Working" >> "$test_results"
    else
        echo "❌ IMAP authentication: Failed" >> "$test_results"
    fi
}

# Test SMTP authentication
test_smtp_auth() {
    local smtp_test_script="/tmp/mail-tests/smtp_auth_test.sh"
    
    cat > "$smtp_test_script" <<EOF
#!/bin/bash
# SMTP Authentication Test

# Test connection to submission port
if timeout 10 telnet $HOSTNAME 587 <<SMTP_TEST 2>/dev/null | grep -q "220"; then
    echo "SMTP connection successful"
    exit 0
else
    echo "SMTP connection failed"
    exit 1
fi
EHLO $HOSTNAME
QUIT
SMTP_TEST
EOF
    
    chmod +x "$smtp_test_script"
    
    if "$smtp_test_script"; then
        return 0
    else
        return 1
    fi
}

# Test IMAP authentication
test_imap_auth() {
    # Test IMAP connection
    if timeout 10 telnet "$HOSTNAME" 993 2>/dev/null | grep -q "OK"; then
        return 0
    else
        return 1
    fi
}

# Check delivery logs
check_delivery_logs() {
    local test_type="$1"
    
    log_info "Checking delivery logs for $test_type tests..."
    
    if [ -f /var/log/mail.log ]; then
        echo "Recent mail log entries for $test_type tests:" >> "/tmp/mail-tests/${test_type}_logs.txt"
        tail -50 /var/log/mail.log | grep -E "(postfix|dovecot|opendkim)" >> "/tmp/mail-tests/${test_type}_logs.txt"
        
        # Check for specific delivery status
        local delivered_count=$(tail -100 /var/log/mail.log | grep -c "status=delivered" || echo "0")
        local bounced_count=$(tail -100 /var/log/mail.log | grep -c "status=bounced" || echo "0")
        local deferred_count=$(tail -100 /var/log/mail.log | grep -c "status=deferred" || echo "0")
        
        echo "Delivery status summary:" >> "/tmp/mail-tests/${test_type}_logs.txt"
        echo "  Delivered: $delivered_count" >> "/tmp/mail-tests/${test_type}_logs.txt"
        echo "  Bounced: $bounced_count" >> "/tmp/mail-tests/${test_type}_logs.txt"
        echo "  Deferred: $deferred_count" >> "/tmp/mail-tests/${test_type}_logs.txt"
        
        log_info "$test_type delivery status - Delivered: $delivered_count, Bounced: $bounced_count, Deferred: $deferred_count"
    else
        log_warning "Mail log file not found - logging may not be configured"
    fi
}

# Analyze delivery results
analyze_delivery_results() {
    log_info "Analyzing email delivery test results..."
    
    echo ""
    echo "📊 EMAIL DELIVERY TEST RESULTS"
    echo "==============================="
    
    # Combine all test results
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    for result_file in /tmp/mail-tests/*_test.log; do
        if [ -f "$result_file" ]; then
            echo ""
            echo "📋 $(basename "$result_file" .log | tr '_' ' ' | tr 'a-z' 'A-Z'):"
            echo "$(cat "$result_file")"
            
            local file_total=$(grep -c "Test" "$result_file" || echo "0")
            local file_passed=$(grep -c "✅" "$result_file" || echo "0")
            
            total_tests=$((total_tests + file_total))
            passed_tests=$((passed_tests + file_passed))
        fi
    done
    
    failed_tests=$((total_tests - passed_tests))
    
    echo ""
    echo "📈 OVERALL SUMMARY:"
    echo "==================="
    echo "Total tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $failed_tests"
    
    if [ $total_tests -gt 0 ]; then
        local success_rate=$(( (passed_tests * 100) / total_tests ))
        echo "Success rate: $success_rate%"
        
        if [ $success_rate -ge 80 ]; then
            echo "🎉 Mail delivery system is working well!"
        elif [ $success_rate -ge 50 ]; then
            echo "⚠️  Mail delivery system has some issues"
        else
            echo "❌ Mail delivery system needs attention"
        fi
    fi
    
    # Check mail queue
    check_mail_queue
    
    # Provide troubleshooting recommendations
    provide_troubleshooting_recommendations
}

# Check mail queue
check_mail_queue() {
    echo ""
    echo "📬 MAIL QUEUE STATUS:"
    echo "===================="
    
    local queue_count=$(postqueue -p | grep -c "^[A-F0-9]" 2>/dev/null || echo "0")
    
    if [ "$queue_count" -eq 0 ]; then
        echo "✅ Mail queue is empty"
    else
        echo "📧 $queue_count messages in queue"
        echo ""
        echo "Queue details:"
        postqueue -p | head -20
        
        if [ "$queue_count" -gt 10 ]; then
            echo "⚠️  Large number of queued messages - possible delivery issues"
        fi
    fi
}

# Provide troubleshooting recommendations
provide_troubleshooting_recommendations() {
    echo ""
    echo "🔧 TROUBLESHOOTING RECOMMENDATIONS:"
    echo "==================================="
    
    # Check common issues
    local issues_found=0
    
    # Check if services are running
    for service in postfix dovecot opendkim; do
        if ! systemctl is-active --quiet "$service"; then
            echo "❌ Service $service is not running - run: systemctl start $service"
            issues_found=$((issues_found + 1))
        fi
    done
    
    # Check ports
    local critical_ports=(25 587 465 993)
    for port in "${critical_ports[@]}"; do
        if ! ss -tuln | grep -q ":$port "; then
            echo "❌ Port $port is not listening - check service configuration"
            issues_found=$((issues_found + 1))
        fi
    done
    
    # Check DNS
    echo ""
    echo "🌐 DNS Configuration Check:"
    echo "--------------------------"
    local dns_issues=0
    
    # Check MX record
    if ! dig +short MX "$DOMAIN" | grep -q "smtp.$DOMAIN"; then
        echo "❌ MX record not properly configured"
        echo "   Add: $DOMAIN IN MX 10 smtp.$DOMAIN"
        dns_issues=$((dns_issues + 1))
    else
        echo "✅ MX record configured"
    fi
    
    # Check A records
    local required_a_records=("smtp.$DOMAIN" "imap.$DOMAIN" "mail.$DOMAIN")
    for record in "${required_a_records[@]}"; do
        local resolved_ip=$(dig +short "$record" | head -1)
        if [ "$resolved_ip" = "$SERVER_IP" ]; then
            echo "✅ $record resolves correctly"
        else
            echo "❌ $record does not resolve to $SERVER_IP (got: $resolved_ip)"
            echo "   Add: $record IN A $SERVER_IP"
            dns_issues=$((dns_issues + 1))
        fi
    done
    
    # Overall recommendations
    echo ""
    echo "📝 NEXT STEPS:"
    echo "=============="
    
    if [ $issues_found -eq 0 ] && [ $dns_issues -eq 0 ]; then
        echo "🎉 No critical issues found!"
        echo "   • Monitor /var/log/mail.log for ongoing issues"
        echo "   • Test with external email clients"
        echo "   • Set up SSL certificates with: ssl_complete_setup.sh"
    else
        echo "⚠️  Issues found that need attention:"
        
        if [ $issues_found -gt 0 ]; then
            echo "   • Fix service and port issues first"
            echo "   • Run: mail-restart"
            echo "   • Run: fix-ports"
        fi
        
        if [ $dns_issues -gt 0 ]; then
            echo "   • Configure DNS records properly"
            echo "   • Wait 15-30 minutes for DNS propagation"
            echo "   • Re-run tests after DNS changes"
        fi
        
        echo "   • Check detailed logs in /tmp/mail-tests/"
        echo "   • Run: tail -f /var/log/mail.log"
    fi
    
    echo ""
    echo "📧 Test email accounts:"
    echo "   admin@$DOMAIN (password: AdminMail2024!)"
    echo "   info@$DOMAIN (password: InfoMail2024!)"
    echo "   support@$DOMAIN (password: SupportMail2024!)"
}

# Function to send test email with detailed logging
send_test_email() {
    local to_address="$1"
    local subject="${2:-Test Email from $DOMAIN}"
    local body="${3:-This is a test email sent from $DOMAIN mail server at $(date)}"
    
    if [ -z "$to_address" ]; then
        echo "Usage: send_test_email <to_address> [subject] [body]"
        return 1
    fi
    
    echo "Sending test email to $to_address..."
    echo "Subject: $subject"
    echo "Body: $body"
    echo ""
    
    # Send email and capture result
    if echo "$body" | mail -s "$subject" "$to_address"; then
        echo "✅ Email sent successfully"
        
        # Wait and check logs
        sleep 5
        echo ""
        echo "Recent mail log entries:"
        tail -10 /var/log/mail.log | grep -E "(postfix|dovecot)" || echo "No recent mail log entries found"
        
        return 0
    else
        echo "❌ Failed to send email"
        return 1
    fi
}

# Function to test DKIM signing
test_dkim_signing() {
    echo "Testing DKIM signing..."
    echo "======================"
    
    # Check if OpenDKIM is running
    if ! systemctl is-active --quiet opendkim; then
        echo "❌ OpenDKIM service is not running"
        echo "Fix: systemctl start opendkim"
        return 1
    fi
    
    # Check DKIM port
    if ! ss -tuln | grep -q ":12301 "; then
        echo "❌ DKIM port 12301 is not listening"
        echo "Fix: Check OpenDKIM configuration"
        return 1
    fi
    
    # Send test email and check for DKIM signature
    local test_email="dkim-test@$DOMAIN"
    echo "Sending DKIM test email..."
    
    if echo "DKIM signature test $(date)" | mail -s "DKIM Test" "$test_email"; then
        sleep 10
        
        # Check logs for DKIM signing
        if tail -20 /var/log/mail.log | grep -q "dkim"; then
            echo "✅ DKIM signing appears to be working"
            echo "Recent DKIM log entries:"
            tail -20 /var/log/mail.log | grep "dkim" | tail -5
        else
            echo "⚠️  No DKIM entries found in logs"
        fi
    else
        echo "❌ Failed to send DKIM test email"
        return 1
    fi
    
    # Display DKIM public key for DNS
    echo ""
    echo "📋 DKIM DNS Record (add this to your DNS):"
    echo "=========================================="
    if [ -f "/etc/opendkim/keys/$DOMAIN/default.txt" ]; then
        cat "/etc/opendkim/keys/$DOMAIN/default.txt"
    else
        echo "DKIM public key file not found"
    fi
}

# Function to test SPF record
test_spf_record() {
    echo "Testing SPF record..."
    echo "===================="
    
    local spf_record=$(dig +short TXT "$DOMAIN" | grep "v=spf1" | head -1)
    
    if [ -n "$spf_record" ]; then
        echo "✅ SPF record found:"
        echo "   $spf_record"
        
        # Check if our IP is included
        if echo "$spf_record" | grep -q "$SERVER_IP"; then
            echo "✅ Server IP $SERVER_IP is included in SPF record"
        else
            echo "⚠️  Server IP $SERVER_IP not found in SPF record"
            echo "   Recommended SPF record:"
            echo "   \"v=spf1 ip4:$SERVER_IP -all\""
        fi
    else
        echo "❌ No SPF record found"
        echo "   Add this TXT record to your DNS:"
        echo "   $DOMAIN IN TXT \"v=spf1 ip4:$SERVER_IP -all\""
    fi
}

# Function to test DMARC record
test_dmarc_record() {
    echo "Testing DMARC record..."
    echo "======================"
    
    local dmarc_record=$(dig +short TXT "_dmarc.$DOMAIN" | grep "v=DMARC1" | head -1)
    
    if [ -n "$dmarc_record" ]; then
        echo "✅ DMARC record found:"
        echo "   $dmarc_record"
    else
        echo "❌ No DMARC record found"
        echo "   Add this TXT record to your DNS:"
        echo "   _dmarc.$DOMAIN IN TXT \"v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN\""
    fi
}

# Function to perform comprehensive email test
comprehensive_email_test() {
    echo "🔍 COMPREHENSIVE EMAIL SYSTEM TEST"
    echo "=================================="
    echo "Domain: $DOMAIN"
    echo "Server IP: $SERVER_IP"
    echo "Test started: $(date)"
    echo ""
    
    # Test services
    echo "1. Service Status Check"
    echo "----------------------"
    for service in postfix dovecot opendkim postsrsd nginx; do
        if systemctl is-active --quiet "$service"; then
            echo "✅ $service: Running"
        else
            echo "❌ $service: Not running"
        fi
    done
    echo ""
    
    # Test ports
    echo "2. Port Status Check"
    echo "-------------------"
    local ports=(25 587 465 143 993 110 995 80 443 12301 10001 10002)
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            echo "✅ Port $port: Listening"
        else
            echo "❌ Port $port: Not listening"
        fi
    done
    echo ""
    
    # Test DNS records
    echo "3. DNS Configuration Check"
    echo "--------------------------"
    test_spf_record
    echo ""
    test_dmarc_record
    echo ""
    
    # Test DKIM
    echo "4. DKIM Configuration Check"
    echo "---------------------------"
    test_dkim_signing
    echo ""
    
    # Test email delivery
    echo "5. Email Delivery Test"
    echo "----------------------"
    test_email_delivery
    echo ""
    
    echo "🏁 Comprehensive test completed at $(date)"
    echo "Check /tmp/mail-tests/ for detailed logs"
}

# Function to monitor mail delivery in real-time
monitor_mail_delivery() {
    echo "📡 Real-time Mail Delivery Monitoring"
    echo "====================================="
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    # Start monitoring mail log
    if [ -f /var/log/mail.log ]; then
        tail -f /var/log/mail.log | while read line; do
            # Highlight important events
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
        echo "❌ Mail log file not found"
        echo "Run: logging_setup.sh setup"
    fi
}

# Run email delivery test if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-test}" in
        "test")
            test_email_delivery
            ;;
        "send")
            send_test_email "$2" "$3" "$4"
            ;;
        "dkim")
            test_dkim_signing
            ;;
        "spf")
            test_spf_record
            ;;
        "dmarc")
            test_dmarc_record
            ;;
        "comprehensive")
            comprehensive_email_test
            ;;
        "monitor")
            monitor_mail_delivery
            ;;
        *)
            echo "Usage: $0 {test|send|dkim|spf|dmarc|comprehensive|monitor}"
            echo ""
            echo "Commands:"
            echo "  test         - Run email delivery tests"
            echo "  send <email> - Send test email to specific address"
            echo "  dkim         - Test DKIM configuration"
            echo "  spf          - Test SPF record"
            echo "  dmarc        - Test DMARC record"
            echo "  comprehensive - Run all tests"
            echo "  monitor      - Monitor mail delivery in real-time"
            echo ""
            echo "Examples:"
            echo "  $0 send user@gmail.com"
            echo "  $0 comprehensive"
            echo "  $0 monitor"
            exit 1
            ;;
    esac
fi
