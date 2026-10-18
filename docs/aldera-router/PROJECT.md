# Project: AI API Relay Platform

## Architecture
The AI API Relay Platform consists of five cooperating components organized into a secure, containerized architecture:

```
[ Client / Developer ] (OpenAI SDK, Cursor, Cline, OpenWebUI)
         │  Authorization: Bearer sk-toko-...
         ▼
[ Nginx Proxy Manager ] (api.aldera.tech -> billing-proxy:8080)
         │
         ▼
[ billing-proxy ] (Go chi, pgxpool, tiktoken, decimal)
   ├── Auth & Cache (SHA-256 API Key verification)
   ├── Concurrency Guard (Pre-flight check + Atomic deduction)
   ├── Stream Relay (SSE streaming with http.Flusher + fallback token estimator)
   └── Dynamic Pricing (Per-model rate calculation via NUMERIC(16,4))
         │                              │
         ├──────────────────┐           │ Internal Docker Network (aldera_router_internal)
         ▼                  ▼           ▼
[ PostgreSQL ]        [ 9router Upstream ] (decolua/9router:latest :20128)
(Users, Keys, Pricing,     │ (OAuth tokens, Provider connections)
 Usage, Topups, Ledger)     │
         ▲                  │ (NPM Basic Auth -> router.aldera.tech)
         │                  ▼
[ router-telegram-bot ] (Python 3.12, aiogram v3, asyncpg)
   ├── User Services (/start, /apikey, /saldo, /harga, /topup, /cara_pakai)
   ├── Admin Console (/addsaldo, /stats, /setprice, AdminFilter)
   └── Anti-Double-Approve Engine (Row lock idempotency on topup requests)
```

Deployment and lifecycle management are automated via Ansible (`roles/applications/aldera-router-setup` in `server-infra-with-ansible`) and Docker Compose.

### Multi-Stack Staging Architecture (VPS 45.66.153.149)

The platform runs two completely isolated multi-stack environments side-by-side on VPS `45.66.153.149`:

- **Production Stack (`main`)**:
  - Directory: `/opt/docker-stack/applications/aldera-router`
  - Bot: `@aldera_tech_bot` (Token: `8852955622:AAEXFz4P8hMNwsW_oaExomiLJk8LDPYbkXM`)
  - Database: `aldera_router` (in `aldera-router-postgres`)
  - Internal Network: `aldera_router_internal`
  - Playbook: `playbooks/server-setup.yml`
- **Staging Stack (`staging`)**:
  - Directory: `/opt/docker-stack/applications/aldera-router-staging`
  - Bot: `@aldera_tech_staging_bot` (Token: `8916243706:AAEMDoEFcwexK2Mhj6ymicycBb0JsLDBSfw`)
  - Database: `aldera_router_staging` (in `aldera-router-staging-postgres`)
  - Internal Network: `aldera_router_staging_internal` (strictly isolated)
  - Playbook: `deploy-aldera-router-staging.yml`

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | R1.1 Healthcheck | Endpoint `/healthz` returns HTTP 200 OK | M2 | ORIGINAL_REQUEST §R1 |
| 2 | R1.2 Models Discovery | Endpoint `/v1/models` returns active models list from PostgreSQL | M2 | ORIGINAL_REQUEST §R1 |
| 3 | R1.3 Chat Completions | OpenAI-compatible `/v1/chat/completions` proxy with auth and billing | M2 | ORIGINAL_REQUEST §R1 |
| 4 | R1.4 Messages API | Anthropic-compatible `/v1/messages` endpoint proxying | M2 | ORIGINAL_REQUEST §R1 |
| 5 | R1.5 Virtual API Key Auth | Validates `sk-toko-...` keys via SHA-256 hash lookup with thread-safe TTL cache | M2 | ORIGINAL_REQUEST §R1 |
| 6 | R1.6 Pre-flight Balance Guard | Rejects requests with HTTP 402 if balance < MIN_BALANCE_THRESHOLD (Rp 500) | M2 | ORIGINAL_REQUEST §R1 |
| 7 | R1.7 Upstream Request Rewriter | Injects `stream_options: {"include_usage": true}` into upstream requests | M2 | ORIGINAL_REQUEST §R1 |
| 8 | R1.8 Low-Latency SSE Relay | Streams SSE chunks with realtime flushing (`http.Flusher`) | M2 | ORIGINAL_REQUEST §R1 |
| 9 | R1.9 Fallback Token Estimator | Estimates token counts on client disconnect or missing upstream usage chunks | M2 | ORIGINAL_REQUEST §R1 |
| 10 | R1.10 Atomic Balance Deduction | `UPDATE users SET balance = balance - $cost` + ledger insert in single transaction | M2 | ORIGINAL_REQUEST §R1 |
| 11 | R1.11 Dynamic Pricing Math | Calculates token cost per 1M tokens with exact `decimal` precision | M2 | ORIGINAL_REQUEST §R1 |
| 12 | R1.12 Proxy Containerization | Multi-stage Dockerfile, non-root user, healthcheck integration | M2 | ORIGINAL_REQUEST §R1 |
| 13 | R2.1 Bot Registration | Command `/start` auto-registers user by Telegram ID | M3 | ORIGINAL_REQUEST §R2 |
| 14 | R2.2 Key Management | Command `/apikey` displays active key or generates new `sk-toko-...` key | M3 | ORIGINAL_REQUEST §R2 |
| 15 | R2.3 Balance & Usage | Command `/saldo` displays IDR balance and token consumption statistics | M3 | ORIGINAL_REQUEST §R2 |
| 16 | R2.4 Pricing Catalog | Command `/harga` presents cleanly formatted pricing per 1M tokens | M3 | ORIGINAL_REQUEST §R2 |
| 17 | R2.5 Topup Ticket Flow | Command `/topup [nominal]` creates ticket with 3-digit unique code & payment info | M3 | ORIGINAL_REQUEST §R2 |
| 18 | R2.6 Receipt Upload | Handles transfer receipt photo upload and associates with pending ticket | M3 | ORIGINAL_REQUEST §R2 |
| 19 | R2.7 Integration Guides | Command `/cara_pakai` guides integration for Cursor, Cline, Roo Code, OpenWebUI | M3 | ORIGINAL_REQUEST §R2 |
| 20 | R2.8 Admin Approval Alerts | Forwards receipt photo to admin with Inline Approve/Reject buttons | M3 | ORIGINAL_REQUEST §R2 |
| 21 | R2.9 Idempotent Approval | Anti-double-approve engine via `SELECT ... FOR UPDATE` row locks | M3 | ORIGINAL_REQUEST §R2 |
| 22 | R2.10 Admin Balance Adjust | Command `/addsaldo [telegram_id] [nominal]` with audit ledger entry | M3 | ORIGINAL_REQUEST §R2 |
| 23 | R2.11 Admin Metrics | Command `/stats` reports total users, today's token volume, and estimated revenue | M3 | ORIGINAL_REQUEST §R2 |
| 24 | R2.12 Admin Price Update | Command `/setprice [model] [input] [output]` updates model selling prices | M3 | ORIGINAL_REQUEST §R2 |
| 25 | R2.13 Admin Security Filter | Restricts admin commands and callbacks strictly to `ADMIN_TELEGRAM_ID` | M3 | ORIGINAL_REQUEST §R2 |
| 26 | R2.14 Bot Containerization | Python 3.12 Dockerfile, non-root user, proper signal handling | M3 | ORIGINAL_REQUEST §R2 |
| 27 | R3.1 PostgreSQL Monetary DDL | All monetary columns defined as `NUMERIC(16, 4)` | M1 | ORIGINAL_REQUEST §R3 |
| 28 | R3.2 Users Table & Constraint | `users` table with non-negative check constraint `CHECK (balance >= 0.0000)` | M1 | ORIGINAL_REQUEST §R3 |
| 29 | R3.3 API Keys Table | `api_keys` storing `key_hash` (SHA-256), `key_prefix`, label, active status | M1 | ORIGINAL_REQUEST §R3 |
| 30 | R3.4 Model Pricing Table | `model_pricing` storing input/output rates per 1M tokens | M1 | ORIGINAL_REQUEST §R3 |
| 31 | R3.5 Usage Logs Table | `usage_logs` tracking prompt/completion tokens, latency, cost, and streaming | M1 | ORIGINAL_REQUEST §R3 |
| 32 | R3.6 Topup Requests Table | `topup_requests` tracking unique code, transfer amount, proof ID, status | M1 | ORIGINAL_REQUEST §R3 |
| 33 | R3.7 Balance Audit Ledger | `balance_transactions` table recording all balance mutations with balance before/after | M1 | ORIGINAL_REQUEST §R3 |
| 34 | R3.8 9router Network Isolation | Upstream 9router isolated in internal Docker network without exposed host ports | M1 | ORIGINAL_REQUEST §R3 |
| 35 | R4.1 Ansible Deployment Role | `roles/applications/aldera-router-setup` in `server-infra-with-ansible` | M4 | ORIGINAL_REQUEST §R4 |
| 36 | R4.2 Docker Compose Template | `docker-compose.yml.j2` defining 9router, billing-proxy, telegram-bot, postgres | M4 | ORIGINAL_REQUEST §R4 |
| 37 | R4.3 Environment Template | `.env.j2` with vault variable structure and secrets | M4 | ORIGINAL_REQUEST §R4 |
| 38 | R4.4 Persistent Volume Setup | Persistent Docker volumes for 9router data and PostgreSQL data | M4 | ORIGINAL_REQUEST §R4 |
| 39 | R4.5 NPM Reverse Proxy Setup | Nginx Proxy Manager configs for `api.aldera.tech` (public) & `router.aldera.tech` (auth) | M4 | ORIGINAL_REQUEST §R4 |
| 40 | R4.6 Verification Harness | `verify-relay.sh` end-to-end automated verification script | M4 | ORIGINAL_REQUEST §R4 |
| 41 | AC.1 Healthz Check | `/healthz` returns 200 OK | M2, M5 | Acceptance Criteria |
| 42 | AC.2 Models Check | `/v1/models` returns active models from DB | M2, M5 | Acceptance Criteria |
| 43 | AC.3 Auth 401 Check | Missing or invalid API key returns 401 Unauthorized | M2, M5 | Acceptance Criteria |
| 44 | AC.4 Balance 402 Check | Balance below threshold returns 402 Payment Required | M2, M5 | Acceptance Criteria |
| 45 | AC.5 Non-streaming Billing | Accurate balance deduction for non-streaming completions | M2, M5 | Acceptance Criteria |
| 46 | AC.6 Streaming Billing | Realtime SSE delivery & accurate balance deduction upon stream completion | M2, M5 | Acceptance Criteria |
| 47 | AC.7 Race Condition Protection | 10 concurrent requests with low balance never produce negative balance | M2, M5 | Acceptance Criteria |
| 48 | AC.8 Bot User Registration | `/start` registers new user in DB | M3, M5 | Acceptance Criteria |
| 49 | AC.9 Bot Key Issuance | `/apikey` issues valid `sk-toko-...` key | M3, M5 | Acceptance Criteria |
| 50 | AC.10 Bot Topup Flow | `/topup 50000` generates unique code and prompts receipt | M3, M5 | Acceptance Criteria |
| 51 | AC.11 Idempotent Approval | Inline Approve credits balance, notifies user, rejects repeat clicks | M3, M5 | Acceptance Criteria |
| 52 | AC.12 Admin Authorization | `/addsaldo` & `/stats` rejected for non-admin users | M3, M5 | Acceptance Criteria |
| 53 | AC.13 Compose Syntax Validity | `docker compose config` syntax is valid | M4, M5 | Acceptance Criteria |
| 54 | AC.14 Ansible Syntax Check | `ansible-playbook --syntax-check` passes cleanly | M4, M5 | Acceptance Criteria |
| 55 | AC.15 End-to-End Verification | Full automated test suite and verification script passes | M5 | Acceptance Criteria |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Database Schema, Hardening & Audit Ledger | Features 27-34 (R3 DDL, constraints, audit ledger, seed data) | none | DONE |
| M2 | Billing & API Gateway Middleware (`billing-proxy`) | Features 1-12, 41-47 (Go chi, pgxpool, auth cache, SSE relay, atomic debit, tests) | M1 | IN_PROGRESS |
| M3 | Telegram Management Bot (`router-telegram-bot`) | Features 13-26, 48-52 (Python aiogram v3, user/admin handlers, idempotency, tests) | M1 | PLANNED |
| M4 | Ansible Automation & Deployment Orchestration | Features 35-40, 53-54 (`aldera-router-setup` role, templates, NPM configs, `verify-relay.sh`) | M1, M2, M3 | PLANNED |
| M5 | Final Integration & E2E Validation | Features 41-55 (Phase 1: 100% E2E test pass Tiers 1-4, Phase 2: Tier 5 adversarial hardening, Forensic Audit) | M1, M2, M3, M4, TEST_READY | PLANNED |

---

## Interface Contracts

### 1. Database ↔ `billing-proxy` and `router-telegram-bot`
- **Monetary Precision**: All balance, amount, and price fields must use PostgreSQL `NUMERIC(16, 4)`.
  - Go: `github.com/shopspring/decimal` (`decimal.Decimal`).
  - Python: `decimal.Decimal`.
- **API Key Format & Hashing**:
  - Plaintext: `sk-toko-` + 48 characters of `[a-zA-Z0-9]` (total length 56 chars).
  - Prefix: first 16 characters (`sk-toko-xxxxxxxx`).
  - Hash: SHA-256 lowercase hex digest (`sha256(raw_key)`). Stored in `api_keys.key_hash`. Plaintext is NEVER stored in database.
- **Negative Balance Invariant**:
  - Constraint: `users.balance` has DB check `CHECK (balance >= 0.0000)`.
  - Pre-flight check in Proxy: reject if `balance < MIN_BALANCE_THRESHOLD` (HTTP 402).
  - Atomic Deduction query:
    ```sql
    UPDATE users SET balance = balance - $cost, updated_at = NOW()
    WHERE id = $user_id AND balance >= $cost
    RETURNING balance;
    ```
- **Audit Ledger Contract**:
  - Every balance mutation (`usage`, `topup`, `manual_adjust`) MUST be accompanied by an atomic row in `balance_transactions`:
    ```sql
    INSERT INTO balance_transactions (user_id, amount, transaction_type, reference_id, balance_before, balance_after, notes)
    VALUES ($user_id, $amount, $type, $ref_id, $before, $after, $notes);
    ```
  - Invariant: `balance_after = balance_before + amount`.

### 2. `billing-proxy` ↔ Upstream `9router`
- Upstream address: `http://9router:20128` (internal Docker network `aldera_router_internal`).
- Endpoints proxied:
  - `POST /v1/chat/completions` -> upstream `POST /v1/chat/completions`
  - `GET /v1/models` -> local PostgreSQL query (active models) or upstream fallback
  - `POST /v1/messages` -> upstream `POST /v1/messages`
- Stream options injection: For all streaming requests (`stream: true`), `billing-proxy` ensures `stream_options.include_usage = true` is present in the forwarded JSON payload.
- Fallback token estimation: If upstream fails to return usage in the final SSE chunk or client disconnects early, `billing-proxy` invokes `tiktoken-go` fallback tokenizer.

### 3. Telegram Bot ↔ Topup Idempotency Contract
- Topup approval execution:
  ```sql
  BEGIN;
  SELECT id, user_id, amount, status FROM topup_requests WHERE id = $id FOR UPDATE;
  -- If status != 'pending', ROLLBACK and return "Ticket already processed"
  -- If status == 'pending':
  UPDATE users SET balance = balance + $amount WHERE id = $user_id RETURNING balance;
  INSERT INTO balance_transactions (...);
  UPDATE topup_requests SET status = 'approved', admin_id = $admin_id, approved_at = NOW() WHERE id = $id;
  COMMIT;
  ```

---

## Code Layout

```
/home/alfiang/Projects/setup-aldera-router/
├── PROJECT.md                                # Master project specification & index
├── TEST_INFRA.md                            # E2E testing framework index
├── TEST_READY.md                            # Published when E2E test suite is complete
├── verify-relay.sh                          # Automated E2E verification script
│
├── database/                                # Milestone 1 (Database)
│   ├── migrations/
│   │   └── 001_initial_schema.sql           # Complete PostgreSQL DDL, constraints & indexes
│   ├── seeds/
│   │   └── 001_initial_pricing.sql          # Seed data for model_pricing
│   └── docker-entrypoint-initdb.d/
│       └── init.sql                         # Combined initialization script for Docker
│
├── billing-proxy/                           # Milestone 2 (Go Gateway)
│   ├── go.mod
│   ├── go.sum
│   ├── Dockerfile
│   ├── cmd/
│   │   └── server/
│   │       └── main.go                      # Entry point & graceful shutdown
│   └── internal/
│       ├── auth/
│       │   ├── key_validator.go             # API key validator & SHA-256 hash lookup
│       │   └── cache.go                     # Thread-safe TTL cache
│       ├── config/
│       │   └── config.go                    # Environment & runtime configuration
│       ├── database/
│       │   ├── pool.go                      # pgxpool connection pool management
│       │   └── billing_repo.go              # Atomic balance check, debit & ledger insert
│       ├── handler/
│       │   ├── health.go                    # /healthz endpoint
│       │   ├── models.go                    # /v1/models endpoint
│       │   └── relay.go                     # /v1/chat/completions & /v1/messages proxy
│       ├── pricing/
│       │   └── calculator.go                # Decimal pricing math per model
│       ├── stream/
│       │   ├── sse_flusher.go               # Realtime SSE stream parser & flusher
│       │   └── estimator.go                 # Fallback tiktoken estimator
│       └── tests/                           # Unit, concurrency & integration tests
│
├── router-telegram-bot/                     # Milestone 3 (Python Bot)
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── pyproject.toml
│   ├── bot/
│   │   ├── __init__.py
│   │   ├── main.go / main.py                # Bot runner & dispatcher initialization
│   │   ├── config.py                        # Pydantic settings
│   │   ├── database/
│   │   │   ├── connection.py                # asyncpg pool manager
│   │   │   └── repo.py                      # Database queries with row-level locks
│   │   ├── filters/
│   │   │   └── admin.py                     # AdminFilter restricted to ADMIN_TELEGRAM_ID
│   │   ├── handlers/
│   │   │   ├── user_commands.py             # /start, /apikey, /saldo, /harga, /cara_pakai
│   │   │   ├── topup.py                     # /topup, unique code, receipt photo handler
│   │   │   └── admin_commands.py            # /addsaldo, /stats, /setprice, inline approvals
│   │   ├── keyboards/
│   │   │   └── inline.py                    # Approval inline buttons
│   │   └── services/
│   │       ├── key_generator.py             # sk-toko-... generation & hashing
│   │       └── qr_service.py                # Payment instructions formatting
│   └── tests/                               # pytest suite for handlers & idempotency
│
├── server-infra-with-ansible/               # Milestone 4 (Ansible Automation)
│   ├── playbooks/
│   │   ├── server-setup.yml                 # Master playbook including aldera-router-setup
│   │   └── deploy-aldera-router.yml         # Dedicated application deployment playbook
│   ├── group_vars/
│   │   └── all/
│   │       └── apps.yml                     # NPM proxy host entries for api/router.aldera.tech
│   └── roles/
│       └── applications/
│           └── aldera-router-setup/
│               ├── tasks/
│               │   └── main.yml             # Directory setup, template rendering, docker compose
│               ├── templates/
│               │   ├── docker-compose.yml.j2 # 9router, billing-proxy, telegram-bot, postgres
│               │   └── .env.j2              # Variables & secrets template
│               └── vars/
│                   └── main.yml             # Role defaults & volume definitions
│
└── tests/                                   # Milestone 5 & E2E Testing Track
    ├── e2e/
    │   ├── test_runner.py                   # Opaque-box E2E test runner
    │   ├── tier1_features/                  # Tier 1: Feature Isolation (>= 5 per feature)
    │   ├── tier2_boundaries/                # Tier 2: Boundaries, race conditions & error states
    │   ├── tier3_pairwise/                  # Tier 3: Cross-feature combinations
    │   └── tier4_realworld/                 # Tier 4: Real-world workflow scenarios
    └── mock_upstream/                       # Lightweight mock upstream for standalone E2E testing
