# Security Hardening Role

Comprehensive security hardening role untuk server infrastructure dengan multiple layers of protection.

## 🛡️ Security Features

### 1. **UFW Firewall**
- Default deny all incoming traffic
- Allow specific ports only (SSH, HTTP, HTTPS, NPM dashboard)
- Rate limiting untuk SSH (anti brute-force)
- IP whitelisting/blacklisting
- Database ports restricted to localhost by default

### 2. **Fail2ban**
- Automatic IP banning for suspicious activity
- SSH protection (3 attempts → 24h ban)
- Nginx protection (bad bots, DDoS, proxy attempts)
- Docker daemon protection
- UFW integration for banning

### 3. **SSH Hardening**
- Disable root login
- Key-based authentication only (no passwords)
- Strong cryptographic algorithms
- Connection timeout
- Max auth tries limit
- Verbose logging

### 4. **Docker Security**
- User namespace remapping (container isolation)
- Seccomp and AppArmor profiles
- Prevent privilege escalation
- Log rotation
- Restricted socket permissions
- Audit logging (optional)

### 5. **System Hardening**
- Kernel parameter tuning (sysctl)
- Automatic security updates
- SYN flood protection
- Disable IP forwarding (unless needed)
- Reverse path filtering
- Rootkit detection (optional)

## 📋 Requirements

- Ansible 2.9+
- Ubuntu 20.04+ / Debian 10+
- Root/sudo access
- Collections:
  - `community.general`
  - `ansible.posix`

## 🚀 Installation

### Via Playbook

```yaml
# playbooks/server-setup.yml
- role: security-hardening
  tags: [security, security-hardening]
```

### Via Makefile

```bash
# Full security setup
make setup-tags TAGS=security-hardening

# Specific security components
make setup-tags TAGS=security-ufw
make setup-tags TAGS=security-fail2ban
make setup-tags TAGS=security-ssh
make setup-tags TAGS=security-docker
make setup-tags TAGS=security-system
```

## ⚙️ Configuration

### Default Variables (`defaults/main.yml`)

```yaml
# UFW Firewall
security_ssh_port: 2222                          # Match ansible_port
security_allow_npm_dashboard: true               # Allow port 81
security_allow_mysql_external: false             # Restrict to localhost
security_allow_postgres_external: false
security_allow_redis_external: false

# Custom ports
security_custom_allowed_ports:
  - port: 8080
    proto: tcp
    comment: "Custom app"

# IP Whitelist
security_whitelist_ips:
  - ip: "192.168.1.100"
    comment: "Office IP"

# Fail2ban
security_fail2ban_bantime: "1h"
security_fail2ban_findtime: "10m"
security_fail2ban_maxretry: 5
security_fail2ban_ssh_maxretry: 3                # More strict for SSH
security_fail2ban_ssh_bantime: "24h"

# SSH Hardening
security_ssh_permit_root_login: "no"
security_ssh_password_authentication: "no"
security_ssh_max_auth_tries: 3
security_ssh_client_alive_interval: 300          # 5 minutes

# Allowed users (empty = allow all)
security_ssh_allowed_users:
  - deployer
  - admin

# Docker Security
security_docker_userns_remap: "default"
security_docker_no_new_privileges: true
security_docker_log_max_size: "10m"

# System Security
security_auto_updates: true
security_sysctl_ip_forward: "0"                  # Set '1' for VPN/router
security_sysctl_ignore_ping: "0"                 # Set '1' to ignore ping
```

## 📊 Port Configuration

### Default Allowed Ports

| Port | Protocol | Service | Access |
|------|----------|---------|--------|
| 2222 | TCP | SSH | Public (rate limited) |
| 80 | TCP | HTTP | Public |
| 443 | TCP | HTTPS | Public |
| 81 | TCP | NPM Dashboard | Public (configurable) |
| 3306 | TCP | MySQL | Localhost only* |
| 5432 | TCP | PostgreSQL | Localhost only* |
| 6379 | TCP | Redis | Localhost only* |

*Can be changed to allow external access via variables.

### Custom Ports

```yaml
# defaults/main.yml atau group_vars
security_custom_allowed_ports:
  - port: 8080
    proto: tcp
    comment: "Node.js app"
  - port: 9000
    proto: tcp
    comment: "Golang API"
  - port: 27017
    proto: tcp
    comment: "MongoDB"
```

## 🔐 Fail2ban Jails

### Active Jails

1. **sshd**
   - Monitors: `/var/log/auth.log`
   - Max retries: 3
   - Ban time: 24 hours
   - Aggressive mode

2. **nginx-http-auth**
   - Monitors: `/var/log/nginx/error.log`
   - Max retries: 10
   - Ban time: 1 hour

3. **nginx-badbots**
   - Blocks known malicious bots
   - Max retries: 2
   - Detects: Nikto, sqlmap, Metasploit, etc.

4. **nginx-noproxy**
   - Blocks proxy attempts
   - Max retries: 2

5. **nginx-limit-req**
   - DDoS protection
   - Max retries: 10 in 60s
   - Ban time: 10 minutes

### Check Jail Status

```bash
# All jails
sudo fail2ban-client status

# Specific jail
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-http-auth

# Banned IPs
sudo fail2ban-client get sshd banip

# Unban IP
sudo fail2ban-client set sshd unbanip 1.2.3.4
```

## 🔒 SSH Security

### Strong Cryptography

**Ciphers:**
- chacha20-poly1305@openssh.com
- aes256-gcm@openssh.com
- aes128-gcm@openssh.com
- aes256-ctr, aes192-ctr, aes128-ctr

**MACs:**
- hmac-sha2-512-etm@openssh.com
- hmac-sha2-256-etm@openssh.com
- hmac-sha2-512, hmac-sha2-256

**Key Exchange:**
- curve25519-sha256
- diffie-hellman-group16-sha512
- diffie-hellman-group18-sha512

### SSH Configuration

```ini
# /etc/ssh/sshd_config (applied automatically)
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
LogLevel VERBOSE
```

### Test SSH Config

```bash
# Test configuration syntax
sudo sshd -t

# View effective configuration
sudo sshd -T

# Test connection (from local machine)
ssh -vvv -p 2222 deployer@server-ip
```

## 🐳 Docker Security

### Features

1. **User Namespace Remapping**
   - Isolates container UIDs from host UIDs
   - Container root (0) → host user (100000)
   - Prevents privilege escalation

2. **Seccomp Profile**
   - Restricts system calls
   - Blocks dangerous operations
   - Custom profile: `/etc/docker/seccomp/default.json`

3. **AppArmor Profile**
   - Mandatory Access Control
   - Restricts file system access
   - Profile: `/etc/apparmor.d/docker-default`

4. **No New Privileges**
   - Prevents setuid binaries
   - Blocks privilege escalation in containers

5. **Log Rotation**
   - Max size: 10MB per file
   - Keep 3 files
   - Automatic cleanup

### Check Docker Security

```bash
# Check namespace remapping
docker info | grep -i "user"

# View running containers with security options
docker inspect <container> | grep -A 20 "SecurityOpt"

# Check seccomp profile
docker inspect <container> | grep -i "seccomp"

# Check AppArmor
docker inspect <container> | grep -i "apparmor"
```

## 🖥️ System Security

### Kernel Parameters

```ini
# /etc/sysctl.d/99-security.conf
net.ipv4.tcp_syncookies = 1              # SYN flood protection
net.ipv4.conf.all.accept_redirects = 0   # Ignore ICMP redirects
net.ipv4.conf.all.send_redirects = 0     # Don't send redirects
net.ipv4.conf.all.rp_filter = 1          # Reverse path filtering
net.ipv4.conf.all.log_martians = 1       # Log impossible packets
kernel.dmesg_restrict = 1                 # Restrict kernel logs
kernel.kptr_restrict = 2                  # Hide kernel pointers
fs.protected_hardlinks = 1                # Protect hardlinks
fs.protected_symlinks = 1                 # Protect symlinks
```

### Automatic Security Updates

```bash
# Configuration
/etc/apt/apt.conf.d/50unattended-upgrades
/etc/apt/apt.conf.d/20auto-upgrades

# Check status
sudo systemctl status unattended-upgrades

# View log
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log

# Manual run
sudo unattended-upgrade -d
```

### Rootkit Detection (Optional)

```bash
# Enable in defaults/main.yml
security_enable_rkhunter: true

# Manual check
sudo rkhunter --check --skip-keypress
sudo chkrootkit
```

## 📈 Monitoring

### UFW Logs

```bash
# View firewall logs
sudo tail -f /var/log/ufw.log

# Check denied connections
sudo grep "BLOCK" /var/log/ufw.log

# Check status
sudo ufw status verbose
```

### Fail2ban Logs

```bash
# Main log
sudo tail -f /var/log/fail2ban.log

# Find bans
sudo grep "Ban" /var/log/fail2ban.log

# Find unbans
sudo grep "Unban" /var/log/fail2ban.log

# Statistics
sudo fail2ban-client status sshd
```

### SSH Logs

```bash
# Authentication attempts
sudo tail -f /var/log/auth.log

# Failed SSH logins
sudo grep "Failed password" /var/log/auth.log

# Successful SSH logins
sudo grep "Accepted" /var/log/auth.log
```

### Docker Audit (if enabled)

```bash
# Enable in defaults/main.yml
security_docker_enable_audit: true

# View audit logs
sudo ausearch -k docker

# Real-time monitoring
sudo aureport -k docker --start today
```

## 🔧 Troubleshooting

### Locked Out of SSH

**Problem:** Cannot connect after SSH hardening.

**Solution:**
1. Access server via console (VPS provider dashboard)
2. Check SSH service:
   ```bash
   sudo systemctl status sshd
   sudo sshd -t  # Test config
   ```
3. Restore backup:
   ```bash
   sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
   sudo systemctl restart sshd
   ```

### IP Banned by Fail2ban

**Problem:** Your IP was banned accidentally.

**Solution:**
```bash
# Check if banned
sudo fail2ban-client status sshd

# Unban your IP
sudo fail2ban-client set sshd unbanip YOUR_IP

# Whitelist your IP
sudo nano /etc/fail2ban/jail.local
# Add to [DEFAULT] section:
ignoreip = 127.0.0.1/8 ::1 YOUR_IP
sudo systemctl restart fail2ban
```

### UFW Blocking Legitimate Traffic

**Problem:** UFW blocking needed service.

**Solution:**
```bash
# Check current rules
sudo ufw status numbered

# Add rule
sudo ufw allow 8080/tcp comment "My app"

# Insert at position (before deny rules)
sudo ufw insert 1 allow from 192.168.1.100

# Delete rule
sudo ufw delete 5
```

### Docker Containers Not Starting

**Problem:** Containers fail after Docker security hardening.

**Solution:**
1. Check if userns-remap is the issue:
   ```bash
   sudo nano /etc/docker/daemon.json
   # Comment out "userns-remap" line
   sudo systemctl restart docker
   ```

2. Check seccomp profile:
   ```bash
   # Run without seccomp temporarily
   docker run --security-opt seccomp=unconfined image
   ```

3. View Docker logs:
   ```bash
   sudo journalctl -u docker -f
   ```

## 🎯 Best Practices

### 1. **Test Before Production**
```bash
# Dry run
make setup-dry-run

# Deploy to staging first
ansible-playbook playbooks/server-setup.yml -i inventory/staging.ini --tags security-hardening
```

### 2. **Whitelist Your IP**
```yaml
# group_vars/all/main.yml
security_whitelist_ips:
  - ip: "YOUR_OFFICE_IP"
    comment: "Office IP - never ban"
```

### 3. **Monitor Logs Regularly**
```bash
# Setup log monitoring script
cat > /usr/local/bin/security-check.sh << 'EOF'
#!/bin/bash
echo "=== UFW Blocks (last 10) ==="
tail -10 /var/log/ufw.log | grep "BLOCK"

echo -e "\n=== Fail2ban Bans (today) ==="
grep "$(date +%Y-%m-%d)" /var/log/fail2ban.log | grep "Ban"

echo -e "\n=== Failed SSH Logins (last 10) ==="
tail -20 /var/log/auth.log | grep "Failed password"

echo -e "\n=== Fail2ban Status ==="
fail2ban-client status sshd
EOF

chmod +x /usr/local/bin/security-check.sh

# Run daily
sudo security-check.sh
```

### 4. **Keep SSH Access Available**
```yaml
# ALWAYS keep at least one way to access server
security_ssh_password_authentication: "no"  # Use keys
# OR have console access via VPS provider

# Test before disconnecting
ssh -p 2222 -i ~/.ssh/key deployer@server
```

### 5. **Backup Before Changes**
```bash
# Automatic backup in role
/etc/ssh/sshd_config.backup
/etc/docker/daemon.json.backup (if exists)

# Manual backup
sudo cp /etc/ssh/sshd_config /root/sshd_config.backup.$(date +%F)
```

## 📊 Security Checklist

After deployment, verify:

- [ ] SSH accessible on custom port (2222)
- [ ] SSH key authentication working
- [ ] Password authentication disabled
- [ ] UFW enabled and configured
- [ ] Fail2ban running with active jails
- [ ] Docker containers still running
- [ ] Web applications accessible (HTTP/HTTPS)
- [ ] NPM dashboard accessible (port 81)
- [ ] Database connections working
- [ ] Auto-updates enabled
- [ ] Logs being generated

## 🔗 Related Documentation

- UFW: https://help.ubuntu.com/community/UFW
- Fail2ban: https://www.fail2ban.org/
- Docker Security: https://docs.docker.com/engine/security/
- SSH Hardening: https://www.ssh.com/academy/ssh/config
- CIS Benchmarks: https://www.cisecurity.org/cis-benchmarks/

## 📝 License

MIT

## 👤 Author

Created as part of server-infra-with-ansible project.
