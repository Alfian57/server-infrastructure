# Cost Optimization Quick Start

Get started with cost optimization in 5 minutes!

## 🚀 Quick Setup

### 1. Deploy Cost Optimization

```bash
# Full deployment
make cost-optimization

# Or specific components
make cost-docker        # Docker cleanup only
make cost-logs          # Log cleanup only
```

### 2. Verify Installation

```bash
# SSH to server
ssh -p 2222 deployer@your-server

# Check scripts
which docker-cleanup disk-check resource-report

# Run disk check
sudo disk-check
```

## 📊 Common Tasks

### Check Disk Usage

```bash
sudo disk-check
```

### Run Manual Cleanup

```bash
# Docker cleanup
sudo docker-cleanup

# Full report
sudo resource-report
```

### View Cleanup History

```bash
sudo cleanup-summary
```

## ⚙️ Quick Configuration

### Enable Webhooks (Discord/Slack)

Create `group_vars/all/cost.yml`:

```yaml
---
cost_enable_webhook_alerts: true
cost_webhook_type: "discord"  # or "slack"
cost_webhook_url: "YOUR_WEBHOOK_URL"
```

### Adjust Resource Limits

```yaml
# For larger apps
cost_app_container_memory_limit: "1g"
cost_db_container_memory_limit: "2g"
```

### Change Cleanup Schedule

```yaml
cost_cleanup_schedule: "03:00"        # 3 AM instead of 2 AM
cost_weekly_cleanup_day: "0"          # 0=Sunday, 1=Monday, etc.
```

## 🎯 Common Scenarios

### Scenario 1: Disk Almost Full (90%+)

```bash
# Emergency cleanup
ssh server
sudo docker-cleanup
sudo journalctl --vacuum-time=3days
sudo apt-get clean && sudo apt-get autoremove -y

# Check again
sudo disk-check
```

### Scenario 2: Too Many Docker Images

```yaml
# Enable aggressive cleanup
cost_docker_aggressive_cleanup: true
cost_docker_image_retention: "168h"  # Keep only 7 days

# Redeploy
make cost-docker
```

### Scenario 3: Containers Using Too Much Memory

```bash
# Check current usage
docker stats

# Reduce limits
# Edit group_vars/all/cost.yml
cost_app_container_memory_limit: "256m"

# Redeploy and apply
make cost-resources
ssh server
sudo apply-resource-limits
```

### Scenario 4: Logs Growing Too Fast

```yaml
# Rotate more frequently
cost_log_rotate_frequency: "daily"
cost_log_max_size: "10M"           # Smaller size
cost_log_rotate_count: 3           # Keep fewer rotations

# Redeploy
make cost-logs
```

## 🔍 Quick Checks

### Check Scheduled Jobs

```bash
ssh server
crontab -l | grep -E "cleanup|disk-check"
```

### Check Logs

```bash
# Cleanup log
tail -f /var/log/cleanup.log

# Disk monitor log
tail -f /var/log/disk-monitor.log
```

### Check Docker Status

```bash
# Disk usage
docker system df

# Container stats
docker stats --no-stream

# Images
docker images
```

## 💡 Pro Tips

### 1. **Monitor First Week**

```bash
# Watch disk usage
watch -n 300 disk-check  # Every 5 minutes

# Check logs daily
tail -100 /var/log/cleanup.log
```

### 2. **Adjust Gradually**

Start conservative:
```yaml
cost_docker_aggressive_cleanup: false
cost_docker_image_retention: "720h"  # 30 days
```

After 1 week, if stable:
```yaml
cost_docker_aggressive_cleanup: true
cost_docker_image_retention: "360h"  # 15 days
```

### 3. **Set Up Alerts Early**

```yaml
cost_enable_webhook_alerts: true
cost_disk_warning_threshold: 70     # Alert at 70%
```

Get notified before problems occur!

### 4. **Create Shortcuts**

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias cost-check='disk-check && echo "" && docker system df'
alias cost-clean='docker-cleanup && echo "Cleanup completed!"'
alias cost-report='resource-report'
alias cost-history='cleanup-summary'
```

Then just run:
```bash
cost-check    # Quick status
cost-clean    # Manual cleanup
cost-report   # Full report
```

## 🎛️ Configuration Presets

### Small VPS (2 GB RAM, 20 GB Disk)

```yaml
# group_vars/all/cost.yml
cost_docker_aggressive_cleanup: true
cost_docker_image_retention: "168h"
cost_app_container_memory_limit: "256m"
cost_db_container_memory_limit: "512m"
cost_log_rotate_count: 3
cost_disk_warning_threshold: 70
cost_enable_webhook_alerts: true
```

### Medium VPS (4 GB RAM, 50 GB Disk)

```yaml
cost_docker_aggressive_cleanup: false
cost_docker_image_retention: "360h"
cost_app_container_memory_limit: "512m"
cost_db_container_memory_limit: "1g"
cost_log_rotate_count: 7
cost_disk_warning_threshold: 75
```

### Large VPS (8+ GB RAM, 100+ GB Disk)

```yaml
cost_docker_aggressive_cleanup: false
cost_docker_image_retention: "720h"
cost_app_container_memory_limit: "1g"
cost_db_container_memory_limit: "2g"
cost_log_rotate_count: 14
cost_disk_warning_threshold: 80
```

## 🔄 Maintenance Workflow

### Weekly Check (5 minutes)

```bash
# 1. SSH to server
ssh server

# 2. Check disk
sudo disk-check

# 3. Check cleanup history
sudo cleanup-summary

# 4. Check resource usage
docker stats --no-stream

# 5. Check logs (optional)
tail -50 /var/log/cleanup.log
```

### Monthly Review (15 minutes)

```bash
# 1. Full report
sudo resource-report > ~/report-$(date +%Y-%m).txt

# 2. Review largest directories
sudo du -h /var | sort -rh | head -20

# 3. Check Docker
docker system df

# 4. Review configuration
# Are limits appropriate?
# Need to adjust schedules?
# Disk trends?

# 5. Adjust if needed
# Edit group_vars/all/cost.yml
# make cost-optimization
```

## 🆘 Troubleshooting

### Cleanup Not Working?

```bash
# Check cron
crontab -l

# Check script permissions
ls -l /usr/local/bin/docker-cleanup

# Run manually with debug
sudo bash -x /usr/local/bin/docker-cleanup
```

### Webhooks Not Sending?

```bash
# Test webhook manually
curl -X POST "YOUR_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"content":"Test from server"}'

# Check disk-check script
sudo disk-check
grep -i webhook /var/log/disk-monitor.log
```

### Container OOMKilled?

```bash
# Check logs
docker logs container_name 2>&1 | grep -i "killed"

# Increase memory
# Edit group_vars/all/cost.yml
cost_app_container_memory_limit: "1g"

# Redeploy
make cost-resources
sudo apply-resource-limits
```

## 📋 Cheat Sheet

```bash
# Status
sudo disk-check              # Disk usage
sudo resource-report         # Full report
sudo cleanup-summary         # Cleanup history
docker stats                 # Container resources
docker system df             # Docker disk usage

# Manual Actions
sudo docker-cleanup          # Docker cleanup
sudo apply-resource-limits   # Apply container limits
docker system prune -a -f    # Aggressive Docker cleanup
journalctl --vacuum-time=3d  # Clean journal

# Logs
tail -f /var/log/cleanup.log       # Cleanup logs
tail -f /var/log/disk-monitor.log  # Disk monitor logs
journalctl -u cron -f              # Cron logs

# Configuration
vi group_vars/all/cost.yml   # Edit config
make cost-optimization       # Redeploy

# Cron Jobs
crontab -l                   # List scheduled tasks
crontab -e                   # Edit scheduled tasks
```

## 🎯 Next Steps

1. **Monitor** disk usage for 1 week
2. **Adjust** configuration based on patterns
3. **Set up** webhook alerts if not done
4. **Review** cleanup logs weekly
5. **Optimize** further based on your needs

## 📚 More Info

- Full documentation: [README.md](README.md)
- Variables reference: [defaults/main.yml](defaults/main.yml)
- Task details: [tasks/](tasks/)

---

**Quick Help:**
```bash
# Get help
sudo disk-check --help
sudo docker-cleanup --help
sudo resource-report --help

# View configuration
cat group_vars/all/cost.yml

# Check role status
make check
```
