# Cost Optimization Role

Comprehensive cost optimization role untuk menghemat resource, storage, dan biaya server dengan automated cleanup dan monitoring.

## 💰 Cost Savings

Role ini dapat menghemat:
- **Disk Space**: 20-40% dengan cleanup Docker, logs, dan packages
- **Memory**: 10-30% dengan resource limits
- **CPU**: Lebih efisien dengan proper limits
- **Server Costs**: Bisa downgrade instance jika resource usage turun

## ✨ Features

### 1. **Docker Cleanup** 🐳
- Remove unused images (dangling & old)
- Clean stopped containers
- Remove unused volumes
- Clean unused networks
- Clear build cache
- Automated daily/weekly cleanup

### 2. **Log Management** 📝
- Automatic log rotation
- Compress old logs
- Clean logs older than N days
- Journal cleanup (systemd logs)
- Application log rotation

### 3. **Package Cleanup** 📦
- Remove unused packages (apt autoremove)
- Clean APT cache
- Remove old kernel versions
- Clean thumbnail cache
- Clean temp files

### 4. **Resource Limits** 🎛️
- Set CPU limits per container
- Set memory limits per container
- Memory reservation (guaranteed minimum)
- Prevent resource exhaustion
- Apply limits per container type

### 5. **Disk Monitoring** 💾
- Real-time disk usage monitoring
- Alert at warning threshold (75%)
- Critical alerts at 90%
- Webhook notifications (Discord, Slack)
- Automated reports

### 6. **Scheduled Cleanup** ⏰
- Daily Docker cleanup
- Weekly full cleanup
- Monthly aggressive cleanup
- Automated via cron jobs
- Detailed cleanup logs

## 📋 Requirements

- Ansible 2.9+
- Ubuntu 20.04+ / Debian 10+
- Docker (optional, for Docker cleanup)
- Root/sudo access

## 🚀 Installation

### Via Playbook

```yaml
# playbooks/server-setup.yml
- role: cost-optimization
  tags: [optimization, cost-optimization]
```

### Via Makefile

```bash
# Full cost optimization
make cost-optimization

# Specific components
make cost-docker          # Docker cleanup only
make cost-logs            # Log cleanup only
make cost-packages        # Package cleanup only
make cost-resources       # Resource limits only
make cost-monitoring      # Disk monitoring only
make cost-scheduled       # Scheduled cleanup only
```

## ⚙️ Configuration

### Default Variables (`defaults/main.yml`)

```yaml
# Docker Cleanup
cost_docker_aggressive_cleanup: false      # Remove ALL unused images
cost_docker_cleanup_volumes: true          # Clean unused volumes
cost_docker_image_retention: "720h"        # 30 days
cost_docker_log_max_size: "10m"            # Per container

# Log Cleanup
cost_log_rotate_frequency: "daily"         # daily, weekly, monthly
cost_log_rotate_count: 7                   # Keep 7 rotations
cost_log_max_size: "50M"                   # Max before rotation
cost_journal_max_size: "500M"              # Journal limit

# Resource Limits
cost_app_container_cpu_limit: "1.0"        # 1 CPU core
cost_app_container_memory_limit: "512m"    # 512 MB
cost_db_container_memory_limit: "1g"       # 1 GB for databases

# Disk Monitoring
cost_disk_warning_threshold: 75            # Warning at 75%
cost_disk_critical_threshold: 90           # Critical at 90%
cost_disk_check_interval: 6                # Check every 6 hours

# Scheduled Cleanup
cost_enable_daily_cleanup: true
cost_cleanup_schedule: "02:00"             # 2 AM
cost_enable_weekly_cleanup: true
cost_weekly_cleanup_day: "0"               # Sunday
```

## 📊 Usage

### Manual Cleanup

```bash
# SSH to server
ssh -p 2222 deployer@server-ip

# Docker cleanup
sudo docker-cleanup

# Check disk usage
sudo disk-check

# Full resource report
sudo resource-report

# Apply resource limits
sudo apply-resource-limits

# View cleanup logs
tail -f /var/log/cleanup.log

# View disk monitoring logs
tail -f /var/log/disk-monitor.log
```

### Automated Cleanup

Cleanup runs automatically via cron:

**Daily** (02:00):
- Docker cleanup (unused images, containers, networks)

**Weekly** (Sunday 03:00):
- Full Docker cleanup
- APT autoremove & autoclean
- Journal cleanup

**Monthly** (1st of month, 04:00 - optional):
- Aggressive Docker cleanup (all unused resources)
- Deep log cleanup
- Temp files cleanup

### Check Cleanup History

```bash
sudo cleanup-summary
```

Output:
```
=== Cleanup Log Summary (Last 30 Days) ===
Total cleanup runs: 30
Last 5 cleanups:
  2025-11-01 02:00:00 - Cleanup started
  2025-10-31 02:00:00 - Cleanup started
  ...

Space reclaimed (estimated):
  Total reclaimed space: 2.5GB
```

## 🎯 Resource Limits

### Container Types

**Application Containers** (Laravel apps):
- CPU: 1.0 core
- Memory: 512 MB
- Reservation: 256 MB

**Database Containers** (MySQL, PostgreSQL, Redis):
- CPU: 2.0 cores
- Memory: 1 GB
- Reservation: 512 MB

**Infrastructure Containers** (NPM, Autoheal):
- CPU: 0.5 core
- Memory: 256 MB
- Reservation: 128 MB

### Apply Limits

```bash
# Apply to all running containers
sudo apply-resource-limits

# View current limits
docker inspect container_name | grep -A 5 "Memory"
docker inspect container_name | grep -A 5 "NanoCpus"

# Check resource usage
docker stats
```

### Custom Limits

Edit `group_vars/all/cost.yml`:

```yaml
---
# Custom resource limits for your apps

cost_app_container_cpu_limit: "2.0"        # 2 cores for apps
cost_app_container_memory_limit: "1g"      # 1 GB for apps

cost_db_container_memory_limit: "2g"       # 2 GB for databases
```

## 🔍 Monitoring

### Disk Check

```bash
sudo disk-check
```

Output:
```
═══════════════════════════════════════════════════════
  Disk Space Check
═══════════════════════════════════════════════════════

Disk Usage Summary:
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        50G   30G   18G  63% /

✓ OK: Disk usage is at 63%
```

### Resource Report

```bash
sudo resource-report
```

Shows:
- Disk usage by filesystem
- Memory usage
- CPU information
- Top processes (CPU & Memory)
- Docker resource usage
- Container stats
- Top 10 largest directories
- Log directory sizes
- Optimization recommendations

## 🔔 Webhook Alerts

### Discord Integration

```yaml
# group_vars/all/cost.yml
cost_enable_webhook_alerts: true
cost_webhook_type: "discord"
cost_webhook_url: "https://discord.com/api/webhooks/YOUR_WEBHOOK"
```

### Slack Integration

```yaml
cost_enable_webhook_alerts: true
cost_webhook_type: "slack"
cost_webhook_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### Alert Levels

- **WARNING** (75% disk usage): Yellow alert with recommendations
- **CRITICAL** (90% disk usage): Red alert with urgent actions

Webhook sends:
- Server hostname
- Disk usage percentage
- Disk total/used/available
- Recommended actions
- Timestamp

## 📈 Expected Results

### Before Optimization

```
Disk Usage: 85%
Docker:
  Images: 15 (5.2 GB)
  Containers: 20 (2 GB)
  Volumes: 10 (1.5 GB)
  Build Cache: 3 GB
Memory Usage: 75%
```

### After Optimization

```
Disk Usage: 62%  ⬇️ -23%
Docker:
  Images: 8 (2.1 GB)      ⬇️ -60% space
  Containers: 8 (800 MB)  ⬇️ -60% space
  Volumes: 5 (500 MB)     ⬇️ -67% space
  Build Cache: 200 MB     ⬇️ -93% space
Memory Usage: 55%         ⬇️ -20%

Total Space Freed: ~8 GB
```

## 🔧 Troubleshooting

### Cleanup Not Running

**Check cron jobs:**
```bash
crontab -l | grep cleanup
```

**Check logs:**
```bash
tail -f /var/log/cleanup.log
grep -i error /var/log/cleanup.log
```

### Docker Cleanup Too Aggressive

If accidentally removing needed images:

```yaml
# Disable aggressive cleanup
cost_docker_aggressive_cleanup: false

# Increase retention period
cost_docker_image_retention: "2160h"  # 90 days
```

### Resource Limits Too Strict

If containers are OOMKilled:

```bash
# Check container logs
docker logs container_name

# Increase limits
# Edit group_vars/all/cost.yml
cost_app_container_memory_limit: "1g"  # Increase to 1GB

# Reapply limits
sudo apply-resource-limits
```

### Disk Still Full

**Find largest directories:**
```bash
sudo du -h / | sort -rh | head -20
```

**Check specific areas:**
```bash
# Docker
sudo du -sh /var/lib/docker

# Logs
sudo du -sh /var/log/*

# APT cache
sudo du -sh /var/cache/apt

# Journal
sudo du -sh /var/log/journal
```

**Manual cleanup:**
```bash
# Docker - aggressive
docker system prune -a -f --volumes

# Logs
find /var/log -type f -name "*.gz" -mtime +7 -delete
journalctl --vacuum-time=3days

# APT
apt-get clean
apt-get autoremove --purge -y
```

## 🎯 Best Practices

### 1. **Test Before Production**

```bash
# Dry run first
make setup-dry-run

# Check what will be removed
docker system df
docker images
docker volume ls
```

### 2. **Monitor After Deployment**

```bash
# Check cleanup logs
tail -f /var/log/cleanup.log

# Check disk usage
watch -n 60 disk-check

# Monitor containers
docker stats
```

### 3. **Adjust Schedules**

For low-traffic sites:
```yaml
cost_cleanup_schedule: "03:00"     # Early morning
cost_weekly_cleanup_day: "0"       # Sunday
```

For high-traffic sites:
```yaml
cost_cleanup_schedule: "04:00"     # Later morning
cost_weekly_cleanup_day: "1"       # Monday (less traffic)
```

### 4. **Set Appropriate Limits**

**Small VPS** (2 GB RAM):
```yaml
cost_app_container_memory_limit: "256m"
cost_db_container_memory_limit: "512m"
```

**Medium VPS** (4 GB RAM):
```yaml
cost_app_container_memory_limit: "512m"
cost_db_container_memory_limit: "1g"
```

**Large VPS** (8+ GB RAM):
```yaml
cost_app_container_memory_limit: "1g"
cost_db_container_memory_limit: "2g"
```

### 5. **Enable Webhooks**

Get notified before disk fills up:
```yaml
cost_enable_webhook_alerts: true
cost_webhook_url: "YOUR_WEBHOOK_URL"
cost_disk_warning_threshold: 70    # Alert earlier
```

## 📊 Monitoring Dashboard

Create simple monitoring dashboard:

```bash
# Add to ~/.bashrc
alias cost-status='echo "=== Cost Optimization Status ==="; disk-check; echo ""; resource-report | head -30; echo ""; cleanup-summary | tail -10'

# Run
cost-status
```

## 🆘 Emergency Cleanup

If disk is 95%+ full:

```bash
# 1. Immediate Docker cleanup
docker system prune -a -f --volumes

# 2. Clean logs
find /var/log -type f -name "*.log" -size +100M -delete
journalctl --vacuum-time=1day

# 3. Clean APT
apt-get clean
apt-get autoremove --purge -y

# 4. Find largest files
find / -xdev -type f -size +100M -exec ls -lh {} \; 2>/dev/null

# 5. Check disk again
df -h
```

## 📝 Customization Examples

### Example 1: Conservative (Keep More Data)

```yaml
cost_docker_aggressive_cleanup: false
cost_docker_image_retention: "2160h"      # 90 days
cost_docker_cleanup_volumes: false        # Keep volumes
cost_log_rotate_count: 14                 # Keep 14 rotations
cost_journal_retention: "14days"
```

### Example 2: Aggressive (Maximum Savings)

```yaml
cost_docker_aggressive_cleanup: true
cost_docker_image_retention: "168h"       # 7 days
cost_docker_cleanup_volumes: true
cost_log_rotate_count: 3                  # Keep 3 rotations
cost_journal_retention: "3days"
cost_enable_monthly_cleanup: true
```

### Example 3: Production (Balanced)

```yaml
cost_docker_aggressive_cleanup: false
cost_docker_image_retention: "720h"       # 30 days
cost_docker_cleanup_volumes: true
cost_log_rotate_count: 7
cost_journal_retention: "7days"
cost_enable_webhook_alerts: true
cost_disk_warning_threshold: 70           # Alert early
```

## 📚 Related Documentation

- **Docker Pruning:** https://docs.docker.com/config/pruning/
- **Logrotate:** https://linux.die.net/man/8/logrotate
- **Journalctl:** https://www.freedesktop.org/software/systemd/man/journalctl.html
- **Docker Resource Constraints:** https://docs.docker.com/config/containers/resource_constraints/

## 🔗 Integration

Works well with:
- **security-hardening**: Secure + optimized infrastructure
- **monitoring** (future): Track cost savings over time
- **backup** (future): Optimize backup storage

## 📝 License

MIT

## 👤 Author

Created as part of server-infra-with-ansible project.

---

**Questions?**
- Check logs: `/var/log/cleanup.log`, `/var/log/disk-monitor.log`
- Run reports: `resource-report`, `cleanup-summary`
- Check disk: `disk-check`
