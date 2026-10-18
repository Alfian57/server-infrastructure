# Project: Server Infrastructure Modernization & Refactoring

## Architecture
- **Ansible Automation & Orchestration**:
  - `playbooks/server-setup.yml`: Master playbook executing roles in ordered lifecycle stages (system setup, security hardening, infrastructure, databases, applications, optimization).
  - `group_vars/all/apps.yml`: Central application catalog and single source of truth for app metadata, domain mappings, container images, deployment definitions, database attachments, environment contracts, and CI credentials.
  - `group_vars/all/vars.yml` & `vault.yml`: Non-sensitive shared variables and AES-256 encrypted production credentials.
- **Reverse Proxy & Domain Routing**:
  - `roles/infrastructure/nginx-proxy-setup/`: Nginx Proxy Manager (NPM) automating virtual host routing, SSL termination, and Cloudflare DNS-01 ACME challenges.
  - Multi-domain routing: Native support for multiple domains per application via NPM `domain_names` API payload.
- **DNS Automation**:
  - `scripts/update-cloudflare-dns-local.sh`: Multi-zone Cloudflare DNS synchronizer that aligns active catalog domains across 4 zones (`alfian-gading.my.id`, `aldera.tech`, `ruang-tenang.my.id`, `sistertika.com`) and prunes obsolete `A`/`CNAME` records while strictly safeguarding non-HTTP records (`MX`, `TXT`, `SRV`).
- **Container Infrastructure & System**:
  - `roles/infrastructure/docker-setup/`: Unified Docker daemon configuration (`daemon.json.j2`) managing logging rotation, storage drivers, live-restore, and security parameters.
  - `roles/applications/portfolio-apps/`: Consolidated portfolio application deployment managing compose execution and templated `.env` generation.
- **Aldera Multi-Stack Staging Architecture (VPS 45.66.153.149)**:
  - `deploy-aldera-router-staging.yml`: Dedicated playbook deploying isolated staging router stack (`/opt/docker-stack/applications/aldera-router-staging`) with bot `@aldera_tech_staging_bot`, database `aldera_router_staging`, and isolated network `aldera_router_staging_internal`.
  - `deploy-aldera-web-staging.yml`: Dedicated playbook deploying isolated staging web application (`/opt/docker-stack/applications/aldera-tech-staging`) for `staging.aldera.tech` with database `aldera_tech_staging`.
  - Token Mappings:
    * Production Bot `@aldera_tech_bot`: `vault_aldera_router_bot_token` (`[REDACTED_IN_VAULT]`)
    * Staging Bot `@aldera_tech_staging_bot`: `vault_aldera_router_staging_bot_token` (`[REDACTED_IN_VAULT]`)
  - Zero-Downtime Isolation: Staging containers use dedicated network bridges and do not bind conflicting aliases on `nginx_proxy_manager_network`.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | File Pod API `.env` Removal | Remove static `roles/applications/file-pod-api-setup/files/.env` | M1 | ORIGINAL_REQUEST R5 |
| 2 | Redundant Docker Compose Cleanup | Remove redundant static `files/docker-compose.yml` in mysql, postgres, redis, and autoheal | M1 | ORIGINAL_REQUEST R5 |
| 3 | Empty `vars/main.yml` Elimination | Remove 0-byte `vars/main.yml` across 7 roles; migrate `nginx-proxy-setup` vars to defaults | M1 | ORIGINAL_REQUEST R5 |
| 4 | Orphaned Application Roles Consolidation | Move 5 standalone `.env.j2` to `portfolio-apps/templates/` and delete empty role folders | M1 | ORIGINAL_REQUEST R5 |
| 5 | Docker Daemon Consolidation | Create single `roles/infrastructure/docker-setup/templates/daemon.json.j2` unifying security & logging | M1 | ORIGINAL_REQUEST R6 |
| 6 | Swap Role Parameterization & Lint Fix | Add `defaults/main.yml`, `meta/main.yml`, and canonical `ansible.posix.mount` to `swap-setup` | M1 | ORIGINAL_REQUEST R6 |
| 7 | Aldera Tech Catalog Rebrand | Update `apps.yml` for Aldera Tech (`aldera`), image `alderatech/aldera-tech`, repo `AlderaTech/aldera-tech`, domain `aldera.tech` | M2 | ORIGINAL_REQUEST R1 |
| 8 | AlderaTech Repositories Migration | Update repo owner and image URLs to `AlderaTech` for web & mobile apps | M2 | ORIGINAL_REQUEST R1 |
| 9 | Ruang Tenang Dedicated Domains | Map Web to `ruang-tenang.my.id` and API to `api.ruang-tenang.my.id`, removing obsolete subdomains | M2 | ORIGINAL_REQUEST R2 |
| 10 | Sistertika UTY Dual-Domain Routing | Configure concurrent dual-domain routing (`alfian-gading.my.id` & `sistertika.com`) across proxy and CORS | M2 | ORIGINAL_REQUEST R2 |
| 11 | Environment Contracts & Secret Mapping | Fix contract drift (`SHARP_IGNORE_GLOBAL_LIBVIPS`, `BACKUP_DIR`, `DB_SSLMODE`) and map `NEXT_PUBLIC_API_URL` | M2 | ORIGINAL_REQUEST R4 |
| 12 | Multi-Zone DNS Catalog Support | Update `scripts/app-catalog.py` to parse multi-zone and list-based `dns` entries cleanly | M3 | ORIGINAL_REQUEST R2 |
| 13 | Cloudflare Multi-Zone Sync & Pruning | Modernize `scripts/update-cloudflare-dns-local.sh` for multi-zone pagination, `--dry-run`, and safe pruning | M3 | ORIGINAL_REQUEST R3 |
| 14 | Non-HTTP Record Safeguarding | Implement 3-layer safeguard protecting `MX`, `TXT`, `SPF`, `DKIM`, and `SRV` records from pruning | M3 | ORIGINAL_REQUEST R3 |
| 15 | Cloud Services Checker Modernization | Update `scripts/check-cloud-services.sh` pagination and obsolete record reporting | M3 | ORIGINAL_REQUEST R3 |
| 16 | GitHub Actions CI/CD Pipeline | Add `.github/workflows/lint-and-audit.yml` running syntax-check, lint, shell-check, doctor, env-check | M4 | ORIGINAL_REQUEST R7 |
| 17 | Controlled Operations & Acceptance Validation | End-to-end acceptance validation across all R1-R8 criteria preserving secrets integrity | M4 | ORIGINAL_REQUEST R8 |
| 18 | Aldera Staging Router Multi-Stack | Dedicated playbook `deploy-aldera-router-staging.yml`, token mapping, isolated DB `aldera_router_staging` | M5 | Spec Miner R1 |
| 19 | Aldera Staging Web Multi-Stack | Dedicated playbook `deploy-aldera-web-staging.yml`, domain `staging.aldera.tech`, isolated DB `aldera_tech_staging` | M5 | Spec Miner R1 |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Codebase Hygiene, Docker Consolidation & Swap Setup | R5, R6 (Features 1-6): Static files cleanup, role consolidation, daemon.json.j2, swap-setup meta/defaults & mount lint fix | none | DONE |
| M2 | App Catalog Modernization, Rebranding & Multi-Domain Routing | R1, R2, R4 (Features 7-11): AlderaTech rebrand, repo migration, Ruang Tenang dedicated domains, Sistertika dual routing, contract sync | M1 | IN_PROGRESS |
| M3 | Cloudflare DNS Multi-Zone Synchronization & Record Pruning | R3 (Features 12-15): app-catalog.py multi-zone parsing, update-cloudflare-dns-local.sh multi-zone sync, safe record pruning, non-HTTP safeguard | M2 | PLANNED |
| M4 | GitHub Actions CI/CD Pipeline & Acceptance Validation | R7, R8 (Features 16-17): .github/workflows/lint-and-audit.yml, automated verification suite (make check, make lint, make shell-check, doctor, env-check, dns dry-run) | M3 | PLANNED |
| M5 | Multi-Stack Staging Architecture & Dual-Bot Deployment | Features 18-19: Dedicated staging playbooks, isolated container networks, dual-bot credentials | M1 | IN_PROGRESS |

---

## Interface Contracts

### 1. `group_vars/all/apps.yml` ↔ `roles/applications/portfolio-apps/`
- `env_template`: Relative path from repository root, e.g. `roles/applications/portfolio-apps/templates/<app>.env.j2`.
- `portfolio-apps/tasks/deploy-one.yml` resolves:
  `src: "{{ playbook_dir }}/../{{ app_env_template }}"`
- `scripts/app-catalog.py` verifies existence and git tracking of `PROJECT_DIR / env_template`.

### 2. `group_vars/all/apps.yml` ↔ `roles/infrastructure/nginx-proxy-setup/`
- Multi-domain routing:
  ```yaml
  proxy:
    domain: "sistertika.alfian-gading.my.id" # primary
    domains:
      - "sistertika.alfian-gading.my.id"
      - "sistertika.com"
  ```
- Nginx Proxy Manager task payload:
  `domain_names: "{{ target_domains }}"` where `target_domains` is derived from `item.domains` (if defined), otherwise `[item.domain]`.
- Nginx configuration template (`cloudflare_proxy_host.conf.j2`):
  `server_name {{ target_domains | default([target_domain]) | join(' ') }};`

### 3. `group_vars/all/apps.yml` ↔ `scripts/app-catalog.py` ↔ `scripts/update-cloudflare-dns-local.sh`
- DNS configuration in `apps.yml`:
  ```yaml
  # Single zone
  dns:
    domain: "aldera.tech"
    records: ["@"]

  # Multi-zone
  dns:
    - domain: "alfian-gading.my.id"
      records: ["sistertika"]
    - domain: "sistertika.com"
      records: ["@"]
  ```
- `scripts/app-catalog.py domains-shell` normalization:
  Accepts either a dict or list of dicts. Emits lines in format:
  `<domain>:<record1> <record2> ...`
- `scripts/update-cloudflare-dns-local.sh`:
  Reads each line, resolves Cloudflare Zone ID, syncs desired records, and prunes obsolete `A`/`CNAME` records while safeguarding non-HTTP records.

---

## Code Layout
```
/home/alfiang/Projects/server-infra-with-ansible/
├── .github/
│   └── workflows/
│       └── lint-and-audit.yml             # M4: CI/CD workflow
├── group_vars/
│   └── all/
│       ├── apps.yml                       # M1/M2: Application catalog & domain configs
│       ├── vars.yml                       # Non-sensitive variables
│       └── vault.yml                      # Encrypted secrets
├── playbooks/
│   └── server-setup.yml                   # Master setup playbook
├── roles/
│   ├── applications/
│   │   ├── file-pod-api-setup/            # M1: Static files/.env removed
│   │   └── portfolio-apps/
│   │       └── templates/
│   │           ├── aldera.env.j2          # M1/M2: Consolidated templates
│   │           ├── lelang-fashion-web.env.j2
│   │           ├── location-based-presence-web.env.j2
│   │           ├── pos-soto-saben.env.j2
│   │           ├── sistertika-uty-api.env.j2
│   │           └── sistertika-uty-web.env.j2
│   ├── databases/
│   │   ├── mysql-setup/                   # M1: files/compose & vars/main.yml removed
│   │   ├── postgres-setup/                # M1: files/compose & vars/main.yml removed
│   │   └── redis-setup/                   # M1: files/compose & vars/main.yml removed
│   ├── infrastructure/
│   │   ├── autoheal-setup/                # M1: files/compose removed
│   │   ├── docker-setup/
│   │   │   └── templates/
│   │   │       └── daemon.json.j2         # M1: Unified daemon template
│   │   └── nginx-proxy-setup/             # M1/M2: defaults/main.yml, multi-domain routing
│   └── system/
│       ├── swap-setup/                    # M1: defaults/main.yml, meta/main.yml, mount fix
│       └── update-apt/                    # M1: vars/main.yml removed
├── scripts/
│   ├── app-catalog.py                     # M2/M3: Multi-zone & list-based dns parsing
│   ├── check-cloud-services.sh            # M3: Pagination & obsolete record warnings
│   ├── config.sh                          # Helper functions & domain loader
│   ├── env-contracts.py                   # Contract verification
│   ├── repo-audit.py                      # Repository audit verification
│   └── update-cloudflare-dns-local.sh     # M3: Multi-zone sync & safe record pruning
└── Makefile                               # M1/M2/M3/M4: Automated verification targets
```
