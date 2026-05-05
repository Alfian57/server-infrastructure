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

## Validation

```bash
make app-env-check
make doctor
make vault-status
```
