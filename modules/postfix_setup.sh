#!/bin/bash

# ==========================================
# POSTFIX SETUP MODULE
# Postfix configuration with submission ports
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main Postfix setup function
setup_postfix() {
    log_step "CONFIGURING POSTFIX WITH SUBMISSION PORTS"
    
    backup_postfix_config
    configure_postfix_main
    configure_postfix_master
    create_postfix_maps
    test_postfix_config
    
    log_success "Postfix configuration completed"
}

# Backup current configuration
backup_postfix_config() {
    log_info "Backing up Postfix configuration..."
    
    backup_config "/etc/postfix/main.cf"
    backup_config "/etc/postfix/master.cf"
}

# Configure main.cf
configure_postfix_main() {
    log_info "Configuring Postfix main.cf..."
    
    # Basic settings
    postconf -e "myhostname = $HOSTNAME"
    postconf -e "mydomain = $DOMAIN"
    postconf -e "myorigin = \$mydomain"
    
    # Destination configuration
    postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
    postconf -e "virtual_mailbox_domains = \$mydomain"
    postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
    
    # Network settings
    postconf -e "relayhost ="
    postconf -e "inet_interfaces = all"
    postconf -e "inet_protocols = ipv4"
    postconf -e "home_mailbox = Maildir/"
    postconf -e "smtpd_banner = \$myhostname ESMTP"

    # TLS Configuration
    postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
    postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
    postconf -e "smtpd_use_tls = yes"
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_tls_security_level = may"
    postconf -e "smtpd_tls_security_level = may"
    postconf -e "smtpd_tls_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1"
    postconf -e "smtp_tls_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1"

    # DKIM milter configuration
    postconf -e "milter_protocol = 6"
    postconf -e "milter_default_action = accept"
    postconf -e "smtpd_milters = inet:localhost:12301"
    postconf -e "non_smtpd_milters = inet:localhost:12301"
    postconf -e "milter_mail_macros = i {mail_addr} {client_addr} {client_name} {auth_authen}"

    # SASL configuration
    postconf -e "smtpd_sasl_type = dovecot"
    postconf -e "smtpd_sasl_path = private/auth"
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "broken_sasl_auth_clients = yes"
    postconf -e "smtpd_sasl_security_options = noanonymous"
    postconf -e "smtpd_sasl_local_domain = \$myhostname"
    postconf -e "smtpd_sasl_authenticated_header = yes"

    # Virtual domains and mailboxes
    postconf -e "virtual_mailbox_maps = hash:/etc/postfix/vmailbox"
    postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"
    postconf -e "local_transport = virtual"
    postconf -e "transport_maps = hash:/etc/postfix/transport"

    # SRS configuration
    postconf -e "sender_canonical_maps = tcp:localhost:10001"
    postconf -e "sender_canonical_classes = envelope_sender"
    postconf -e "recipient_canonical_maps = tcp:localhost:10002"
    postconf -e "recipient_canonical_classes = envelope_recipient"

    # Security restrictions
    configure_postfix_restrictions

    # Rate limiting and size limits
    postconf -e "smtpd_client_connection_count_limit = 50"
    postconf -e "smtpd_client_connection_rate_limit = 30"
    postconf -e "message_size_limit = 50000000"
    postconf -e "mailbox_size_limit = 0"
}

# Configure security restrictions
configure_postfix_restrictions() {
    log_info "Configuring Postfix security restrictions..."
    
    postconf -e "smtpd_helo_required = no"
    postconf -e "smtpd_delay_reject = no"
    postconf -e "smtpd_helo_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_invalid_helo_hostname"
    postconf -e "smtpd_sender_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_sender"
    postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_recipient, reject_unknown_recipient_domain, reject_unauth_destination, permit"
    postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
}

# Configure master.cf with submission ports
configure_postfix_master() {
    log_info "Configuring Postfix master.cf with submission ports..."
    
    cat > /etc/postfix/master.cf << 'EOF'
#
# Postfix master process configuration file
# ==========================================================================
# service type  private unpriv  chroot  wakeup  maxproc command + args
#               (yes)   (yes)   (yes)   (never) (100)
# ==========================================================================
smtp      inet  n       -       y       -       -       smtpd
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache

# Submission ports configuration
587       inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_helo_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

465       inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_helo_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF
}

# Create Postfix maps
create_postfix_maps() {
    log_info "Creating Postfix maps..."
    
    # Create transport map
    cat > /etc/postfix/transport <<EOF
# Transport map for external forwarding
$DOMAIN     lmtp:unix:private/dovecot-lmtp
gmail.com   smtp:
yahoo.com   smtp:
aol.com     smtp:
EOF
    postmap /etc/postfix/transport
    
    # Create empty virtual maps (will be populated by other modules)
    touch /etc/postfix/virtual
    touch /etc/postfix/vmailbox
    postmap /etc/postfix/virtual
    postmap /etc/postfix/vmailbox
}

# Test Postfix configuration
test_postfix_config() {
    log_info "Testing Postfix configuration..."
    
    if test_config "postfix"; then
        log_success "Postfix configuration is valid"
    else
        log_error "Postfix configuration test failed"
        exit 1
    fi
}

# Run Postfix setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_postfix
fi