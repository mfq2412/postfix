#!/bin/bash

# ==========================================
# EMAIL FORWARDING SETUP MODULE
# Configure email forwarding and aliases
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main forwarding setup function
setup_forwarding() {
    log_step "SETTING UP EMAIL FORWARDING"
    
    initialize_virtual_file
    setup_distribution_list
    setup_common_aliases
    update_virtual_maps
    test_forwarding_config
    
    log_success "Email forwarding setup completed"
}

# Initialize virtual aliases file
initialize_virtual_file() {
    log_info "Initializing virtual aliases file..."
    
    # Create or clear virtual file
    > /etc/postfix/virtual
    
    # Add header comment
    cat > /etc/postfix/virtual <<EOF
# Virtual alias map for email forwarding
# Format: source_email destination_email(s)
# Multiple destinations separated by spaces

EOF
    
    chmod 644 /etc/postfix/virtual
    chown root:root /etc/postfix/virtual
}

# Setup distribution list
setup_distribution_list() {
    log_info "Setting up distribution list..."
    
    if [ -n "$MEMBER_EMAILS" ]; then
        # Convert comma-separated to space-separated for Postfix
        local formatted_members=$(echo "$MEMBER_EMAILS" | tr ',' ' ')
        
        # Add distribution list entry
        echo "$DISTRO_EMAIL $formatted_members" >> /etc/postfix/virtual
        
        log_success "Distribution list configured: $DISTRO_EMAIL"
        log_info "Members: $MEMBER_EMAILS"
    else
        log_warning "No member emails configured for distribution list"
    fi
}

# Setup common aliases
setup_common_aliases() {
    log_info "Setting up common email aliases..."
    
    # Common aliases that forward to admin
    local common_aliases=(
        "info@$DOMAIN"
        "support@$DOMAIN"
        "contact@$DOMAIN"
        "sales@$DOMAIN"
        "noreply@$DOMAIN"
        "postmaster@$DOMAIN"
        "abuse@$DOMAIN"
        "hostmaster@$DOMAIN"
    )
    
    for alias in "${common_aliases[@]}"; do
        echo "$alias $ADMIN_EMAIL" >> /etc/postfix/virtual
    done
    
    log_success "Common aliases configured"
}

# Update virtual maps
update_virtual_maps() {
    log_info "Updating virtual maps..."
    
    # Generate virtual alias database
    postmap /etc/postfix/virtual
    
    # Verify database creation
    if [ -f /etc/postfix/virtual.db ]; then
        log_success "Virtual alias database created"
    else
        log_error "Failed to create virtual alias database"
        return 1
    fi
    
    # Display forwarding summary
    local rule_count=$(grep -c -v "^#" /etc/postfix/virtual | grep -c -v "^$" || echo "0")
    log_info "Created $rule_count forwarding rules"
}

# Test forwarding configuration
test_forwarding_config() {
    log_info "Testing forwarding configuration..."
    
    # Check if virtual file exists and has content
    if [ ! -f /etc/postfix/virtual ] || [ ! -s /etc/postfix/virtual ]; then
        log_error "Virtual file is missing or empty"
        return 1
    fi
    
    # Check if virtual.db exists
    if [ ! -f /etc/postfix/virtual.db ]; then
        log_error "Virtual database is missing"
        return 1
    fi
    
    # Check if postfix is configured for virtual aliases
    if ! postconf virtual_alias_maps | grep -q virtual; then
        log_error "Postfix not configured for virtual aliases"
        return 1
    fi
    
    # Test distribution list lookup
    if [ -n "$MEMBER_EMAILS" ]; then
        local lookup_result=$(postmap -q "$DISTRO_EMAIL" /etc/postfix/virtual 2>/dev/null || echo "")
        if [ -n "$lookup_result" ]; then
            log_success "Distribution list lookup test passed"
        else
            log_warning "Distribution list lookup test failed"
        fi
    fi
    
    log_success "Forwarding configuration tests passed"
}

# Function to add forwarding rule
add_forwarding_rule() {
    local source="$1"
    local destination="$2"
    
    if [ -z "$source" ] || [ -z "$destination" ]; then
        log_error "Source and destination required"
        return 1
    fi
    
    # Validate email formats
    if ! validate_email "$source"; then
        log_error "Invalid source email format: $source"
        return 1
    fi
    
    # Check if rule already exists
    if grep -q "^$source " /etc/postfix/virtual 2>/dev/null; then
        log_warning "Forwarding rule for $source already exists"
        return 1
    fi
    
    # Add forwarding rule
    echo "$source $destination" >> /etc/postfix/virtual
    
    # Update database
    postmap /etc/postfix/virtual
    
    # Reload postfix
    systemctl reload postfix 2>/dev/null || true
    
    log_success "Forwarding rule added: $source → $destination"
}

# Function to remove forwarding rule
remove_forwarding_rule() {
    local source="$1"
    
    if [ -z "$source" ]; then
        log_error "Source email required"
        return 1
    fi
    
    if [ ! -f /etc/postfix/virtual ]; then
        log_error "Virtual aliases file not found"
        return 1
    fi
    
    # Check if rule exists
    if ! grep -q "^$source " /etc/postfix/virtual; then
        log_error "Forwarding rule for $source not found"
        return 1
    fi
    
    # Remove rule
    sed -i "/^$source /d" /etc/postfix/virtual
    
    # Update database
    postmap /etc/postfix/virtual
    
    # Reload postfix
    systemctl reload postfix 2>/dev/null || true
    
    log_success "Forwarding rule removed for: $source"
}

# Function to list forwarding rules
list_forwarding_rules() {
    echo "Email Forwarding Rules:"
    echo "======================"
    
    if [ -f /etc/postfix/virtual ] && [ -s /etc/postfix/virtual ]; then
        grep -v "^#" /etc/postfix/virtual | grep -v "^$" | while read -r line; do
            [ -n "$line" ] && echo "📧 $line"
        done
    else
        echo "No forwarding rules found"
    fi
}

# Function to update distribution list
update_distribution_list() {
    local new_members="$1"
    
    if [ -z "$new_members" ]; then
        log_error "New member list required"
        return 1
    fi
    
    # Convert comma-separated to space-separated
    local formatted_members=$(echo "$new_members" | tr ',' ' ')
    
    # Remove old distribution entry
    sed -i "/^$DISTRO_EMAIL /d" /etc/postfix/virtual
    
    # Add new distribution entry
    echo "$DISTRO_EMAIL $formatted_members" >> /etc/postfix/virtual
    
    # Update database
    postmap /etc/postfix/virtual
    
    # Reload postfix
    systemctl reload postfix 2>/dev/null || true
    
    log_success "Distribution list updated with: $formatted_members"
}

# Function to test forwarding functionality
test_forwarding_functionality() {
    echo "Testing Email Forwarding Configuration"
    echo "====================================="
    
    # Test 1: Check virtual file
    if [ ! -f /etc/postfix/virtual ] || [ ! -s /etc/postfix/virtual ]; then
        echo "❌ Virtual file missing or empty"
        return 1
    fi
    echo "✅ Virtual file exists and has content"
    
    # Test 2: Check virtual database
    if [ ! -f /etc/postfix/virtual.db ]; then
        echo "❌ Virtual database missing"
        echo "Fix: postmap /etc/postfix/virtual"
        return 1
    fi
    echo "✅ Virtual database exists"
    
    # Test 3: Check Postfix configuration
    if ! postconf virtual_alias_maps | grep -q virtual; then
        echo "❌ Postfix not configured for virtual aliases"
        return 1
    fi
    echo "✅ Postfix configured for virtual aliases"
    
    # Test 4: Test distribution list lookup
    if [ -n "$MEMBER_EMAILS" ]; then
        local lookup_result=$(postmap -q "$DISTRO_EMAIL" /etc/postfix/virtual 2>/dev/null || echo "")
        if [ -n "$lookup_result" ]; then
            echo "✅ Distribution list lookup working"
            echo "   $DISTRO_EMAIL → $lookup_result"
        else
            echo "❌ Distribution list lookup failed"
        fi
    fi
    
    # Test 5: Show active rules
    echo ""
    echo "Active forwarding rules:"
    echo "------------------------"
    list_forwarding_rules
    
    echo ""
    echo "✅ Forwarding configuration test completed"
}

# Function to show forwarding statistics
show_forwarding_stats() {
    echo "Email Forwarding Statistics"
    echo "=========================="
    
    if [ -f /etc/postfix/virtual ] && [ -s /etc/postfix/virtual ]; then
        local total_rules=$(grep -c -v "^#" /etc/postfix/virtual | grep -c -v "^$" || echo "0")
        local distribution_rules=$(grep -c "$DISTRO_EMAIL" /etc/postfix/virtual || echo "0")
        local alias_rules=$((total_rules - distribution_rules))
        
        echo "Total forwarding rules: $total_rules"
        echo "Distribution lists: $distribution_rules"
        echo "Email aliases: $alias_rules"
        
        # Show domains being forwarded to
        echo ""
        echo "External domains receiving forwarded mail:"
        grep -v "^#" /etc/postfix/virtual | grep -v "^$" | awk '{for(i=2;i<=NF;i++) print $i}' | sed 's/.*@//' | sort | uniq -c | sort -nr
    else
        echo "No forwarding rules configured"
    fi
}

# Run forwarding setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            setup_forwarding
            ;;
        "add")
            add_forwarding_rule "$2" "$3"
            ;;
        "remove")
            remove_forwarding_rule "$2"
            ;;
        "list")
            list_forwarding_rules
            ;;
        "update-distribution")
            update_distribution_list "$2"
            ;;
        "test")
            test_forwarding_functionality
            ;;
        "stats")
            show_forwarding_stats
            ;;
        *)
            echo "Usage: $0 {setup|add|remove|list|update-distribution|test|stats}"
            echo ""
            echo "Commands:"
            echo "  setup                          - Set up initial forwarding configuration"
            echo "  add <source> <destination>     - Add forwarding rule"
            echo "  remove <source>                - Remove forwarding rule"
            echo "  list                           - List all forwarding rules"
            echo "  update-distribution <members>  - Update distribution list"
            echo "  test                           - Test forwarding configuration"
            echo "  stats                          - Show forwarding statistics"
            exit 1
            ;;
    esac
fi