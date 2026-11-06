# Migration And Seeder Policy

The `production` boolean in each application catalog entry is the source of truth for database safety. It is independent of `.env`, `NODE_ENV`, and `APP_ENV`; changing one does not change the others.

Production deploys use forward-only migrations by default. A normal deploy never resets a database based only on the `production` value. For an enabled application with `production: false`, use `make infra ACTION=reset-db APP=<app>` when a disposable database must be recreated. That explicit action checks ownership, drops only the application's recorded database claims, provisions the catalog targets, then deploys the selected application to apply schema setup and available seeders.

`ACTION=reset-db` refuses production applications, disabled applications, applications without declared databases, shared/system databases, and existing databases without a verified owner. It does not remove application volumes or shared database services. Production database resets require an owner-approved operational path outside this action.

## Defaults

| Stack | Deploy migration | Runtime migration env | Seeder default |
| --- | --- | --- | --- |
| Laravel | `php artisan migrate --force` from Ansible | Disabled unless the app image has its own unrelated env | Only on fresh DB or explicit `seed_on: always` |
| Express + Prisma | `npx prisma migrate deploy` from Ansible when `run_migrate: true` | `RUN_MIGRATE=false` | Manual unless explicitly configured |
| Go + golang-migrate | `./migrate up` from Ansible only when `run_migrate: true` | `RUN_MIGRATE=false` | Manual unless explicitly configured |
| Raw SQL demo seed | Manual by default, or explicit `mysql_seed_on: always` | Not applicable | App-specific |

## Rules

- Use `migrate up` / `php artisan migrate` / `prisma migrate deploy` for normal deploys.
- Do not run `migrate down` automatically during deploy. If a rollback needs schema changes, make a new forward migration that restores compatibility.
- Use `migrate:fresh`, `migrate fresh`, or destructive SQL only through the explicit `reset-db` action for an enabled `production: false` application, or through a separately owner-approved production procedure.
- Seeders should be idempotent before they are allowed to run repeatedly with `seed_on: always`.
- `reset-db` runs the application's available seeder once after database recreation, even when normal deployments do not seed.
- Demo/reference data seeders should generally use `seed_on: fresh` so normal deployments seed only a new database.
- Container entrypoints should not run migrations on every restart. Use `runtime_migrate: true` only for apps where that behavior is explicitly intended.

## Catalog Fields

- `run_migrate`: run the stack-specific forward migration from Ansible.
- `run_fresh_migrate`: run a destructive reset migration during a normal deployment. Keep false unless that behavior is specifically intended; `ACTION=reset-db` explicitly enables fresh initialization for its one selected application.
- `run_seeder`: allow seeders for the app.
- `seed_on`: `fresh`, `always`, or `manual`.
- `runtime_migrate`, `runtime_fresh_migrate`, `runtime_seeder`: pass migration/seeder flags into the container runtime. These default to false.
- `run_mysql_seed`: render and execute an app-specific SQL seed.
- `mysql_seed_on`: `always` or `manual`.
