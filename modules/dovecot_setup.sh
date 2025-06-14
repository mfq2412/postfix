#!/bin/bash

# ==========================================
# DOVECOT SETUP MODULE
# Dovecot IMAP/POP3 server configuration
# ==========================================

set -e

# Source configuration and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/mail_config.sh"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize if run directly
[ -z "$LOG_FILE" ] && init_common

# Main Dovecot setup function
setup_dovecot() {
    log_step "CONFIGURING DOVECOT IMAP/POP3 SERVER"
    
    backup_dovecot_config
    configure_dovecot_main
    create_dovecot_users_file
    test_dovecot_config
    
    log_success "Dovecot configuration completed"
}

# Backup current configuration
backup_dovecot_config() {
    log_info "Backing up Dovecot configuration..."
    backup_config "/etc/dovecot/dovecot.conf"
}

# Configure main Dovecot settings
configure_dovecot_main() {
    log_info "Configuring Dovecot main settings..."
    
    cat > /etc/dovecot/dovecot.conf << 'EOF'
# Dovecot configuration for mail server

# Protocols and networking
protocols = imap pop3 lmtp
listen = *, ::
disable_plaintext_auth = yes
auth_mechanisms = plain login

# Mail location and users
mail_location = maildir:/var/mail/vhosts/%d/%n
mail_uid = vmail
mail_gid = vmail
mail_privileged_group = vmail
first_valid_uid = 5000
last_valid_uid = 5000

# Connection settings
mail_max_userip_connections = 10
login_greeting = Dovecot ready.
login_trusted_networks = 127.0.0.0/8

# User and password databases
userdb {
  driver = passwd-file
  args = scheme=CRYPT username_format=%u /etc/dovecot/users
}

passdb {
  driver = passwd-file
  args = scheme=CRYPT username_format=%u /etc/dovecot/users
}

# SSL configuration
ssl = required
ssl_cert = </etc/ssl/certs/ssl-cert-snakeoil.pem
ssl_key = </etc/ssl/private/ssl-cert-snakeoil.key
ssl_min_protocol = TLSv1.2

# IMAP service
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
  process_min_avail = 1
  process_limit = 50
  service_count = 1
  vsz_limit = 128M
}

# POP3 service
service pop3-login {
  inet_listener pop3 {
    port = 110
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}

# LMTP service for Postfix integration
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    group = postfix
    mode = 0600
    user = postfix
  }
}

# Authentication service for SMTP AUTH
service auth {
  unix_listener /var/spool/postfix/private/auth {
    group = postfix
    mode = 0666
    user = postfix
  }
  unix_listener auth-userdb {
    group = vmail
    mode = 0600
    user = vmail
  }
}

service auth-worker {
  user = vmail
}

# Namespace configuration
namespace inbox {
  inbox = yes
  location = 
  mailbox Drafts {
    special_use = \Drafts
    auto = subscribe
  }
  mailbox Junk {
    special_use = \Junk
    auto = subscribe
  }
  mailbox Sent {
    special_use = \Sent
    auto = subscribe
  }
  mailbox "Sent Messages" {
    special_use = \Sent
  }
  mailbox Trash {
    special_use = \Trash
    auto = subscribe
  }
  prefix = 
}

# Protocol-specific settings
protocol imap {
  mail_max_userip_connections = 10
}

protocol pop3 {
  mail_max_userip_connections = 5
  pop3_uidl_format = %08Xu%08Xv
}

# Logging
log_path = /var/log/dovecot.log
auth_verbose = no
auth_debug = no
auth_debug_passwords = no
mail_debug = no
verbose_ssl = no
EOF
}

# Create users file
create_dovecot_users_file() {
    log_info "Creating Dovecot users file..."
    
    touch /etc/dovecot/users
    chmod 640 /etc/dovecot/users
    chown root:dovecot /etc/dovecot/users
}

# Test Dovecot configuration
test_dovecot_config() {
    log_info "Testing Dovecot configuration..."
    
    if test_config "dovecot"; then
        log_success "Dovecot configuration is valid"
    else
        log_error "Dovecot configuration test failed"
        exit 1
    fi
}

# Run Dovecot setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_dovecot
fi