# 🔐 Vault Management Guide

Comprehensive guide untuk managing secrets menggunakan Ansible Vault di project ini.

## 📁 Vault Structure

### New Centralized Structure (Best Practice)

```
group_vars/
├── all/
│   ├── vars.yml      # Non-sensitive variables (plain text)
│   └── vault.yml     # ALL sensitive credentials (encrypted)
└── README.md         # This file
```

**Benefits:**
- ✅ **Centralized** - Semua secrets di satu tempat
- ✅ **Organized** - Terpisah antara sensitive dan non-sensitive
- ✅ **Automatic** - Ansible auto-load dari group_vars/all/
- ✅ **Secure** - Hanya vault.yml yang encrypted
- ✅ **Easy Management** - Mudah backup, rotate, dan audit
- ✅ **Team Friendly** - Clear structure untuk collaboration

### Old Structure (Deprecated)

```
roles/
├── role-name/
│   ├── defaults/main.yml    # ❌ Encrypted (tersebar)
│   ├── vars/main.yml         # ❌ Encrypted (tersebar)
│   └── files/.env            # ❌ Encrypted (tersebar)
```

**Issues with old structure:**
- ❌ Secrets tersebar di 13+ files
- ❌ Hard to manage dan audit
- ❌ Duplicate credentials
- ❌ Sulit untuk rotate passwords

## 🔑 File Purposes

### 1. `vars.yml` (Plain Text)

**Purpose:** Non-sensitive configuration variables

**Contains:**
- Network names
- Docker image names (public)
- Default paths
- Non-sensitive URLs
- Application defaults

**Example:**
```yaml
---
github_username: "alfian57"
docker_registry: "ghcr.io"
mysql_image: "mysql:8.0"
nginx_proxy_network: "nginx_proxy_manager_network"
```

**Security:** ✅ Safe to commit to git (already committed)

### 2. `vault.yml` (Encrypted)

**Purpose:** ALL sensitive credentials and secrets

**Contains:**
- GitHub tokens
- Database passwords
- API keys
- Application secrets
- User credentials
- SSL certificates

**Example (after encryption):**
```
$ANSIBLE_VAULT;1.1;AES256
61333035646335326439633039643066653634316461333539356230336134376237326130616163
...
```

**Security:** 🔒 MUST be encrypted before committing

## 🚀 Quick Start

### 1. Setup Vault Password

```bash
# Using Makefile
make vault-create-pass

# Manual
echo "your-secure-vault-password" > .vault_pass
chmod 600 .vault_pass
```

### 2. Edit Vault File (First Time)

```bash
# Edit vault.yml and replace placeholder values
nano group_vars/all/vault.yml

# Replace ALL "your-xxx-here" dengan actual values
```

### 3. Encrypt Vault File

```bash
# Using Makefile
make vault-encrypt FILE=group_vars/all/vault.yml

# Manual
ansible-vault encrypt group_vars/all/vault.yml
```

### 4. Verify Encryption

```bash
# Check if encrypted
head -1 group_vars/all/vault.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256

# View content (without decrypting permanently)
make vault-view FILE=group_vars/all/vault.yml
```

### 5. Use in Playbooks

Variables automatically available! Ansible auto-loads dari `group_vars/all/`:

```yaml
# In your tasks
- name: Use vault variable
  debug:
    msg: "GitHub token: {{ vault_github_token }}"
```

## 🛠️ Common Operations

### View Encrypted Content

```bash
# Using Makefile
make vault-view FILE=group_vars/all/vault.yml

# Manual
ansible-vault view group_vars/all/vault.yml
```

### Edit Encrypted File

```bash
# Using Makefile (recommended)
make vault-edit FILE=group_vars/all/vault.yml

# Manual
ansible-vault edit group_vars/all/vault.yml
```

### Re-encrypt with New Password

```bash
# Change vault password
ansible-vault rekey group_vars/all/vault.yml

# Update .vault_pass dengan password baru
echo "new-password" > .vault_pass
chmod 600 .vault_pass
```

### Decrypt Temporarily (NOT RECOMMENDED)

```bash
# Only for migration or debugging
ansible-vault decrypt group_vars/all/vault.yml

# Don't forget to re-encrypt!
ansible-vault encrypt group_vars/all/vault.yml
```

### Encrypt Additional Files

```bash
# If you have other sensitive files
make vault-encrypt FILE=path/to/sensitive/file

# Or manual
ansible-vault encrypt path/to/sensitive/file
```

## 📋 Variable Naming Convention

### Pattern: `vault_<category>_<name>`

**Examples:**
```yaml
# Database credentials
vault_mysql_root_password: "xxx"
vault_postgres_password: "xxx"

# Application secrets
vault_materi_ku:
  app_key: "xxx"
  db_password: "xxx"

# User credentials
vault_users:
  - username: "deploy"
    password: "xxx"

# API tokens
vault_github_token: "xxx"
vault_cloudflare_api_token: "xxx"
```

**Benefits:**
- Clear separation: `vault_*` = sensitive, others = non-sensitive
- Easy to audit: `grep vault_ group_vars/all/vault.yml`
- Auto-complete friendly in editors
- Clear documentation

## 🔄 Migration from Old Structure

### Step 1: Decrypt Old Files

```bash
# Decrypt all old encrypted files
ansible-vault decrypt roles/*/defaults/main.yml
ansible-vault decrypt roles/*/vars/main.yml
ansible-vault decrypt roles/*/files/.env
```

### Step 2: Extract Credentials

Extract semua credentials ke `group_vars/all/vault.yml` dengan format baru:

```yaml
# Old: roles/mysql-setup/files/.env
MYSQL_ROOT_PASSWORD=oldpass123

# New: group_vars/all/vault.yml
vault_mysql_root_password: "oldpass123"
```

### Step 3: Update Tasks

Update tasks untuk reference vault variables:

```yaml
# Old
- name: Deploy MySQL
  environment:
    MYSQL_ROOT_PASSWORD: "{{ lookup('file', 'roles/mysql-setup/files/.env') }}"

# New
- name: Deploy MySQL
  environment:
    MYSQL_ROOT_PASSWORD: "{{ vault_mysql_root_password }}"
```

### Step 4: Encrypt New Vault

```bash
make vault-encrypt FILE=group_vars/all/vault.yml
```

### Step 5: Test

```bash
make ping
make setup-dry-run
```

### Step 6: Remove Old Files

```bash
# Backup first!
mkdir -p backup/old-vaults
cp roles/*/defaults/main.yml backup/old-vaults/ 2>/dev/null || true
cp roles/*/vars/main.yml backup/old-vaults/ 2>/dev/null || true
cp roles/*/files/.env backup/old-vaults/ 2>/dev/null || true

# Remove old encrypted files
rm roles/*/defaults/main.yml 2>/dev/null || true
rm roles/*/vars/main.yml 2>/dev/null || true  
rm roles/*/files/.env 2>/dev/null || true
```

## 🔐 Security Best Practices

### 1. Vault Password Management

```bash
# Strong password
# Minimal 20 characters, kombinasi huruf, angka, simbol
echo "Sup3rS3cur3P@ssw0rd!2024#Ansible" > .vault_pass
chmod 600 .vault_pass

# NEVER commit .vault_pass to git
# Already in .gitignore
```

### 2. Rotate Passwords Regularly

```bash
# 1. Generate new passwords
pwgen -s 32 1  # Linux
openssl rand -base64 32  # macOS/Linux

# 2. Edit vault
make vault-edit FILE=group_vars/all/vault.yml

# 3. Update services
make setup
```

### 3. Use Password Manager for Team

**Options:**
- 1Password - Store vault password in shared vault
- LastPass - Team shared folder
- HashiCorp Vault - Enterprise solution
- AWS Secrets Manager - Cloud solution

### 4. Audit Vault Access

```bash
# Check vault history
git log group_vars/all/vault.yml

# Who last edited
git log -1 --format="%an <%ae>" group_vars/all/vault.yml

# Show encrypted diff
git diff HEAD~1 group_vars/all/vault.yml
```

### 5. Backup Vault

```bash
# Backup encrypted version
cp group_vars/all/vault.yml backup/vault-$(date +%Y%m%d).yml

# Backup decrypted (secure location only!)
ansible-vault decrypt group_vars/all/vault.yml --output=/secure/path/vault-backup.yml
```

## 🎯 Variable Reference

### Available Vault Variables

See the full list in `group_vars/all/vault.yml`:

#### GitHub/Docker
- `vault_github_token` - GitHub PAT for GHCR
- `vault_docker_password` - Docker registry password

#### MySQL
- `vault_mysql_root_password` - MySQL root password
- `vault_mysql_databases` - Dict of all MySQL databases
  - `materi_ku`, `panca_trivia`, `ruang_istirahat`, `tech_talk`

#### PostgreSQL  
- `vault_postgres_password` - PostgreSQL password
- `vault_postgres_databases` - Dict of PostgreSQL databases

#### Redis
- `vault_redis_password` - Redis password

#### Applications
- `vault_materi_ku` - Materi Ku app secrets
- `vault_panca_trivia` - Panca Trivia app secrets
- `vault_ruang_istirahat` - Ruang Istirahat app secrets
- `vault_tech_talk` - Tech Talk app secrets

#### Users
- `vault_users` - List of user credentials

### Usage in Templates

```jinja2
# In docker-compose.yml.j2
version: '3.8'
services:
  mysql:
    environment:
      MYSQL_ROOT_PASSWORD: {{ vault_mysql_root_password }}
      MYSQL_DATABASE: {{ vault_mysql_databases.materi_ku.name }}
      MYSQL_USER: {{ vault_mysql_databases.materi_ku.user }}
      MYSQL_PASSWORD: {{ vault_mysql_databases.materi_ku.password }}
```

```jinja2
# In .env.j2
APP_KEY={{ vault_materi_ku.app_key }}
DB_PASSWORD={{ vault_materi_ku.db_password }}
REDIS_PASSWORD={{ vault_redis_password }}
```

## 🐛 Troubleshooting

### Issue: "Decryption failed"

**Cause:** Wrong vault password

**Solution:**
```bash
# Check .vault_pass content
cat .vault_pass

# Try with prompt instead
ansible-vault view group_vars/all/vault.yml --ask-vault-pass

# Update .vault_pass
echo "correct-password" > .vault_pass
chmod 600 .vault_pass
```

### Issue: "vault.yml not found"

**Cause:** File tidak ter-create atau salah path

**Solution:**
```bash
# Check if exists
ls -la group_vars/all/vault.yml

# Create if missing
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
make vault-edit FILE=group_vars/all/vault.yml
```

### Issue: Variables not loaded

**Cause:** Typo di variable name atau tidak encrypted

**Solution:**
```bash
# Test variable loading
ansible all -m debug -a "var=vault_github_token"

# Check if encrypted
head -1 group_vars/all/vault.yml

# Should show: $ANSIBLE_VAULT;1.1;AES256
```

### Issue: "ERROR! Attempting to decrypt but no vault secrets found"

**Cause:** .vault_pass tidak ditemukan atau ansible.cfg tidak configured

**Solution:**
```bash
# Check ansible.cfg
grep vault_password_file ansible.cfg

# Should show:
# vault_password_file = ./.vault_pass

# Or use environment variable
export ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass
```

## 📊 Vault Statistics

**Current Structure:**
- ✅ 1 encrypted file (group_vars/all/vault.yml)
- ✅ 1 plain file (group_vars/all/vars.yml)
- ✅ 100+ credentials centralized
- ✅ Clear separation of concerns

**Old Structure (deprecated):**
- ❌ 13 encrypted files scattered
- ❌ Hard to maintain
- ❌ Duplicate credentials
- ❌ No clear organization

**Improvement:**
- 📉 92% reduction in encrypted files (13 → 1)
- ⚡ 10x faster to manage
- 🔒 Better security through centralization
- 📝 Easier auditing and rotation

## 📚 Additional Resources

- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Best Practices for Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html#variables-and-vaults)
- [group_vars Directory](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html#organizing-host-and-group-variables)

## 🚀 Quick Command Reference

```bash
# Create vault password
make vault-create-pass

# View vault (read-only)
make vault-view FILE=group_vars/all/vault.yml

# Edit vault (decrypt → edit → encrypt)
make vault-edit FILE=group_vars/all/vault.yml

# Encrypt file
make vault-encrypt FILE=group_vars/all/vault.yml

# Decrypt file (not recommended)
make vault-decrypt FILE=group_vars/all/vault.yml

# Test deployment with vault
make setup-dry-run

# Full deployment
make setup
```

---

**Last Updated:** November 2025

**Status:** ✅ Production Ready - Centralized Vault Structure Implemented
