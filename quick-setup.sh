#!/bin/bash

# ==========================================
# QUICK SETUP SCRIPT
# Downloads and sets up modular mail server
# ==========================================

set -e

echo "🚀 Modular Mail Server Setup v7.0"
echo "=================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Please run: sudo bash $0"
    exit 1
fi

# Configuration
MAILSERVER_DIR="/opt/mailserver"
REPO_BASE_URL="https://raw.githubusercontent.com/your-repo/modular-mail-server/main"

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$MAILSERVER_DIR"/{modules,config,lib,bin,logs,backups}
mkdir -p "$MAILSERVER_DIR/config/templates"

# Download configuration files
echo "⬇️  Downloading configuration files..."

# Core configuration
curl -s "$REPO_BASE_URL/config/mail_config.sh" -o "$MAILSERVER_DIR/config/mail_config.sh"
curl -s "$REPO_BASE_URL/lib/common.sh" -o "$MAILSERVER_DIR/lib/common.sh"

# Download modules
echo "⬇️  Downloading modules..."
modules=(
    "system_setup.sh"
    "postfix_setup.sh" 
    "dovecot_setup.sh"
    "opendkim_setup.sh"
    "postsrsd_setup.sh"
    "nginx_setup.sh"
    "firewall_setup.sh"
    "ssl_setup.sh"
    "mail_users_setup.sh"
    "forwarding_setup.sh"
    "service_manager.sh"
    "verification.sh"
    "management_tools.sh"
)

for module in "${modules[@]}"; do
    curl -s "$REPO_BASE_URL/modules/$module" -o "$MAILSERVER_DIR/modules/$module"
    chmod +x "$MAILSERVER_DIR/modules/$module"
done

# Download main setup script
curl -s "$REPO_BASE_URL/setup.sh" -o "$MAILSERVER_DIR/setup.sh"
chmod +x "$MAILSERVER_DIR/setup.sh"

# Set permissions
chmod +x "$MAILSERVER_DIR/config/mail_config.sh"
chmod +x "$MAILSERVER_DIR/lib/common.sh"

echo "✅ Download completed!"
echo ""
echo "🔧 To configure and run the mail server:"
echo "1. Edit configuration: nano $MAILSERVER_DIR/config/mail_config.sh"
echo "2. Run setup: $MAILSERVER_DIR/setup.sh"
echo ""
echo "📚 Available after setup:"
echo "   mail-status    - Check server status"
echo "   mail-test      - Test functionality"
echo "   mail-user      - Manage users"
echo "   mail-forward   - Manage forwarding"

# Ask if user wants to run setup now
echo ""
read -p "Do you want to run the setup now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Starting mail server setup..."
    "$MAILSERVER_DIR/setup.sh"
else
    echo "Setup skipped. Run '$MAILSERVER_DIR/setup.sh' when ready."
fi
