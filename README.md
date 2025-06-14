# Modular Mail Server v7.0 - Installation & Usage Guide

## 🚀 Quick Installation from GitHub

### Method 1: One-Line Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/mfq2412/postfix/main/quick-setup.sh | sudo bash
```

### Method 2: Git Clone & Install
```bash
# Clone the repository
git clone https://github.com/mfq2412/postfix.git
cd postfix

# Run the interactive setup
sudo ./setup.sh
```

### Method 3: Download & Install (No Git Required)
```bash
# Download and extract
wget https://github.com/mfq2412/postfix/archive/main.zip
unzip main.zip
cd postfix-main

# Run setup
sudo ./setup.sh
```

## 📋 Interactive Configuration

When you run the setup, you'll be prompted for:

1. **Domain Name** (e.g., `mycompany.com`)
2. **Mail Hostname** (default: `smtp.yourdomain.com`)
3. **Server IP** (auto-detected if left empty)

**Example Installation Session:**
```
==========================================
🔧 MAIL SERVER CONFIGURATION
==========================================

📧 Enter your domain name (e.g., example.com): mycompany.com
🌐 Enter mail server hostname (default: smtp.mycompany.com): [Enter]
🌍 Server IP (leave empty for auto-detection): [Enter]

==========================================
📋 CONFIGURATION SUMMARY
==========================================
🌐 Domain:           mycompany.com
📧 Mail Hostname:    smtp.mycompany.com
🌍 Server IP:        192.168.1.100 (auto-detected)
👤 Admin Email:      admin@mycompany.com
📮 Distribution:     distribution@mycompany.com

✅ Continue with this configuration? (y/N): y
```

## 📁 Repository Information

- **GitHub HTTPS:** `https://github.com/mfq2412/postfix.git`
- **GitHub SSH:** `git@github.com:mfq2412/postfix.git`
- **GitHub URL:** `https://github.com/mfq2412/postfix`
- **Raw Files:** `https://raw.githubusercontent.com/mfq2412/postfix/main/`

## Pre-Installation Requirements

### System Requirements
- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: Minimum 2GB, Recommended 4GB+
- **Storage**: Minimum 20GB free space
- **Network**: Static IP address
- **Privileges**: Root access required

### DNS Requirements (Configure BEFORE Installation)
Replace `yourdomain.com` with your actual domain:

```dns
# A Records (Required)
smtp.yourdomain.com           A    YOUR_SERVER_IP
imap.yourdomain.com           A    YOUR_SERVER_IP
mail.yourdomain.com           A    YOUR_SERVER_IP
autodiscover.yourdomain.com   A    YOUR_SERVER_IP
autoconfig.yourdomain.com     A    YOUR_SERVER_IP

# MX Record (Required)
yourdomain.com                MX   10 smtp.yourdomain.com.

# SPF Record (Recommended)
yourdomain.com                TXT  "v=spf1 ip4:YOUR_SERVER_IP include:gmail.com -all"

# DMARC Record (Recommended)
_dmarc.yourdomain.com         TXT  "v=DMARC1; p=quarantine; rua=mailto:admin@yourdomain.com"
```

**Note:** The DKIM record will be provided after installation.

## 🛠️ Installation Process

### Step 1: Choose Installation Method
```bash
# Option A: One-line install
curl -fsSL https://raw.githubusercontent.com/mfq2412/postfix/main/quick-setup.sh | sudo bash

# Option B: Git clone
git clone https://github.com/mfq2412/postfix.git && cd postfix && sudo ./setup.sh

# Option C: Download ZIP
wget https://github.com/mfq2412/postfix/archive/main.zip && unzip main.zip && cd postfix-main && sudo ./setup.sh
```

### Step 2: Follow Interactive Prompts
The script will prompt you for:
- Your domain name
- Mail server hostname  
- Server IP (optional, auto-detected)

### Step 3: What Happens During Installation
- ✅ System packages installation
- ✅ Service configuration (Postfix, Dovecot, OpenDKIM, etc.)
- ✅ User creation and mailbox setup
- ✅ Email forwarding configuration
- ✅ SSL certificate preparation
- ✅ Firewall configuration
- ✅ Management tools creation
- ✅ Comprehensive testing

### Step 4: Post-Installation Tasks
```bash
# Check status
mail-status

# Run full test
mail-test

# Get SSL certificates (after DNS propagation)
mail-ssl obtain

# Add DKIM record to DNS
dkim-test  # Shows the DNS record to add
```

## 📧 Default Mail Accounts Created

After installation, these accounts are automatically created:

| Email Address | Default Password | Purpose |
|---------------|------------------|---------|
| `admin@yourdomain.com` | `AdminMail2024!` | Administrator account |
| `info@yourdomain.com` | `InfoMail2024!` | General information |
| `support@yourdomain.com` | `SupportMail2024!` | Customer support |
| `postmaster@yourdomain.com` | `PostMaster2024!` | Mail system admin |
| `distribution@yourdomain.com` | `DistroMail2024!` | Distribution list |

**⚠️ Important:** Change these default passwords immediately after installation!

```bash
# Change password for any user
mail-user change-password admin@yourdomain.com NewSecurePassword123!
```

## 📬 Email Forwarding

The system automatically sets up these forwarding rules:

- `info@yourdomain.com` → `admin@yourdomain.com`
- `support@yourdomain.com` → `admin@yourdomain.com`
- `contact@yourdomain.com` → `admin@yourdomain.com`
- `sales@yourdomain.com` → `admin@yourdomain.com`
- `noreply@yourdomain.com` → `admin@yourdomain.com`
- `postmaster@yourdomain.com` → `admin@yourdomain.com`

### Configure Distribution List
To add external email addresses to the distribution list, edit the configuration:

```bash
# Edit forwarding members (during installation, you can set MEMBER_EMAILS)
sudo nano /opt/mailserver/config/mail_config.sh

# Or add forwarding rules after installation
mail-forward add distribution@yourdomain.com "user1@gmail.com user2@yahoo.com"
```

## 💻 Daily Usage Commands

### System Status and Monitoring
```bash
# Quick status check
mail-status

# Full functionality test
mail-test

# Restart all services
mail-restart

# Fix inactive ports
fix-ports
```

### User Management
```bash
# Add new user
mail-user add newuser@yourdomain.com password123

# List all users
mail-user list

# Remove user
mail-user remove olduser@yourdomain.com

# Change password
mail-user change-password user@yourdomain.com newpassword456
```

### Email Forwarding Management
```bash
# Add forwarding rule
mail-forward add info@yourdomain.com external@gmail.com

# List forwarding rules
mail-forward list

# Remove forwarding rule
mail-forward remove info@yourdomain.com

# Test forwarding configuration
mail-forward test
```

### SSL Certificate Management
```bash
# Obtain Let's Encrypt certificates
mail-ssl obtain

# Check certificate status
mail-ssl status

# Manually renew certificates
mail-ssl renew
```

### DKIM Management
```bash
# Test DKIM configuration
dkim-test

# View DKIM public key for DNS
cat /etc/opendkim/keys/yourdomain.com/default.txt
```

## 📧 Mail Client Configuration

### IMAP Settings
```
Server: smtp.yourdomain.com
Port: 993
Security: SSL/TLS
Authentication: Normal password
Username: your-full-email@yourdomain.com
Password: your-password
```

### SMTP Settings
```
Server: smtp.yourdomain.com
Port: 587 (STARTTLS) or 465 (SSL)
Security: STARTTLS or SSL/TLS
Authentication: Normal password
Username: your-full-email@yourdomain.com
Password: your-password
```

### Autodiscovery
Most modern email clients will automatically configure using:
- `autodiscover.yourdomain.com`
- `autoconfig.yourdomain.com`

## 🔧 Configuration After Installation

If you need to modify settings after installation:

### Email Forwarding Members
```bash
# Edit the member list
sudo nano /opt/mailserver/config/mail_config.sh
# Look for MEMBER_EMAILS line and update

# Or use the forwarding management tool
mail-forward add source@domain.com destination@external.com
```

### Add More Domains
```bash
# Edit configuration to add additional domains
sudo nano /opt/mailserver/config/mail_config.sh
# Add domains to virtual_mailbox_domains in postfix_setup.sh
```

### Custom Settings
```bash
# Advanced Postfix settings
sudo nano /etc/postfix/main.cf

# Advanced Dovecot settings  
sudo nano /etc/dovecot/dovecot.conf

# Restart services after changes
mail-restart
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Services Not Starting
```bash
# Check specific service
systemctl status postfix
systemctl status dovecot
systemctl status opendkim

# View logs
journalctl -u postfix -f
journalctl -u dovecot -f

# Restart services
mail-restart
```

#### 2. Ports Not Active
```bash
# Check port status
ss -tuln | grep -E ':(25|465|587|993)'

# Fix all ports
fix-ports

# Manual service restart
systemctl restart postfix
systemctl restart dovecot
```

#### 3. Email Authentication Failing
```bash
# Test user authentication
doveadm auth test user@yourdomain.com password

# Check user database
cat /etc/dovecot/users

# Recreate user
mail-user remove user@yourdomain.com
mail-user add user@yourdomain.com newpassword
```

#### 4. DKIM Not Working
```bash
# Test DKIM
dkim-test

# Check OpenDKIM service
systemctl status opendkim

# Restart OpenDKIM
systemctl restart opendkim

# Verify DKIM keys
ls -la /etc/opendkim/keys/yourdomain.com/
```

#### 5. Email Forwarding Issues
```bash
# Test forwarding
mail-forward test

# Check virtual maps
postmap -q distribution@yourdomain.com /etc/postfix/virtual

# Rebuild virtual database
postmap /etc/postfix/virtual
systemctl reload postfix
```

#### 6. SSL Certificate Problems
```bash
# Check certificate status
mail-ssl status

# Obtain new certificates
mail-ssl obtain

# Manual certificate check
openssl x509 -text -noout -in /etc/letsencrypt/live/smtp.yourdomain.com/fullchain.pem
```

### Diagnostic Commands

#### Complete System Diagnosis
```bash
# Run comprehensive test
mail-test

# Check all components
mail-status

# View recent logs
tail -f /opt/mailserver/logs/mailserver-setup.log
```

#### Port Connectivity Test
```bash
# Test from external server
telnet your-server-ip 25
telnet your-server-ip 587
telnet your-server-ip 993

# Test locally
nc -zv localhost 25
nc -zv localhost 587
nc -zv localhost 993
```

#### Email Flow Test
```bash
# Send test email (requires mail command)
echo "Test email" | mail -s "Test Subject" admin@yourdomain.com

# Check mail queue
postqueue -p

# Check mail logs
tail -f /var/log/mail.log
```

## Mail Client Configuration

### IMAP Settings
```
Server: smtp.yourdomain.com
Port: 993
Security: SSL/TLS
Authentication: Normal password
Username: your-full-email@yourdomain.com
Password: your-password
```

### SMTP Settings
```
Server: smtp.yourdomain.com
Port: 587 (STARTTLS) or 465 (SSL)
Security: STARTTLS or SSL/TLS
Authentication: Normal password
Username: your-full-email@yourdomain.com
Password: your-password
```

### Autodiscovery
Most modern email clients will automatically configure using:
- `autodiscover.yourdomain.com`
- `autoconfig.yourdomain.com`

## Advanced Configuration

### Adding Custom Modules
1. Create new module in `/opt/mailserver/modules/`
2. Follow existing module structure
3. Add to service list in `mail_config.sh`
4. Update `setup.sh` to include new module

### Custom Forwarding Rules
```bash
# Add complex forwarding rules
echo "catch-all@yourdomain.com admin@yourdomain.com" >> /etc/postfix/virtual
postmap /etc/postfix/virtual
systemctl reload postfix
```

### Performance Tuning
```bash
# Edit Postfix settings
nano /etc/postfix/main.cf

# Edit Dovecot settings
nano /etc/dovecot/dovecot.conf

# Restart services after changes
mail-restart
```

## Security Best Practices

### 1. Regular Updates
```bash
# Update system packages
apt update && apt upgrade

# Check security updates
unattended-upgrades --dry-run
```

### 2. Monitor Logs
```bash
# Watch mail logs
tail -f /var/log/mail.log

# Check authentication failures
grep "authentication failed" /var/log/mail.log
```

### 3. Firewall Management
```bash
# Check firewall status
ufw status

# Add custom rules if needed
ufw allow from trusted-ip to any port 22
```

### 4. SSL Certificate Monitoring
```bash
# Check certificate expiry
mail-ssl status

# Set up automated renewal monitoring
echo "0 0 * * 0 /opt/mailserver/bin/mail-ssl renew" | crontab -
```

## Backup and Recovery

### Configuration Backup
```bash
# Backup configuration files
tar -czf /opt/mailserver/backups/config-$(date +%Y%m%d).tar.gz \
  /etc/postfix/ \
  /etc/dovecot/ \
  /etc/opendkim/ \
  /opt/mailserver/config/
```

### Mail Data Backup
```bash
# Backup mail data
tar -czf /opt/mailserver/backups/maildata-$(date +%Y%m%d).tar.gz \
  /var/mail/vhosts/
```

### Full System Recovery
```bash
# 1. Restore configuration
tar -xzf /opt/mailserver/backups/config-YYYYMMDD.tar.gz -C /

# 2. Restore mail data
tar -xzf /opt/mailserver/backups/maildata-YYYYMMDD.tar.gz -C /

# 3. Restart services
mail-restart

# 4. Verify functionality
mail-test
```

## Support and Maintenance

### Regular Maintenance Tasks
```bash
# Weekly: Check system status
mail-status

# Monthly: Full functionality test
mail-test

# Quarterly: Review and update configuration
nano /opt/mailserver/config/mail_config.sh
```

### Performance Monitoring
```bash
# Check system resources
htop
df -h
free -h

# Monitor mail queue
postqueue -p

# Check connection counts
netstat -an | grep :25 | wc -l
```

### Getting Help
- Check logs: `/opt/mailserver/logs/`
- Run diagnostics: `mail-test`
- Review configuration: `/opt/mailserver/config/mail_config.sh`
- Test specific components: `dkim-test`, `mail-forward test`

This modular approach ensures reliable, maintainable, and scalable mail server operation with comprehensive management tools and excellent troubleshooting capabilities.
