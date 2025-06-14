#!/bin/bash

# ==========================================
# MAIL SERVER CONFIGURATION
# Central configuration file for all modules
# ==========================================

# Domain and server configuration - Will be updated during installation
DOMAIN="${DOMAIN:-example.com}"
HOSTNAME="${HOSTNAME:-smtp.example.com}"
SERVER_IP="${SERVER_IP:-}"  # Auto-detected if empty

# DKIM configuration
DKIM_SELECTOR="${DKIM_SELECTOR:-default}"

# Email addresses - Will be updated based on domain during installation
ADMIN_EMAIL="admin@example.com"
DISTRO_EMAIL="distribution@example.com"

# Email forwarding configuration
MEMBER_EMAILS="${MEMBER_EMAILS:-inaya999.xx@gmail.com,jeffmanua@aol.com,mdfaisalqureshi88@gmail.com,cuddington@comcast.net,cuddington9211@att.net,jeffmanua9211@mailbox.org}"

# Default mail users (email:password format) - Will be updated based on domain
declare -a MAIL_USERS=(
    "admin@example.com:AdminMail2024!"
    "info@example.com:InfoMail2024!"
    "support@example.com:SupportMail2024!"
    "postmaster@example.com:PostMaster2024!"
    "distribution@example.com:DistroMail2024!"
)

# Service configuration
declare -a SERVICES=("postsrsd" "opendkim" "postfix" "dovecot" "nginx")

# Port configuration
declare -A REQUIRED_PORTS=(
    ["25"]="SMTP"
    ["465"]="SMTPS"
    ["587"]="Submission"
    ["143"]="IMAP"
    ["993"]="IMAPS"
    ["110"]="POP3"
    ["995"]="POP3S"
    ["80"]="HTTP"
    ["443"]="HTTPS"
    ["10001"]="SRS-Forward"
    ["10002"]="SRS-Reverse"
    ["12301"]="OpenDKIM"
)

# Critical ports for connectivity testing
CRITICAL_PORTS=("25" "465" "587" "993")

# Directory structure
MAILSERVER_DIR="/opt/mailserver"
BIN_DIR="$MAILSERVER_DIR/bin"
CONFIG_DIR="$MAILSERVER_DIR/config"
LOG_DIR="$MAILSERVER_DIR/logs"
BACKUP_DIR="$MAILSERVER_DIR/backups"

# Logging configuration
LOG_FILE="$LOG_DIR/mailserver-setup.log"

# SSL configuration
SSL_DOMAINS=("$HOSTNAME" "autodiscover.$DOMAIN" "autoconfig.$DOMAIN" "imap.$DOMAIN" "mail.$DOMAIN")

# Package lists
REQUIRED_PACKAGES=(
    "postfix"
    "opendkim" "opendkim-tools"
    "dovecot-core" "dovecot-imapd" "dovecot-pop3d" "dovecot-lmtpd"
    "nginx" "certbot" "python3-certbot-nginx"
    "postsrsd"
    "ufw" "dnsutils" "mailutils"
    "net-tools" "telnet" "curl" "wget"
)

# Postfix configuration templates
POSTFIX_MAIN_TEMPLATE="$CONFIG_DIR/templates/postfix_main.cf"
POSTFIX_MASTER_TEMPLATE="$CONFIG_DIR/templates/postfix_master.cf"

# Dovecot configuration template
DOVECOT_TEMPLATE="$CONFIG_DIR/templates/dovecot.conf"

# OpenDKIM configuration template
OPENDKIM_TEMPLATE="$CONFIG_DIR/templates/opendkim.conf"

# Export all variables for use in other scripts
export DOMAIN HOSTNAME SERVER_IP DKIM_SELECTOR ADMIN_EMAIL DISTRO_EMAIL
export MEMBER_EMAILS MAIL_USERS SERVICES REQUIRED_PORTS CRITICAL_PORTS
export MAILSERVER_DIR BIN_DIR CONFIG_DIR LOG_DIR BACKUP_DIR LOG_FILE
export SSL_DOMAINS REQUIRED_PACKAGES
export POSTFIX_MAIN_TEMPLATE POSTFIX_MASTER_TEMPLATE DOVECOT_TEMPLATE OPENDKIM_TEMPLATE
