# Nginx Proxy Manager Setup Role

Ansible role untuk menginstall dan mengkonfigurasi Nginx Proxy Manager (NPM) dengan **auto SSL setup** menggunakan Let's Encrypt.

## Purpose

Role ini:
1. ✅ Deploy Nginx Proxy Manager via Docker
2. ✅ Auto-configure admin credentials dari vault
3. ✅ Create proxy hosts untuk semua aplikasi
4. ✅ **Auto-request Let's Encrypt SSL certificates**
5. ✅ **Force SSL** (HTTP → HTTPS redirect)
6. ✅ **Enable HTTP/2** support
7. ✅ **Enable HSTS** security header
8. ✅ **Block exploits** protection
9. ✅ Support websocket & caching (configurable)

## Features

### Automatic SSL Configuration 🔒

Role ini akan **otomatis**:
- ✅ Request Let's Encrypt SSL certificate untuk setiap subdomain
- ✅ Enable Force SSL (redirect HTTP → HTTPS)
- ✅ Configure HTTP/2 support
- ✅ Enable HSTS (HTTP Strict Transport Security)
- ✅ Enable block exploits protection

**Tidak perlu manual setup SSL di NPM!**

### Security Features

- ✅ **Auto-change default credentials** (admin@example.com)
- ✅ **Force SSL** - All traffic via HTTPS
- ✅ **HTTP/2** - Better performance
- ✅ **HSTS** - Prevent SSL stripping attacks
- ✅ **Block exploits** - Protection against common attacks

### Proxy Host Management

- ✅ Idempotent (safe to re-run)
- ✅ Create or update proxy hosts
- ✅ Support websocket (configurable)
- ✅ Support caching (configurable)
- ✅ Auto-detect existing hosts

## Requirements

### Vault Variables

```yaml
# group_vars/all/vault.yml (encrypted)
vault_npm_admin_email: "your-email@example.com"
vault_npm_admin_password: "your-strong-password"
vault_npm_admin_nickname: "Admin"
vault_npm_domain_name: "alfian-gading.site"
```

### Prerequisites

1. **Docker must be installed** (via docker-setup role)
2. **DNS records must point to server** (via cloudflare-dns-setup role)
3. **Port 80 and 443 must be open** (for Let's Encrypt validation)

### Domain Setup

**Important:** DNS records MUST be configured BEFORE running this role!

```bash
# Run cloudflare-dns-setup first
make setup-tags TAGS=cloudflare-dns-setup
make update-cloudflare-dns-interactive

# Then run nginx-proxy-setup
make setup-tags TAGS=nginx-proxy-setup
```

## Installation

Role ini dipanggil dari main playbook:

```yaml
# playbooks/server-setup.yml
- role: nginx-proxy-setup
  tags: [infrastructure, nginx-proxy-setup]
```

### Install via Makefile

```bash
# Full setup (includes NPM)
make setup

# NPM only
make setup-tags TAGS=nginx-proxy-setup
```

## Configuration

### Proxy Hosts

Edit `defaults/main.yml`:

```yaml
proxy_hosts:
  - subdomain: "materi-ku"
    scheme: "http"
    forward_host: "materi-ku"          # Docker container name
    forward_port: 80
    caching_enabled: true
    websocket_support: false
  
  - subdomain: "api"
    scheme: "http"
    forward_host: "backend-api"
    forward_port: 3000
    caching_enabled: false              # Disable for APIs
    websocket_support: true             # Enable for real-time apps
```

### Add New Application

```yaml
proxy_hosts:
  # ... existing entries ...
  
  - subdomain: "new-app"
    scheme: "http"
    forward_host: "new-app-container"
    forward_port: 8080
    caching_enabled: true
    websocket_support: false
```

Then re-run:

```bash
make setup-tags TAGS=nginx-proxy-setup
```

## SSL Setup Process

### Automatic SSL Workflow

```
1. Create proxy host (HTTP only)
   ↓
2. Wait for proxy host accessible
   ↓
3. Request Let's Encrypt certificate
   ↓
4. Let's Encrypt validates domain (HTTP-01 challenge)
   ↓
5. Certificate issued
   ↓
6. Update proxy host with SSL enabled
   ↓
7. Enable Force SSL redirect
   ↓
8. Enable HTTP/2 + HSTS
   ↓
9. ✅ HTTPS ready!
```

### Let's Encrypt Validation

NPM uses **HTTP-01 challenge**:
1. Let's Encrypt sends validation request to `http://subdomain.domain/.well-known/acme-challenge/xxx`
2. NPM responds with validation token
3. Certificate issued

**Requirements:**
- ✅ DNS must point to server
- ✅ Port 80 must be open
- ✅ Domain must be accessible from internet

### Cloudflare Integration

With Cloudflare proxy (orange cloud):

```
User Browser
    ↓ HTTPS (Cloudflare Universal SSL)
Cloudflare CDN
    ↓ HTTPS (Let's Encrypt from NPM)
VPS Server (Nginx Proxy Manager)
    ↓ HTTP
Docker Container
```

**Both Cloudflare AND NPM have SSL:**
- Cloudflare: Edge SSL (browser → Cloudflare)
- NPM: Origin SSL (Cloudflare → server)

**Why both?**
- End-to-end encryption
- No "mixed content" warnings
- Better security

## Usage

### Access Admin Panel

```
URL: http://YOUR_SERVER_IP:81
Username: (from vault: vault_npm_admin_email)
Password: (from vault: vault_npm_admin_password)
```

### Verify SSL Certificates

After deployment, check each subdomain:

```bash
# Check SSL certificate
curl -I https://materi-ku.alfian-gading.site

# Should show:
# HTTP/2 200
# strict-transport-security: max-age=31536000

# Verify redirect
curl -I http://materi-ku.alfian-gading.site
# Should show:
# HTTP/1.1 301 Moved Permanently
# Location: https://materi-ku.alfian-gading.site
```

### View in NPM Dashboard

1. Login to NPM admin panel
2. Go to "Proxy Hosts"
3. Verify each host has:
   - 🔒 SSL certificate (Let's Encrypt)
   - ✅ Force SSL enabled
   - ✅ HTTP/2 support
   - ✅ HSTS enabled

## Troubleshooting

### SSL Certificate Request Failed

**Error:** SSL certificate request returns 400 or fails

**Possible causes:**
1. DNS not pointing to server
2. Domain not accessible from internet
3. Port 80 blocked
4. Rate limit from Let's Encrypt

**Solutions:**

```bash
# 1. Check DNS
dig materi-ku.alfian-gading.site

# Should return your server IP

# 2. Check port 80 accessible
curl http://YOUR_SERVER_IP

# Should return NPM page

# 3. Check from external
curl http://materi-ku.alfian-gading.site

# Should work (not connection refused)

# 4. Check Let's Encrypt rate limits
# Max 50 certificates per domain per week
# Wait if limit exceeded
```

### Proxy Host Created Without SSL

**Symptom:** Proxy host exists but no SSL

**Solution:**

```bash
# 1. Verify DNS first
dig subdomain.alfian-gading.site

# 2. Re-run role (will retry SSL)
make setup-tags TAGS=nginx-proxy-setup

# 3. Manual request in NPM dashboard
# Login → Proxy Hosts → Edit → SSL tab → Request certificate
```

### Certificate Expired

Let's Encrypt certificates auto-renew in NPM.

**If renewal fails:**
1. Check NPM logs: `docker logs nginx-proxy-manager`
2. Verify domain still accessible
3. Check Let's Encrypt status: https://letsencrypt.status.io/
4. Re-request certificate in NPM dashboard

### Cloudflare SSL/TLS Mode

**Important:** Set Cloudflare SSL/TLS mode to **Full** (not Flexible):

```
Cloudflare Dashboard → SSL/TLS → Overview
Mode: Full (or Full Strict)
```

**Why:**
- Flexible: Cloudflare → Server uses HTTP (insecure)
- Full: Cloudflare → Server uses HTTPS (secure)
- Full Strict: Validates server certificate (most secure)

### Websocket Not Working

**Symptom:** WebSocket connections fail

**Solution:**

```yaml
# Enable websocket support
proxy_hosts:
  - subdomain: "app"
    websocket_support: true  # Set to true
```

Re-run role:

```bash
make setup-tags TAGS=nginx-proxy-setup
```

## Architecture

```
Internet
    ↓
Port 80, 443 (Nginx Proxy Manager)
    ↓
Docker Network: nginx_proxy_manager
    ↓
Application Containers:
    - materi-ku:80
    - panca-trivia:80
    - ruang-istirahat:80
    - tech-talk:80
```

### Docker Compose

NPM deployed with:
- **Image:** jc21/nginx-proxy-manager:2.12.3
- **Ports:** 80, 443 (public), 81 (admin)
- **Volumes:** npm_data, npm_letsencrypt
- **Network:** nginx_proxy_manager (bridge)
- **Health check:** Automatic

## Advanced Configuration

### Custom Advanced Config

For advanced Nginx configuration, use NPM dashboard:

```
Proxy Host → Edit → Advanced tab → Custom Nginx Configuration
```

Example - Rate limiting:

```nginx
limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;
limit_req zone=mylimit burst=20 nodelay;
```

### Access Lists

Create access lists in NPM dashboard:
- IP whitelist/blacklist
- HTTP authentication
- Apply to specific proxy hosts

### Custom Locations

Add custom location blocks in NPM:
- Different backends for different paths
- Static file serving
- Custom headers

## Monitoring

### Check NPM Status

```bash
# Docker status
docker ps | grep nginx-proxy-manager

# Logs
docker logs nginx-proxy-manager

# Follow logs
docker logs -f nginx-proxy-manager
```

### SSL Certificate Expiry

NPM auto-renews 30 days before expiry.

Check expiry:

```bash
echo | openssl s_client -servername materi-ku.alfian-gading.site \
  -connect materi-ku.alfian-gading.site:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### Performance Monitoring

Use Cloudflare Analytics:
- Requests per second
- Bandwidth usage
- Cache hit ratio
- SSL/TLS version distribution

## Security Best Practices

### Admin Panel Security

1. **Change default port 81** (optional):
   ```yaml
   # Edit docker-compose template
   ports:
     - "8081:81"  # Custom admin port
   ```

2. **Use strong password** (in vault)
3. **Enable 2FA** (in NPM dashboard)
4. **Restrict admin access** (firewall rules)

### SSL/TLS Configuration

NPM automatically uses:
- ✅ TLS 1.2 and 1.3
- ✅ Strong cipher suites
- ✅ HSTS header
- ✅ OCSP stapling

### Rate Limiting

Configure in NPM advanced settings per host.

### DDoS Protection

Use Cloudflare proxy (orange cloud):
- DDoS mitigation
- WAF (Web Application Firewall)
- Rate limiting
- Bot management

## Related Documentation

- [Nginx Proxy Manager Docs](https://nginxproxymanager.com/guide/)
- [Let's Encrypt](https://letsencrypt.org/)
- [Cloudflare SSL/TLS](https://developers.cloudflare.com/ssl/)

## Integration with Other Roles

### Execution Order

```yaml
1. docker-setup          # Install Docker
2. cloudflare-dns-setup  # Setup DNS records
3. nginx-proxy-setup     # Setup NPM + SSL
4. application-setups    # Deploy apps
```

### Application Integration

Applications must:
1. Be on same Docker network OR use container name
2. Expose appropriate port
3. Handle X-Forwarded-* headers

Example Laravel config:

```php
// config/trustedproxy.php
'proxies' => '*',
'headers' => Request::HEADER_X_FORWARDED_ALL,
```

## Performance Tips

1. **Enable caching** for static content
2. **Use HTTP/2** (auto-enabled)
3. **Enable gzip compression** (default in NPM)
4. **Use Cloudflare CDN** for global performance
5. **Enable HSTS** (auto-enabled)

## Backup & Restore

### Backup NPM Data

```bash
# Backup NPM configuration
docker run --rm \
  -v npm_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/npm-backup.tar.gz /data

# Backup Let's Encrypt certificates
docker run --rm \
  -v npm_letsencrypt:/letsencrypt \
  -v $(pwd):/backup \
  alpine tar czf /backup/letsencrypt-backup.tar.gz /letsencrypt
```

### Restore

```bash
# Restore NPM data
docker run --rm \
  -v npm_data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd / && tar xzf /backup/npm-backup.tar.gz"

# Restart NPM
docker restart nginx-proxy-manager
```

## Author

Created for server infrastructure automation with auto SSL configuration.

## License

MIT
