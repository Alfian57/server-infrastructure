# Server Infrastructure with Ansible

Ansible playbooks dan roles untuk automasi setup dan management server infrastructure dengan support untuk multiple tech stacks: Laravel, React, Next.js, Express.js, dan Golang.

## 📋 Daftar Isi

- [Features](#-features)
- [Struktur Proyek](#️-struktur-proyek)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Instalasi](#-instalasi)
- [Penggunaan dengan Makefile](#-penggunaan-dengan-makefile)
- [Penggunaan Manual](#-penggunaan-manual)
- [Roles](#-roles)
- [Konfigurasi](#️-konfigurasi)

## ✨ Features

- 🎯 **One-Command Deployment**: Deploy complete infrastructure dengan satu command
- 🔒 **Secure by Default**: Ansible Vault untuk credentials, proper file permissions
- 🚀 **Multi-Stack Support**: Laravel, React, Next.js, Express.js, Golang
- 📦 **DRY Principle**: Shared tasks untuk minimize code duplication
- 🏷️ **Tag-based Execution**: Deploy specific layers (system/infrastructure/database/application)
- 🔄 **Auto-healing**: Automatic restart untuk unhealthy containers
- 📊 **Health Checks**: Built-in health monitoring untuk semua services
- 🛠️ **Makefile Commands**: 50+ shortcut commands untuk ease of use
- 📝 **Comprehensive Docs**: Detailed documentation untuk setiap role dan stack

## 🏗️ Struktur Proyek

```
.
├── Makefile                   # 50+ command shortcuts
├── MAKEFILE_GUIDE.md          # Comprehensive Makefile documentation
├── ansible.cfg                # Konfigurasi Ansible
├── inventory/
│   └── hosts.ini              # Daftar host server
├── playbooks/
│   └── server-setup.yml       # Main playbook untuk setup server
└── roles/
    ├── common/                # Shared tasks dan files
    │   ├── tasks/
    │   │   ├── deploy-laravel-app.yml    # Laravel deployment template
    │   │   ├── deploy-react-app.yml      # React deployment template
    │   │   ├── deploy-nextjs-app.yml     # Next.js deployment template
    │   │   ├── deploy-express-app.yml    # Express deployment template
    │   │   └── deploy-golang-app.yml     # Golang deployment template
    │   ├── files/
    │   │   └── update.sh                 # Auto-update script for containers
    │   ├── README.md                     # Shared tasks documentation
    │   ├── APPLICATION_TEMPLATE.md       # Quick start guide for new apps
    │   └── DOCKER_COMPOSE_TEMPLATES.md   # Docker compose examples
    ├── update-apt/            # Update sistem Ubuntu/Debian
    ├── users-setup/           # Manajemen user dan SSH keys
    ├── git-setup/             # Instalasi dan konfigurasi Git
    ├── docker-setup/          # Instalasi Docker & Docker Compose
    ├── autoheal-setup/        # Auto-healing untuk Docker containers
    ├── nginx-proxy-setup/     # Nginx Proxy Manager
    ├── mysql-setup/           # MySQL database
    ├── postgres-setup/        # PostgreSQL database
    ├── redis-setup/           # Redis cache
    ├── materi-ku-setup/       # Aplikasi Materi-Ku (Laravel)
    ├── panca-trivia-setup/    # Aplikasi Panca Trivia (Laravel)
    ├── ruang-istirahat-setup/ # Aplikasi Ruang Istirahat (Laravel)
    └── tech-talk-setup/       # Aplikasi Tech Talk (Laravel)
```

## 📦 Prerequisites

- **Ansible** 2.9 atau lebih tinggi
- **Python** 3.x
- **Make** (untuk menggunakan Makefile commands)
- **SSH access** ke target server
- **Sudo privileges** pada target server

Check prerequisites:
```bash
ansible --version
python3 --version
make --version
ssh user@your-server
```

## ⚡ Quick Start

### 1. Clone dan Setup
```bash
# Clone repository
git clone <repository-url>
cd server-infra-with-ansible

# Install dependencies
make install
```

### 2. Konfigurasi Vault Password (untuk decrypt encrypted files)
```bash
# Buat vault password file
make vault-create-pass

# Atau manual
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass
```

### 3. Update Inventory
```bash
# Edit dengan server IP Anda
nano inventory/hosts.ini
```

### 4. Test Connection
```bash
make ping
```

### 5. Deploy!
```bash
# Full deployment
make setup

# Atau selective deployment
make infrastructure    # Deploy Docker, Nginx, Autoheal
make database         # Deploy MySQL, PostgreSQL, Redis
make application      # Deploy semua applications
```

## 🚀 Instalasi

### Opsi 1: Menggunakan Makefile (Recommended)

```bash
# Install Ansible dan collections
make install

# Verify installation
make version
```

### Opsi 2: Manual Installation

1. Clone repository:
```bash
git clone <repository-url>
cd server-infra-with-ansible
```

2. Install Ansible collections:
```bash
ansible-galaxy collection install community.docker
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.general
```

3. Install ansible-lint (optional, untuk code quality):
```bash
pip install ansible-lint
```

4. Konfigurasi inventory:
```bash
# Edit inventory/hosts.ini dengan IP server Anda
nano inventory/hosts.ini
```

5. Setup vault password (jika ada encrypted files):
```bash
# Create vault password file
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass
```

## 🛠️ Penggunaan dengan Makefile

Makefile menyediakan **50+ commands** untuk memudahkan management infrastructure.

### 📖 Lihat Semua Commands
```bash
make help
```

### 🎯 Common Commands

#### General
```bash
make ping              # Test connection ke servers
make check             # Syntax check playbook
make lint              # Lint Ansible code
make status            # Quick status check
```

#### Full Deployment
```bash
make setup             # Complete server setup
make setup-verbose     # Setup dengan verbose output
make setup-dry-run     # Dry run (no changes)
```

#### Tag-based Deployment
```bash
make system            # Deploy system roles
make infrastructure    # Deploy infrastructure roles
make database          # Deploy database roles
make application       # Deploy application roles
```

#### Individual Roles
```bash
make docker            # Setup Docker
make nginx             # Setup Nginx Proxy Manager
make mysql             # Setup MySQL
make redis             # Setup Redis
```

#### Application Deployment
```bash
make materi-ku         # Deploy Materi-Ku app
make panca-trivia      # Deploy Panca Trivia app
make all-apps          # Deploy all applications

# Dynamic redeploy
make redeploy-app APP=materi-ku
```

#### Server Management
```bash
make facts             # Gather server facts
make list-hosts        # List all hosts
make list-tags         # List available tags
make server-info       # Display server information
```

#### Vault Management
```bash
# Setup
make vault-create-pass              # Create vault password file

# Main vault operations (recommended)
make vault-main                     # Quick edit main vault (group_vars/all/vault.yml)
make vault-status                   # Show status of all vault files
make vault-migrate                  # Run migration from old structure

# Generic vault operations
make vault-encrypt FILE=path/file   # Encrypt any file
make vault-decrypt FILE=path/file   # Decrypt any file  
make vault-edit FILE=path/file      # Edit any encrypted file
make vault-view FILE=path/file      # View any encrypted file
```

**New Centralized Vault Structure:**
- ✅ All secrets in one place: `group_vars/all/vault.yml`
- ✅ Easy to manage, audit, and rotate
- ✅ Automatic loading by Ansible
- 📚 Full guide: `cat group_vars/README.md`

#### Utilities
```bash
make install           # Install Ansible + collections
make update            # Update collections
make clean             # Clean temporary files
make version           # Show Ansible version
```

### 📚 Detailed Documentation
Untuk dokumentasi lengkap Makefile dengan examples dan workflows, lihat:
```bash
cat MAKEFILE_GUIDE.md
```

## 💻 Penggunaan Manual

## 💻 Penggunaan Manual

Jika tidak menggunakan Makefile, gunakan ansible-playbook command:

### Menjalankan Full Server Setup

```bash
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini
```

### Menjalankan Role Tertentu dengan Tags

```bash
# Hanya setup Docker
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --tags docker-setup

# Deploy hanya infrastructure layer
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --tags infrastructure

# Deploy specific application
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --tags materi-ku-setup
```

### Dry Run (Check Mode)

```bash
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --check
```

### Dengan Vault Password

```bash
# Prompt untuk password
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --ask-vault-pass

# Menggunakan password file
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --vault-password-file=.vault_pass
```

## 🎭 Roles

### 🖥️ System Setup
- **update-apt**: Update dan upgrade paket sistem (safe upgrade strategy)
- **users-setup**: Membuat user, konfigurasi SSH keys, conditional reboot
- **git-setup**: Install Git dan konfigurasi global

### 🏗️ Infrastructure
- **docker-setup**: Install Docker CE dan Docker Compose v2
- **autoheal-setup**: Deploy container untuk auto-restart unhealthy containers
- **nginx-proxy-setup**: Setup Nginx Proxy Manager untuk reverse proxy dengan UI

### 💾 Databases
- **mysql-setup**: Deploy MySQL 8.x container
- **postgres-setup**: Deploy PostgreSQL 14+ container
- **redis-setup**: Deploy Redis 7.x container

### 🚀 Applications

Semua aplikasi menggunakan **shared deployment tasks** untuk consistency:

- **materi-ku-setup**: Laravel application (menggunakan `deploy-laravel-app.yml`)
- **panca-trivia-setup**: Laravel application (menggunakan `deploy-laravel-app.yml`)
- **ruang-istirahat-setup**: Laravel application (menggunakan `deploy-laravel-app.yml`)
- **tech-talk-setup**: Laravel application (menggunakan `deploy-laravel-app.yml`)

### 📦 Common/Shared

Role `common` menyediakan shared tasks untuk deployment berbagai tech stacks:

| Template | Tech Stack | Default Port | Features |
|----------|-----------|--------------|----------|
| `deploy-laravel-app.yml` | Laravel/PHP | 8000 | MySQL network, health checks, storage volumes |
| `deploy-react-app.yml` | React SPA | 3000 | Basic health check, nginx serving |
| `deploy-nextjs-app.yml` | Next.js | 3000 | .next cache, SSR support, longer startup |
| `deploy-express-app.yml` | Express/Node | 3000 | Optional DB network, uploads directory, /health endpoint |
| `deploy-golang-app.yml` | Golang | 8080 | Auto network building, config/data dirs, fast startup |

**Dokumentasi lengkap:**
- `roles/common/README.md` - Detailed usage dan comparison
- `roles/common/APPLICATION_TEMPLATE.md` - Quick start guide untuk new apps
- `roles/common/DOCKER_COMPOSE_TEMPLATES.md` - Docker compose examples

**Code Efficiency:**
- Before: 76 lines per application role
- After: 4 lines per application role (95% reduction!)
- Total saved: ~300 lines across 4 apps

## ⚙️ Konfigurasi

### Ansible Configuration

File `ansible.cfg` berisi konfigurasi dasar:
```ini
[defaults]
inventory = ./inventory/hosts.ini
host_key_checking = False
roles_path = ./roles
private_key_file = ~/.ssh/server_ed25519

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
pipelining = True
```

**Configuration explained:**
- `inventory` - Path ke inventory file
- `host_key_checking = False` - Skip SSH host key verification (untuk testing)
- `roles_path` - Path ke roles directory
- `private_key_file` - Default SSH private key untuk semua hosts
- `ssh_args` - Additional SSH arguments
- `pipelining` - Improve performance dengan SSH pipelining

### Inventory

File `inventory/hosts.ini` berisi daftar server target dengan SSH configuration:

```ini
[all]
127.0.0.1 ansible_user=root ansible_port=2222 ansible_ssh_private_key_file=~/.ssh/server_ed25519

# Format umum:
# <IP/HOSTNAME> ansible_user=<username> ansible_port=<port> ansible_ssh_private_key_file=<path>

# Untuk multiple servers:
# [webservers]
# 192.168.1.10 ansible_user=deploy ansible_port=22 ansible_ssh_private_key_file=~/.ssh/deploy_key
# 192.168.1.11 ansible_user=deploy ansible_port=22 ansible_ssh_private_key_file=~/.ssh/deploy_key
#
# [databases]
# 192.168.1.20 ansible_user=admin ansible_port=2222 ansible_ssh_private_key_file=~/.ssh/admin_key
```

**SSH Configuration Parameters:**
- `ansible_user` - Username untuk SSH login
- `ansible_port` - SSH port (default: 22)
- `ansible_ssh_private_key_file` - Path ke SSH private key
- `ansible_become` - Use sudo (default: true dari playbook)
- `ansible_become_password` - Sudo password (jika diperlukan)

**Test SSH connection manually:**
```bash
# Test dengan SSH langsung
ssh -i ~/.ssh/server_ed25519 root@127.0.0.1 -p 2222

# Test dengan Ansible
make ping
# atau
ansible all -m ping
```

### Variables

Setiap role memiliki variabel yang dapat dikonfigurasi:

**Lokasi variabel:**
- `defaults/main.yml`: Default values (low priority)
- `vars/main.yml`: Role-specific variables (high priority, beberapa encrypted)

**Override variables:**
```bash
# Via command line
ansible-playbook playbooks/server-setup.yml -e "app_name=my-app app_port=4000"

# Via extra vars file
ansible-playbook playbooks/server-setup.yml -e @custom-vars.yml
```

### Ansible Vault

File sensitive (credentials, tokens, passwords) dienkripsi menggunakan Ansible Vault.

**Setup vault password:**
```bash
# Menggunakan Makefile
make vault-create-pass

# Manual
echo "your-secure-password" > .vault_pass
chmod 600 .vault_pass
```

**Encrypt/Decrypt files:**
```bash
# Menggunakan Makefile
make vault-encrypt FILE=roles/mysql-setup/vars/main.yml
make vault-decrypt FILE=roles/mysql-setup/vars/main.yml
make vault-edit FILE=roles/mysql-setup/vars/main.yml
make vault-view FILE=roles/mysql-setup/vars/main.yml

# Manual dengan ansible-vault
ansible-vault encrypt roles/mysql-setup/vars/main.yml
ansible-vault decrypt roles/mysql-setup/vars/main.yml
ansible-vault edit roles/mysql-setup/vars/main.yml
ansible-vault view roles/mysql-setup/vars/main.yml
```

**Best practices:**
- ✅ Simpan `.vault_pass` di `.gitignore`
- ✅ Gunakan `vault-edit` untuk edit encrypted files
- ✅ Encrypt semua credentials, tokens, passwords
- ✅ Share vault password securely dengan team (1Password, LastPass, etc)
- ❌ Jangan commit `.vault_pass` ke git
- ❌ Jangan commit unencrypted credentials

## 🔧 Update Script

Semua aplikasi yang di-deploy mendapatkan automatic update script.

**Lokasi:** `roles/common/files/update.sh`

**Features:**
- ✅ Auto login ke GitHub Container Registry
- ✅ Pull latest Docker image
- ✅ Recreate containers dengan zero-downtime
- ✅ Cleanup unused images
- ✅ Comprehensive logging ke `/var/log/docker-updates/`
- ✅ Error handling dan exit codes
- ✅ Color output untuk readability
- ✅ Configurable via environment variables

**Usage:**
```bash
# Manual update
ssh root@your-server
cd /opt/docker-stack/applications/materi-ku
./update.sh

# Otomatis via cron (opsional)
# Add to crontab:
# 0 2 * * * /opt/docker-stack/applications/materi-ku/update.sh >> /var/log/docker-updates/cron.log 2>&1
```

**Configuration:**
Edit variabel di `update.sh`:
```bash
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
DOCKER_PASSWORD_FILE="${DOCKER_PASSWORD_FILE:-/opt/docker-stack/docker-password.txt}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-ghcr.io}"
DOCKER_REGISTRY_USER="${DOCKER_REGISTRY_USER:-alfian57}"
```

## 🆕 Deploying New Applications

### Quick Start Guide

Untuk deploy aplikasi baru (React, Next.js, Express, Golang, Laravel):

1. **Buat role baru:**
```bash
mkdir -p roles/my-new-app-setup/{tasks,files,vars,defaults}
```

2. **Buat `tasks/main.yml`:**
```yaml
---
- name: Deploy My New App
  ansible.builtin.include_tasks: ../../common/tasks/deploy-react-app.yml
  vars:
    app_name: "my-new-app"
    app_port: 3000  # optional, defaults per stack
```

3. **Buat files yang diperlukan:**
   - `files/docker-compose.yml` - Docker compose configuration
   - `files/.env` - Environment variables (encrypt dengan vault!)

4. **Update playbook:**
```yaml
# playbooks/server-setup.yml
roles:
  - role: my-new-app-setup
    tags: [application, my-new-app-setup]
```

5. **Deploy:**
```bash
make check
make redeploy-app APP=my-new-app
```

**Dokumentasi lengkap:**
- `roles/common/APPLICATION_TEMPLATE.md` - Step-by-step guide
- `roles/common/DOCKER_COMPOSE_TEMPLATES.md` - Docker compose examples
- `roles/common/README.md` - Shared tasks documentation

## 🐛 Troubleshooting

### Connection Issues
```bash
# Test basic connectivity
make ping

# Verbose SSH
ssh -vvv root@your-server

# Check firewall
ansible all -i inventory/hosts.ini -m shell -a "ufw status"
```

### Syntax Errors
```bash
# Check playbook syntax
make check

# Lint for best practices
make lint
```

### Container Issues
```bash
# Check running containers
make server-info

# View container logs
ssh root@your-server
docker logs materi-ku
docker logs --tail 100 -f mysql
```

### Vault Issues
```bash
# Create vault password
make vault-create-pass

# Verify vault can decrypt
make vault-view FILE=roles/users-setup/vars/main.yml
```

### Debug Mode
```bash
# Run with verbose output
make setup-verbose

# Dry run (no changes)
make setup-dry-run

# Step through tasks
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --step
```

## 📊 Project Statistics

- **Total Roles:** 14 (4 system + 3 infrastructure + 3 database + 4 applications)
- **Shared Task Templates:** 5 (Laravel, React, Next.js, Express, Golang)
- **Makefile Commands:** 50+
- **Code Reduction:** 95% per application role (76 lines → 4 lines)
- **Security Fixes:** 5 critical vulnerabilities fixed
- **Supported Tech Stacks:** 5 different stacks
- **Lines of Documentation:** 1500+ across all docs

## 🔐 Security Best Practices

1. **Always use Ansible Vault** untuk credentials
2. **Never commit** `.vault_pass` atau unencrypted credentials
3. **Use SSH keys** instead of passwords
4. **Restrict file permissions** (0600 untuk sensitive files)
5. **Regular updates** dengan `make update-apt`
6. **Monitor logs** di `/var/log/docker-updates/`
7. **Use strong passwords** untuk vault dan databases
8. **Limit SSH access** dengan firewall rules
9. **Enable fail2ban** untuk SSH protection
10. **Regular backups** untuk databases dan volumes

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Run lint: `make lint`
4. Test changes: `make setup-dry-run`
5. Commit: `git commit -m 'Add amazing feature'`
6. Push: `git push origin feature/amazing-feature`
7. Create Pull Request

## 📚 Additional Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Docker Documentation](https://docs.docker.com/)
- [Makefile Tutorial](https://makefiletutorial.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Ansible Vault Guide](https://docs.ansible.com/ansible/latest/user_guide/vault.html)

## 📝 License

SPDX-License-Identifier: MIT-0

## 👤 Author

**Alfian Gading Saputra** ([@Alfian57](https://github.com/Alfian57))

---

**Last Updated:** November 2025

**Need help?** Check `MAKEFILE_GUIDE.md` for detailed command documentation.
