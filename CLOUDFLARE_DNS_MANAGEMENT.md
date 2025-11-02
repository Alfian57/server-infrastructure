# Cloudflare DNS Management

Automasi untuk mengelola Cloudflare DNS records yang mengarah ke VPS. Script dijalankan **di server** untuk keamanan yang lebih baik.

## 📋 Overview

Script ini mengotomasi pembuatan dan update DNS records untuk domain `alfian-gading.site`:

### DNS Records yang Dikelola

```
✓ alfian-gading.site                    → VPS_IP (Proxied)
✓ materi-ku.alfian-gading.site          → VPS_IP (Proxied)
✓ panca-trivia.alfian-gading.site       → VPS_IP (Proxied)
✓ ruang-istirahat.alfian-gading.site    → VPS_IP (Proxied)
✓ tech-talk.alfian-gading.site          → VPS_IP (Proxied)
✓ *.alfian-gading.site                  → VPS_IP (DNS Only)
```

**Total: 6 DNS A Records**

### Key Features

- ✅ Dijalankan di server (lebih aman)
- ✅ Auto-detect VPS IP dari inventory
- ✅ Support Proxied (Orange Cloud) dan DNS Only (Gray Cloud)
- ✅ Support wildcard subdomain
- ✅ One-time setup (tidak perlu dijalankan setiap deploy)
- ✅ Idempotent (aman dijalankan berulang kali)
- ✅ Colorful Python script dengan error handling

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│ Development Machine (localhost)                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  1. Run: make setup                             │
│     or: make setup-tags TAGS=cloudflare-dns-setup│
│                                                 │
└────────────────┬────────────────────────────────┘
                 │ Ansible Playbook
                 ↓
┌─────────────────────────────────────────────────┐
│ VPS Server                                      │
├─────────────────────────────────────────────────┤
│                                                 │
│  2. cloudflare-dns-setup role:                  │
│     • Install python3-cloudflare                │
│     • Setup Cloudflare API credentials          │
│     • Copy DNS records configuration            │
│     • Install update-cloudflare-dns script      │
│                                                 │
│  3. Files in /home/deployer/:                   │
│     • .config/cloudflare/                       │
│       - cloudflare.ini (API token)              │
│       - dns-records.yml (config)                │
│     • .local/bin/update-cloudflare-dns          │
│                                                 │
│  4. SSH to server and run:                      │
│     $ update-cloudflare-dns                     │
│                                                 │
└────────────────┬────────────────────────────────┘
                 │ Cloudflare API
                 ↓
         ┌──────────────────────┐
         │   Cloudflare Zone    │
         │  alfian-gading.site  │
         │                      │
         │  6 A Records         │
         │  5 Proxied           │
         │  1 DNS Only          │
         └──────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

1. **Cloudflare API Token**

Cara membuat API Token:

```
1. Login ke Cloudflare Dashboard
2. Go to: Profile → API Tokens → Create Token
3. Use template: "Edit zone DNS"
   
   OR create custom token with permissions:
   - Zone → DNS → Edit
   - Zone → Zone → Read
   
4. Zone Resources:
   - Include → Specific zone → alfian-gading.site
   
5. Click "Continue to summary"
6. Click "Create Token"
7. Copy token (starts with: xxx...)
```

2. **Add Token to Vault**

```bash
# Edit vault
ansible-vault edit group_vars/all/vault.yml

# Add this line:
vault_cloudflare_api_token: "your_api_token_here"
```

### Step 1: Install Cloudflare DNS Setup

```bash
# Option A: Full server setup (includes Cloudflare DNS)
make setup

# Option B: Cloudflare DNS only
make setup-tags TAGS=cloudflare-dns-setup
```

This will:
- Install Python Cloudflare library
- Setup API credentials from vault
- Copy DNS records configuration
- Install `update-cloudflare-dns` script

### Step 2: Update DNS Records (One-Time)

```bash
# Option A: Via Makefile (Recommended)
make update-cloudflare-dns-interactive

# Option B: Manual SSH
ssh -p 2222 deployer@YOUR_SERVER_IP
update-cloudflare-dns
```

### Step 3: Verify

Check DNS in Cloudflare Dashboard:
```
https://dash.cloudflare.com/ → alfian-gading.site → DNS → Records
```

Or via command line:
```bash
dig alfian-gading.site
dig materi-ku.alfian-gading.site
```

## 📂 File Structure

```
server-infra-with-ansible/
├── playbooks/
│   └── server-setup.yml              # Includes cloudflare-dns-setup
├── roles/
│   └── cloudflare-dns-setup/
│       ├── tasks/
│       │   └── main.yml              # Install & configure
│       ├── templates/
│       │   ├── cloudflare.ini.j2     # API credentials
│       │   └── update-cloudflare-dns.py.j2  # Python script
│       ├── defaults/
│       │   └── main.yml              # DNS records config
│       └── README.md
└── Makefile                          # Shortcuts

Server (/home/deployer/):
├── .config/cloudflare/
│   ├── cloudflare.ini                # API token (0600)
│   └── dns-records.yml               # DNS config (0644)
└── .local/bin/
    └── update-cloudflare-dns         # Python script (0755)
```

## ⚙️ Configuration

### DNS Records

Default configuration in `roles/cloudflare-dns-setup/defaults/main.yml`:

```yaml
cloudflare_domain: "alfian-gading.site"

cloudflare_dns_records:
  # Root domain (proxied)
  - name: "@"
    type: "A"
    proxied: true
    comment: "Root domain - Main website"
  
  # Applications (proxied for SSL + DDoS protection)
  - name: "materi-ku"
    type: "A"
    proxied: true
    comment: "Materi-ku application"
  
  - name: "panca-trivia"
    type: "A"
    proxied: true
    comment: "Panca-trivia application"
  
  - name: "ruang-istirahat"
    type: "A"
    proxied: true
    comment: "Ruang-istirahat application"
  
  - name: "tech-talk"
    type: "A"
    proxied: true
    comment: "Tech-talk application"
  
  # Wildcard (DNS only - free plan limitation)
  - name: "*"
    type: "A"
    proxied: false
    comment: "Wildcard for development subdomains"
```

### Add New Subdomain

```bash
# Edit defaults
vim roles/cloudflare-dns-setup/defaults/main.yml

# Add new record:
cloudflare_dns_records:
  # ... existing records ...
  
  - name: "new-app"
    type: "A"
    proxied: true
    comment: "New application"
```

Re-run setup:

```bash
# Update role
make setup-tags TAGS=cloudflare-dns-setup

# Update DNS
make update-cloudflare-dns-interactive
```

## 🔐 Proxied vs DNS Only

### Proxied (Orange Cloud) ☁️

**Advantages:**
- ✅ Free SSL/TLS certificate from Cloudflare
- ✅ DDoS protection & WAF
- ✅ CDN caching (faster for global users)
- ✅ Hide real server IP
- ✅ Analytics & insights
- ✅ Always Online™ (cached version when server down)

**Use for:**
- Production applications
- Public-facing websites
- APIs (if caching configured properly)

**Current setup:** Root domain + all app subdomains

### DNS Only (Gray Cloud) ☁️

**Advantages:**
- ✅ Direct connection to server (lower latency)
- ✅ Works with wildcard on free plan
- ✅ Full control over SSL (use your own cert)

**Disadvantages:**
- ❌ No Cloudflare protection
- ❌ Real server IP exposed
- ❌ No free SSL from Cloudflare

**Use for:**
- Development/testing subdomains
- Internal services
- Wildcard records (free plan limitation)

**Current setup:** `*.alfian-gading.site`

## 📖 Usage Guide

### Script Execution Flow

```python
1. Check Requirements
   ✓ DNS records configuration exists
   ✓ Cloudflare credentials file exists

2. Get VPS IP
   ✓ Read from /home/deployer/ansible-workspace/hosts.ini

3. Load DNS Records
   ✓ Parse dns-records.yml

4. Connect to Cloudflare
   ✓ Initialize API client with token
   ✓ Get Zone ID for domain

5. Fetch Existing Records
   ✓ Get current A records from Cloudflare

6. Show Preview
   ✓ Display what will be created/updated

7. Confirm
   ✓ Ask user for confirmation

8. Update Records
   ✓ Create new records
   ✓ Update existing records (if IP or proxy status changed)

9. Summary
   ✓ Show success/fail counts
   ✓ Display propagation note
```

### Example Output

```
╔═══════════════════════════════════════════════════════════════╗
║  Update Cloudflare DNS Records                          ║
╚═══════════════════════════════════════════════════════════════╝

▶ Checking requirements...
✓ DNS records configuration found
✓ Cloudflare credentials found

▶ Getting VPS IP from inventory...
✓ VPS IP: 103.XXX.XXX.XXX

▶ Loading DNS records configuration...
✓ Loaded 6 DNS records to configure

▶ Connecting to Cloudflare API...
✓ Connected to Cloudflare API

▶ Getting Zone ID for alfian-gading.site...
✓ Zone ID: abc123def456ghi789

▶ Fetching existing DNS records...
✓ Found 0 existing A records

DNS Records to configure:
  • alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
  • materi-ku.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
  • panca-trivia.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
  • ruang-istirahat.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
  • tech-talk.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
  • *.alfian-gading.site → 103.XXX.XXX.XXX (DNS Only)

Continue? [y/N] y

▶ Updating DNS records...

✓ Created alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
✓ Created materi-ku.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
✓ Created panca-trivia.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
✓ Created ruang-istirahat.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
✓ Created tech-talk.alfian-gading.site → 103.XXX.XXX.XXX (Proxied)
✓ Created *.alfian-gading.site → 103.XXX.XXX.XXX (DNS Only)

╔═══════════════════════════════════════════════════════════════╗
║  Summary                                                      ║
╠═══════════════════════════════════════════════════════════════╣
║  Domain: alfian-gading.site                                   ║
║  VPS IP: 103.XXX.XXX.XXX                                      ║
║  Records processed: 6                                         ║
║  Successful: 6                                                ║
╚═══════════════════════════════════════════════════════════════╝

✓ All DNS records updated successfully!

Note: DNS propagation may take a few minutes.
Verify records at: https://dash.cloudflare.com/
```

## 🛠️ Makefile Commands

```bash
# Cloudflare DNS Management
make setup-cloudflare-dns              # Info about setup
make update-cloudflare-dns             # Show SSH command
make update-cloudflare-dns-interactive # Auto SSH + run script
```

## 🔧 Advanced Usage

### Change VPS IP

If you migrate to new server:

```bash
# 1. Update inventory with new IP
vim inventory/hosts.ini

# 2. Re-run server setup
make setup

# 3. Update DNS (will detect new IP automatically)
make update-cloudflare-dns-interactive
```

Script will detect IP change and update all records.

### Toggle Proxy Status

Change from Proxied to DNS Only (or vice versa):

```bash
# 1. Edit config
vim roles/cloudflare-dns-setup/defaults/main.yml

# Change proxied value:
- name: "app-name"
  proxied: false  # Change to true or false

# 2. Re-run setup
make setup-tags TAGS=cloudflare-dns-setup

# 3. Update DNS
make update-cloudflare-dns-interactive
```

### Remove Subdomain

```bash
# 1. Remove from config
vim roles/cloudflare-dns-setup/defaults/main.yml

# Delete the record entry

# 2. Manually delete in Cloudflare Dashboard
# Or use Cloudflare API/Dashboard
```

Script doesn't delete records (safety feature).

## 🐛 Troubleshooting

### API Token Invalid

**Error:**
```
✗ Failed to initialize Cloudflare client: ...
```

**Solution:**
```bash
# 1. Verify token in vault
ansible-vault view group_vars/all/vault.yml --ask-vault-pass

# 2. Check token in Cloudflare Dashboard
# Profile → API Tokens → Verify status

# 3. Re-generate if expired/invalid

# 4. Update vault
ansible-vault edit group_vars/all/vault.yml

# 5. Re-run setup
make setup-tags TAGS=cloudflare-dns-setup
```

### Domain Not Found

**Error:**
```
✗ Domain not found in Cloudflare: alfian-gading.site
```

**Solution:**
1. Add domain to Cloudflare account
2. Go to Cloudflare Dashboard → Add a Site
3. Enter: `alfian-gading.site`
4. Update nameservers at domain registrar
5. Wait for domain activation (can take 24-48 hours)

### Python Module Not Found

**Error:**
```
ModuleNotFoundError: No module named 'CloudFlare'
```

**Solution:**
```bash
# SSH to server
ssh -p 2222 deployer@YOUR_SERVER_IP

# Install manually
sudo pip3 install cloudflare

# Or re-run Ansible role
make setup-tags TAGS=cloudflare-dns-setup
```

### Permission Denied

**Error:**
```
Permission denied: /home/deployer/.config/cloudflare/cloudflare.ini
```

**Solution:**
```bash
# Fix permissions
ssh -p 2222 deployer@YOUR_SERVER_IP
chmod 600 ~/.config/cloudflare/cloudflare.ini
chmod 755 ~/.local/bin/update-cloudflare-dns
```

### DNS Not Resolving

After updating DNS:

```bash
# Check with dig
dig alfian-gading.site
dig materi-ku.alfian-gading.site

# Check with nslookup (use Cloudflare DNS)
nslookup alfian-gading.site 1.1.1.1

# Check propagation
https://www.whatsmydns.net/
```

**Note:** DNS propagation can take:
- Cloudflare: Instant to 1 minute
- Global: Up to 24-48 hours (rare)

## 🔐 Security Best Practices

### API Token Permissions

**Minimum required permissions:**
- Zone → DNS → Edit
- Zone → Zone → Read

**Scope:**
- Specific zone: `alfian-gading.site`

**Do NOT use:**
- Global API Key (too powerful)
- Tokens with Account-level permissions

### File Security

```bash
# API credentials (sensitive)
/home/deployer/.config/cloudflare/cloudflare.ini  → 0600

# DNS config (not sensitive)
/home/deployer/.config/cloudflare/dns-records.yml → 0644

# Script (executable)
/home/deployer/.local/bin/update-cloudflare-dns   → 0755
```

### Vault Security

- ✅ API token stored in encrypted Ansible vault
- ✅ Vault password in `.vault_pass` (gitignored)
- ✅ Token only transmitted to server via Ansible (encrypted)
- ✅ Token file on server has 0600 permissions

## 📊 Monitoring & Verification

### Verify in Cloudflare Dashboard

```
1. Login: https://dash.cloudflare.com/
2. Select: alfian-gading.site
3. Go to: DNS → Records
4. Verify: 6 A records exist
5. Check: Proxy status (orange/gray cloud)
```

### Verify via API

```bash
# SSH to server
ssh -p 2222 deployer@YOUR_SERVER_IP

# List all DNS records
python3 << EOF
import CloudFlare
cf = CloudFlare.CloudFlare(token='YOUR_TOKEN')
zones = cf.zones.get(params={'name': 'alfian-gading.site'})
zone_id = zones[0]['id']
records = cf.zones.dns_records.get(zone_id, params={'type': 'A'})
for r in records:
    print(f"{r['name']} → {r['content']} (Proxied: {r['proxied']})")
EOF
```

### Verify DNS Resolution

```bash
# Test each subdomain
for sub in "" "materi-ku" "panca-trivia" "ruang-istirahat" "tech-talk"; do
  if [ -z "$sub" ]; then
    domain="alfian-gading.site"
  else
    domain="$sub.alfian-gading.site"
  fi
  echo "Testing $domain..."
  dig +short "$domain" @1.1.1.1
done
```

## 🚀 Integration with Nginx Proxy Manager

After DNS setup, configure Nginx Proxy Manager:

### For Each Application

1. **Login to Nginx Proxy Manager**
   - URL: `http://YOUR_SERVER_IP:81`
   - Default: `admin@example.com` / `changeme`

2. **Add Proxy Host**
   ```
   Domain Names: materi-ku.alfian-gading.site
   Scheme: http
   Forward Hostname/IP: materi-ku (Docker container name)
   Forward Port: 80
   
   SSL Tab:
   ☑ Request New SSL Certificate
   ☑ Force SSL
   ☑ HTTP/2 Support
   Email: your@email.com
   ☑ Agree to Let's Encrypt Terms
   ```

3. **Repeat for All Apps**
   - panca-trivia.alfian-gading.site → panca-trivia:80
   - ruang-istirahat.alfian-gading.site → ruang-istirahat:80
   - tech-talk.alfian-gading.site → tech-talk:80

### SSL Flow

```
User Browser
    ↓ HTTPS (Cloudflare SSL)
Cloudflare CDN (Proxied, Orange Cloud)
    ↓ HTTPS (Cloudflare Origin Certificate)
VPS Server (Nginx Proxy Manager)
    ↓ HTTP
Docker Container (Application)
```

## 📚 Related Documentation

- [roles/cloudflare-dns-setup/README.md](roles/cloudflare-dns-setup/README.md)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Python Cloudflare Library](https://github.com/cloudflare/python-cloudflare)
- [Cloudflare DNS Records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/)

## 💡 Tips

1. **One-time setup**: DNS tidak perlu diupdate setiap deploy (kecuali IP berubah)
2. **Verify before apply**: Script shows preview before making changes
3. **Idempotent**: Aman dijalankan berkali-kali (no duplicate records)
4. **Use proxied**: Maksimalkan Cloudflare free benefits (SSL, DDoS, CDN)
5. **Wildcard for dev**: `*.alfian-gading.site` untuk subdomain testing

## 🎯 When to Update DNS

**Update DNS when:**
- ✅ Initial server setup
- ✅ VPS IP changes (server migration)
- ✅ Add new application subdomain
- ✅ Change proxy status (orange ↔ gray cloud)

**NOT needed when:**
- ❌ Application deployment
- ❌ Code updates
- ❌ Docker container restart
- ❌ Nginx config changes

---

**Ready to use!** 🚀

First time setup:
```bash
# 1. Add API token to vault
ansible-vault edit group_vars/all/vault.yml

# 2. Deploy Cloudflare DNS setup
make setup-tags TAGS=cloudflare-dns-setup

# 3. Update DNS records
make update-cloudflare-dns-interactive
```

Done! Your domain `alfian-gading.site` and all subdomains now point to your VPS. 🎉
