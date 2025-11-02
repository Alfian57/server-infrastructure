# Security Hardening - Quick Start Guide

## 🚀 Quick Deploy

### 1. Full Security Hardening

```bash
# Deploy semua security features
make security

# Atau menggunakan ansible-playbook langsung
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --tags security-hardening
```

### 2. Specific Security Components

```bash
# UFW Firewall only
make security-ufw

# Fail2ban only
make security-fail2ban

# SSH hardening only
make security-ssh

# Docker security only
make security-docker

# System hardening only
make security-system
```

### 3. Check Security Status

```bash
# Via Makefile
make security-check

# Via SSH on server
ssh -p 2222 deployer@server-ip
sudo security-check
```

## ⚙️ Configuration

### Override Default Settings

Create `group_vars/all/security.yml`:

```yaml
---
# Custom security configuration

# SSH Port (must match ansible_port in inventory)
security_ssh_port: 2222

# Allow NPM dashboard from anywhere
security_allow_npm_dashboard: true

# Allow database external access (NOT RECOMMENDED in production)
security_allow_mysql_external: false
security_allow_postgres_external: false
security_allow_redis_external: false

# Fail2ban settings
security_fail2ban_ssh_maxretry: 3      # More strict
security_fail2ban_ssh_bantime: "24h"   # Longer ban

# Whitelist your office IP
security_whitelist_ips:
  - ip: "YOUR_OFFICE_IP"
    comment: "Office - never ban"

# Custom allowed ports
security_custom_allowed_ports:
  - port: 8080
    proto: tcp
    comment: "Custom app"
```

## 📊 Common Use Cases

### 1. Basic Security (Recommended)

```yaml
# group_vars/all/security.yml
---
security_ssh_port: 2222
security_allow_npm_dashboard: true
security_allow_mysql_external: false
security_allow_postgres_external: false
security_allow_redis_external: false
security_fail2ban_ssh_maxretry: 3
security_fail2ban_ssh_bantime: "24h"
```

Deploy:
```bash
make security
```

### 2. Paranoid Mode (Maximum Security)

```yaml
# group_vars/all/security.yml
---
security_ssh_port: 2222
security_allow_npm_dashboard: false        # Access via SSH tunnel only
security_allow_mysql_external: false
security_allow_postgres_external: false
security_allow_redis_external: false
security_fail2ban_ssh_maxretry: 2          # Only 2 attempts
security_fail2ban_ssh_bantime: "168h"      # 1 week ban
security_sysctl_ignore_ping: "1"           # Hide from ping
security_docker_enable_audit: true         # Full audit logging
security_enable_rkhunter: true             # Rootkit scanning
```

Deploy:
```bash
make security
```

### 3. Development Mode (More Lenient)

```yaml
# group_vars/all/security.yml
---
security_ssh_port: 22                      # Standard port
security_allow_npm_dashboard: true
security_allow_mysql_external: true        # Allow external DB access
security_allow_postgres_external: true
security_fail2ban_ssh_maxretry: 5          # More attempts allowed
security_fail2ban_ssh_bantime: "1h"        # Shorter ban
security_whitelist_ips:
  - ip: "YOUR_DEV_MACHINE_IP"
    comment: "Dev machine"
```

Deploy:
```bash
make security
```

## 🔍 Verification Steps

After deployment, verify security:

### 1. Check UFW

```bash
ssh -p 2222 deployer@server-ip
sudo ufw status verbose
```

Expected output:
```
Status: active
Logging: on (low)

To                         Action      From
--                         ------      ----
2222/tcp                   LIMIT       Anywhere
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
81/tcp                     ALLOW       Anywhere
```

### 2. Check Fail2ban

```bash
sudo fail2ban-client status
```

Expected output:
```
Status
|- Number of jail:      4
`- Jail list:   sshd, nginx-http-auth, nginx-badbots, nginx-noproxy
```

### 3. Check SSH Config

```bash
sudo sshd -t     # Test config syntax
sudo sshd -T     # View effective config
```

### 4. Test SSH Connection

From your local machine:
```bash
# Should work (key-based)
ssh -p 2222 -i ~/.ssh/server_key deployer@server-ip

# Should fail (password-based)
ssh -p 2222 deployer@server-ip
# Enter password... should be rejected
```

### 5. Run Security Check

```bash
ssh -p 2222 deployer@server-ip
sudo security-check
```

Expected output:
```
═══════════════════════════════════════════════════════
  Security Status Report
═══════════════════════════════════════════════════════

▶ UFW Firewall Status
─────────────────────────────────────────────────────
✓ UFW is active

▶ Fail2ban Status
─────────────────────────────────────────────────────
✓ Fail2ban is running

▶ SSH Security Configuration
─────────────────────────────────────────────────────
  ✓ Root login: disabled
  ✓ Password authentication: disabled
  ✓ Max auth tries: 3
  ✓ SSH port: 2222

Security Score: 6/6
Status: Excellent
```

## 🚨 Troubleshooting

### Problem: Locked Out of SSH

**Symptoms:** Cannot connect after security hardening.

**Solution:**

1. **Via VPS Console:**
   - Login via provider's web console
   - Restore SSH config:
     ```bash
     sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
     sudo systemctl restart sshd
     ```

2. **Via Recovery Mode:**
   - Boot into recovery mode
   - Edit `/etc/ssh/sshd_config`
   - Set `PasswordAuthentication yes` temporarily
   - Reboot

3. **Prevention:**
   - Always whitelist your IP before deploying:
     ```yaml
     security_whitelist_ips:
       - ip: "YOUR_IP"
         comment: "My IP - never ban"
     ```
   - Test SSH in a new terminal before closing current session

### Problem: IP Banned by Fail2ban

**Symptoms:** Connection refused after multiple failed attempts.

**Solution:**

1. **Via Console:**
   ```bash
   # Check if banned
   sudo fail2ban-client status sshd
   
   # Unban
   sudo fail2ban-client set sshd unbanip YOUR_IP
   ```

2. **Permanent Whitelist:**
   ```bash
   sudo nano /etc/fail2ban/jail.local
   # Add to [DEFAULT]:
   ignoreip = 127.0.0.1/8 ::1 YOUR_IP
   
   sudo systemctl restart fail2ban
   ```

### Problem: UFW Blocking Legitimate Traffic

**Symptoms:** Service not accessible after UFW setup.

**Solution:**

1. **Check current rules:**
   ```bash
   sudo ufw status numbered
   ```

2. **Add rule:**
   ```bash
   sudo ufw allow 8080/tcp comment "My service"
   ```

3. **Or temporarily disable:**
   ```bash
   sudo ufw disable
   # Fix issue
   sudo ufw enable
   ```

### Problem: Docker Containers Failing

**Symptoms:** Containers won't start after Docker security hardening.

**Solution:**

1. **Check daemon.json:**
   ```bash
   sudo cat /etc/docker/daemon.json
   ```

2. **Temporarily disable userns-remap:**
   ```bash
   sudo nano /etc/docker/daemon.json
   # Comment out "userns-remap" line
   sudo systemctl restart docker
   ```

3. **Check logs:**
   ```bash
   sudo journalctl -u docker -f
   ```

## 📝 Best Practices

1. **Always whitelist your management IP:**
   ```yaml
   security_whitelist_ips:
     - ip: "YOUR_IP"
       comment: "Management IP"
   ```

2. **Test in dry-run mode first:**
   ```bash
   make setup-dry-run
   ```

3. **Keep a backup SSH session open:**
   ```bash
   # Terminal 1: Current session
   ssh -p 2222 deployer@server-ip
   
   # Terminal 2: Deploy changes
   make security
   
   # Terminal 3: Test new connection
   ssh -p 2222 deployer@server-ip
   ```

4. **Monitor logs after deployment:**
   ```bash
   sudo tail -f /var/log/fail2ban.log
   sudo tail -f /var/log/ufw.log
   sudo tail -f /var/log/auth.log
   ```

5. **Run security check regularly:**
   ```bash
   sudo security-check
   ```

## 🎯 Next Steps

After security hardening:

1. **Test all services:**
   - Web applications (HTTP/HTTPS)
   - NPM dashboard (port 81)
   - Database connections
   - SSH access

2. **Set up monitoring:**
   - Consider adding monitoring role
   - Set up log aggregation
   - Configure alerts

3. **Regular maintenance:**
   - Review Fail2ban logs weekly
   - Check security-check output
   - Update security rules as needed

4. **Document your setup:**
   - Save your custom security.yml
   - Document whitelisted IPs
   - Keep inventory of custom ports

## 📚 Additional Resources

- **Main README:** `roles/security-hardening/README.md`
- **UFW Guide:** https://help.ubuntu.com/community/UFW
- **Fail2ban Wiki:** https://www.fail2ban.org/
- **SSH Best Practices:** https://www.ssh.com/academy/ssh/config
- **Docker Security:** https://docs.docker.com/engine/security/

---

**Need Help?**
- Review detailed README: `roles/security-hardening/README.md`
- Check logs: `/var/log/fail2ban.log`, `/var/log/ufw.log`
- Run diagnostics: `sudo security-check`
