# Cloudflare DNS Setup Role

Ansible role untuk menginstall dan mengkonfigurasi Cloudflare DNS management di **server** untuk automasi DNS records.

## Purpose

Role ini:
1. ✅ Install Python Cloudflare library di server
2. ✅ Setup Cloudflare API credentials dari vault
3. ✅ Copy DNS records configuration
4. ✅ Install `update-cloudflare-dns` script
5. ✅ Setup PATH untuk deployer user

## Features

- Install Python Cloudflare library (python3-cloudflare)
- Auto-configure dengan API token dari vault
- Create/Update DNS A records
- Support proxied (Cloudflare CDN) dan DNS only
- Support wildcard records
- Colorful Python script dengan error handling
- One-time setup (option C - setup awal saja)

## Requirements

### Vault Variables

```yaml
# group_vars/all/vault.yml (encrypted)
vault_cloudflare_api_token: "your_cloudflare_api_token_here"
```

**How to get Cloudflare API Token:**
1. Login ke Cloudflare Dashboard
2. Go to: Profile → API Tokens → Create Token
3. Use template: "Edit zone DNS"
4. Or create custom token with permissions:
   - Zone → DNS → Edit
   - Zone → Zone → Read
5. Select specific zone: `alfian-gading.site`
6. Create token and copy it

### Local Files

- `inventory/hosts.ini` - Inventory dengan VPS IP

## DNS Records Configuration

Default configuration in `defaults/main.yml`:

```yaml
cloudflare_domain: "alfian-gading.site"

cloudflare_dns_records:
  # Root domain (proxied)
  - name: "@"
    type: "A"
    proxied: true
    comment: "Root domain - Main website"
  
  # Application subdomains (proxied for SSL, DDoS, CDN)
  - name: "materi-ku"
    type: "A"
    proxied: true
    comment: "Materi-ku application"
  
  - name: "panca-trivia"
    type: "A"
    proxied: true
  
  - name: "ruang-istirahat"
    type: "A"
    proxied: true
  
  - name: "tech-talk"
    type: "A"
    proxied: true
  
  # Wildcard (DNS only - free plan limitation)
  - name: "*"
    type: "A"
    proxied: false
    comment: "Wildcard for development subdomains"
```

### Proxied vs DNS Only

**Proxied (Orange Cloud) - Recommended for apps:**
- ✅ Free SSL/TLS from Cloudflare
- ✅ DDoS protection
- ✅ CDN caching for static assets
- ✅ Hide real server IP
- ❌ Cannot use with wildcard on free plan

**DNS Only (Gray Cloud):**
- ✅ Direct to server (faster)
- ✅ Works with wildcard
- ❌ No Cloudflare protection
- ❌ No free SSL from Cloudflare

## Installation

Role ini dipanggil dari main playbook:

```yaml
# playbooks/server-setup.yml
- role: cloudflare-dns-setup
  tags: [system, cloudflare-dns-setup]
```

### Install via Makefile

```bash
# Full setup (includes Cloudflare DNS)
make setup

# Cloudflare DNS only
make setup-tags TAGS=cloudflare-dns-setup
```

## Files Created on Server

```
/home/deployer/
├── .config/cloudflare/
│   ├── cloudflare.ini          # API credentials (0600)
│   └── dns-records.yml         # DNS records config
└── .local/bin/
    └── update-cloudflare-dns   # Executable Python script
```

## Usage

### One-Time DNS Setup

```bash
# Option A: Via Makefile (Recommended)
make update-cloudflare-dns-interactive

# Option B: Manual SSH
ssh -p 2222 deployer@YOUR_SERVER_IP
update-cloudflare-dns
```

### Script Features

The Python script will:
1. ✅ Check requirements (credentials, config files)
2. ✅ Get VPS IP from inventory
3. ✅ Load DNS records configuration
4. ✅ Connect to Cloudflare API
5. ✅ Get Zone ID for domain
6. ✅ Fetch existing DNS records
7. ✅ Show what will be updated
8. ✅ Ask for confirmation
9. ✅ Create/Update DNS records
10. ✅ Show summary

### Example Output

```
╔═══════════════════════════════════════════════════════════════╗
║  Update Cloudflare DNS Records                          ║
╚═══════════════════════════════════════════════════════════════╝

▶ Checking requirements...
✓ DNS records configuration found
✓ Cloudflare credentials found

▶ Getting VPS IP from inventory...
✓ VPS IP: 123.45.67.89

▶ Loading DNS records configuration...
✓ Loaded 6 DNS records to configure

▶ Connecting to Cloudflare API...
✓ Connected to Cloudflare API

▶ Getting Zone ID for alfian-gading.site...
✓ Zone ID: abc123def456

▶ Fetching existing DNS records...
✓ Found 0 existing A records

DNS Records to configure:
  • alfian-gading.site → 123.45.67.89 (Proxied)
  • materi-ku.alfian-gading.site → 123.45.67.89 (Proxied)
  • panca-trivia.alfian-gading.site → 123.45.67.89 (Proxied)
  • ruang-istirahat.alfian-gading.site → 123.45.67.89 (Proxied)
  • tech-talk.alfian-gading.site → 123.45.67.89 (Proxied)
  • *.alfian-gading.site → 123.45.67.89 (DNS Only)

Continue? [y/N] y

▶ Updating DNS records...

✓ Created alfian-gading.site → 123.45.67.89 (Proxied)
✓ Created materi-ku.alfian-gading.site → 123.45.67.89 (Proxied)
✓ Created panca-trivia.alfian-gading.site → 123.45.67.89 (Proxied)
✓ Created ruang-istirahat.alfian-gading.site → 123.45.67.89 (Proxied)
✓ Created tech-talk.alfian-gading.site → 123.45.67.89 (Proxied)
✓ Created *.alfian-gading.site → 123.45.67.89 (DNS Only)

╔═══════════════════════════════════════════════════════════════╗
║  Summary                                                      ║
╠═══════════════════════════════════════════════════════════════╣
║  Domain: alfian-gading.site                                   ║
║  VPS IP: 123.45.67.89                                         ║
║  Records processed: 6                                         ║
║  Successful: 6                                                ║
╚═══════════════════════════════════════════════════════════════╝

✓ All DNS records updated successfully!

Note: DNS propagation may take a few minutes.
Verify records at: https://dash.cloudflare.com/
```

## Configuration

### Add New Subdomain

Edit `roles/cloudflare-dns-setup/defaults/main.yml`:

```yaml
cloudflare_dns_records:
  # ... existing records ...
  
  - name: "new-app"
    type: "A"
    proxied: true
    comment: "New application"
```

Then re-run:

```bash
make setup-tags TAGS=cloudflare-dns-setup
make update-cloudflare-dns-interactive
```

### Change Domain

Edit `roles/cloudflare-dns-setup/defaults/main.yml`:

```yaml
cloudflare_domain: "your-new-domain.com"
```

### Toggle Proxy Status

Change `proxied` value:

```yaml
- name: "app-name"
  proxied: true   # Orange cloud (proxied)
  # OR
  proxied: false  # Gray cloud (DNS only)
```

## Architecture

```
localhost (ansible-playbook)
    ↓
server (cloudflare-dns-setup role)
    ↓
/home/deployer/.config/cloudflare/ (credentials & config)
/home/deployer/.local/bin/ (script)
    ↓
Cloudflare API (create/update DNS records)
```

## Dependencies

- Python 3.x
- pip3
- python3-cloudflare library
- Ansible 2.9+
- Server: Ubuntu/Debian with apt

## Tags

```bash
# Run this role only
ansible-playbook playbooks/server-setup.yml --tags cloudflare-dns-setup

# Or via Makefile
make setup-tags TAGS=cloudflare-dns-setup
```

## Security

### File Permissions

```bash
/home/deployer/.config/cloudflare/cloudflare.ini  0600 (API token)
/home/deployer/.config/cloudflare/dns-records.yml 0644 (config)
/home/deployer/.local/bin/update-cloudflare-dns   0755 (executable)
```

### API Token Security

- ✅ Token stored in encrypted Ansible vault
- ✅ Token only on server (not on localhost)
- ✅ Token file has restrictive permissions (0600)
- ✅ Limited permissions (Zone DNS Edit only)

## Verification

```bash
# Check Python Cloudflare installed
ssh -p 2222 deployer@YOUR_SERVER_IP 'pip3 show cloudflare'

# Check credentials file
ssh -p 2222 deployer@YOUR_SERVER_IP 'ls -la ~/.config/cloudflare/'

# Check script exists
ssh -p 2222 deployer@YOUR_SERVER_IP 'which update-cloudflare-dns'

# Test script
ssh -p 2222 deployer@YOUR_SERVER_IP 'update-cloudflare-dns'
```

## Troubleshooting

### API Token Invalid

```bash
# Check token in vault
ansible-vault view group_vars/all/vault.yml --ask-vault-pass | grep cloudflare

# Re-generate token in Cloudflare Dashboard
# Update vault:
ansible-vault edit group_vars/all/vault.yml

# Re-run setup
make setup-tags TAGS=cloudflare-dns-setup
```

### Domain Not Found

Make sure domain is added to your Cloudflare account:
1. Go to Cloudflare Dashboard
2. Add site: `alfian-gading.site`
3. Change nameservers at domain registrar to Cloudflare's nameservers
4. Wait for activation

### Python Module Not Found

```bash
# SSH to server
ssh -p 2222 deployer@YOUR_SERVER_IP

# Install manually
sudo pip3 install cloudflare

# Or re-run role
make setup-tags TAGS=cloudflare-dns-setup
```

### DNS Not Propagating

DNS changes can take time:
- Cloudflare: Usually instant to 1 minute
- Global propagation: Up to 24-48 hours (rare)

Check DNS:
```bash
# Check with dig
dig alfian-gading.site
dig materi-ku.alfian-gading.site

# Check with nslookup
nslookup alfian-gading.site 1.1.1.1
```

## When to Update DNS

Update DNS records when:
- ✅ **Initial setup** (first time)
- ✅ **VPS IP changes** (migrate to new server)
- ✅ **Add new subdomain** (new application)
- ✅ **Change proxy status** (toggle orange/gray cloud)

**NOT needed when:**
- ❌ Deploy aplikasi (IP sama)
- ❌ Update code
- ❌ Restart services

## Related Documentation

- [Cloudflare API Docs](https://developers.cloudflare.com/api/)
- [Python Cloudflare Library](https://github.com/cloudflare/python-cloudflare)

## Nginx Proxy Manager Integration

Setelah DNS records dibuat, configure di Nginx Proxy Manager:

1. Login ke Nginx Proxy Manager
2. Add Proxy Host untuk setiap subdomain:
   - Domain: `materi-ku.alfian-gading.site`
   - Forward to: `materi-ku:80` (Docker container)
   - SSL: Request Let's Encrypt certificate
3. Cloudflare akan handle SSL termination di edge
4. Nginx akan handle SSL dari Cloudflare ke server

## Author

Created for server infrastructure automation with Cloudflare DNS integration.

## License

MIT
