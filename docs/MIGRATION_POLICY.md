# Migration And Seeder Policy

Production deploys must run forward-only migrations by default. Rollbacks and database resets are operational actions, not normal deploy behavior.

## Defaults

| Stack | Deploy migration | Runtime migration env | Seeder default |
| --- | --- | --- | --- |
| Laravel | `php artisan migrate --force` from Ansible | Disabled unless the app image has its own unrelated env | Only on fresh DB or explicit `seed_on: always` |
| Express + Prisma | `npx prisma migrate deploy` from Ansible when `run_migrate: true` | `RUN_MIGRATE=false` | Manual unless explicitly configured |
| Go + golang-migrate | `./migrate up` from Ansible only when `run_migrate: true` | `RUN_MIGRATE=false` | Manual unless explicitly configured |
| Raw SQL demo seed | Manual by default, or explicit `mysql_seed_on: always` | Not applicable | App-specific |

## Rules

- Use `migrate up` / `php artisan migrate` / `prisma migrate deploy` for normal production deploys.
- Do not run `migrate down` automatically during deploy. If a rollback needs schema changes, make a new forward migration that restores compatibility.
- Use `migrate:fresh`, `migrate fresh`, or destructive SQL only on disposable/demo databases or with `confirm_destroy_data=yes`.
- Seeders should be idempotent before they are allowed to run repeatedly with `seed_on: always`.
- Demo/reference data seeders should generally use `seed_on: fresh` so they only run on a new database.
- Container entrypoints should not run migrations on every restart. Use `runtime_migrate: true` only for apps where that behavior is explicitly intended.

## Catalog Fields

- `run_migrate`: run the stack-specific forward migration from Ansible.
- `run_fresh_migrate`: run a destructive reset migration. Requires `confirm_destroy_data=yes`.
- `run_seeder`: allow seeders for the app.
- `seed_on`: `fresh`, `always`, or `manual`.
- `runtime_migrate`, `runtime_fresh_migrate`, `runtime_seeder`: pass migration/seeder flags into the container runtime. These default to false.
- `run_mysql_seed`: render and execute an app-specific SQL seed.
- `mysql_seed_on`: `always` or `manual`.
