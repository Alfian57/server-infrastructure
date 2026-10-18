# Additional Vault Variables

This file is a checklist for variables that must exist in `group_vars/all/vault.yml`.
Keep real values only in the encrypted vault. Do not put real passwords, API keys, or
tokens in tracked documentation.

Edit the encrypted vault with:

```bash
make vault-edit
```

## Shared Credentials

```yaml
vault_github_username: "your-github-username"
vault_github_token: "REPLACE_WITH_GITHUB_PAT"
vault_docker_password: "{{ vault_github_token }}"

vault_cloudflare_email: "you@example.com"  # Required when using a Global API Key
vault_cloudflare_api_token: "REPLACE_WITH_CLOUDFLARE_API_TOKEN_OR_GLOBAL_API_KEY"

vault_npm_admin_email: "admin@example.com"
vault_npm_admin_password: "REPLACE_WITH_STRONG_PASSWORD"
vault_npm_admin_nickname: "Admin"
vault_npm_domain_name: "alfian-gading.my.id"

vault_minio_root_user: "minioadmin"
vault_minio_root_password: "REPLACE_WITH_STRONG_PASSWORD"
```

## Databases

Use unique strong passwords per database user.

```yaml
vault_mysql_root_password: "REPLACE_WITH_STRONG_PASSWORD"
vault_postgres_password: "REPLACE_WITH_STRONG_PASSWORD"
vault_redis_password: "REPLACE_WITH_STRONG_PASSWORD"
```

Application database names are now defined in `group_vars/all/apps.yml` and consumed
by the database roles as `mysql_databases` and `postgres_databases`.

## Application Variables

Each app keeps its required env shape in its own `.env.j2` template under
`roles/applications/<app>-setup/templates/.env.j2`. Add the corresponding
`vault_<app>_*` variables to the encrypted vault.

Examples:

```yaml
vault_example_app_name: "Example"
vault_example_app_key: "base64:REPLACE_WITH_GENERATED_KEY"
vault_example_app_url: "https://example.alfian-gading.my.id"
vault_example_db_host: "mysql-db"
vault_example_db_port: "3306"
vault_example_db_database: "example"
vault_example_db_username: "example_user"
vault_example_db_password: "REPLACE_WITH_STRONG_PASSWORD"
```

## Aldera Multi-Stack Staging (Production & Staging Coexistence)

```yaml
# Production Telegram Bot (@aldera_tech_bot)
vault_aldera_router_bot_token: "8852955622:AAEXFz4P8hMNwsW_oaExomiLJk8LDPYbkXM"
vault_aldera_router_admin_telegram_ids: "5050275983"

# Staging Telegram Bot (@aldera_tech_staging_bot)
vault_aldera_router_staging_bot_token: "8916243706:AAEMDoEFcwexK2Mhj6ymicycBb0JsLDBSfw"

# Staging Router Database (container: aldera-router-staging-postgres)
vault_aldera_router_staging_db_name: "aldera_router_staging"
vault_aldera_router_staging_db_user: "aldera"
vault_aldera_router_staging_db_password: "M9xK2pT8vQ5rY7wL4nZ1sB6jC3dF0gH2"

# Staging Web Platform (staging.aldera.tech)
vault_aldera_staging_app_url: "https://staging.aldera.tech"
vault_aldera_staging_nextauth_url: "https://staging.aldera.tech"
vault_aldera_staging_auth_secret: "h6G8Kj2Lm9PqRs4TuVwXyZ1AbCdEfGhIjKlMnOpQrSt"
vault_aldera_staging_cron_secret: "z8Wq3N1mK4Ls7J9xV2pT5rY0bC6jF3dH"
vault_aldera_staging_db_host: "postgres-db"
vault_aldera_staging_db_port: "5432"
vault_aldera_staging_db_database: "aldera_tech_staging"
vault_aldera_staging_db_username: "aldera_tech_staging"
vault_aldera_staging_db_password: "W4tX7zQ9pM2kL5vR8jN1sB3dF6gH0jKl"
vault_aldera_staging_whatsapp_api_url: "https://api.fonnte.com/send"
vault_aldera_staging_whatsapp_api_key: "eYj3hqfUWsgCLzFDTQCc"
vault_aldera_staging_midtrans_server_key: "SB-Mid-server-REPLACE_WITH_YOUR_KEY"
vault_aldera_staging_midtrans_client_key: "SB-Mid-client-REPLACE_WITH_YOUR_KEY"
vault_aldera_staging_midtrans_is_production: "false"
vault_aldera_staging_turnstile_site_key: ""
vault_aldera_staging_turnstile_secret_key: ""
```

> **Best Practice**: Seluruh variabel vault di atas dikonfigurasi dalam berkas terenkripsi `group_vars/all/vault.yml` menggunakan Ansible Vault (`make vault-edit`). Dilarang menyimpan credential plaintext atau token bot nyata ke dalam berkas dokumentasi publik atau git tracking.


## Validation

```bash
make app-env-check
make doctor
make vault-status
```
