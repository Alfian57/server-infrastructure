# Original User Request

## 2026-10-14T16:39:30Z

Membangun platform AI API Relay siap-produksi yang terdiri dari Golang Billing Proxy (gateway verifikasi token & saldo), Python Telegram Management Bot (aiogram v3 untuk top-up dan manajemen user/API key), 9Router upstream integration, PostgreSQL dengan audit mutasi saldo, serta Ansible Playbook & Docker Compose untuk deployment otomatis ke Ubuntu VPS 22.04/24.04 LTS.

Working directory: `/home/alfiang/Projects/setup-aldera-router`
Integrity mode: development

---

## Requirements

### R1. Billing & API Gateway Middleware (`billing-proxy` in Go)
- Menyediakan endpoint OpenAI-compatible (`/v1/chat/completions`, `/v1/models`, `/v1/messages`).
- Validasi API key virtual (`sk-toko-...`) terhadap PostgreSQL dengan caching / pool efisien.
- Atomic balance reservation & deduction: Mencegah *negative balance attack* / *race condition* saat concurrent requests dengan row-level lock / threshold minimum saldo.
- Penanganan SSE Streaming & Non-Streaming: Meneruskan parameter `stream_options: {"include_usage": true}` ke upstream dan dilengkapi fallback token estimator (jika upstream tidak mengirim chunk usage atau client memutuskan koneksi di tengah jalan).
- Menghitung tarif dinamis per model (input & output tokens) dan mencatat log penggunaan ke PostgreSQL.
- Containerized (Dockerfile & healthcheck endpoint).

### R2. Telegram Management Bot (`router-telegram-bot` in Python `aiogram` v3)
- **User Commands:**
  - `/start`: Registrasi otomatis ke database berdasarkan Telegram ID.
  - `/apikey`: Melihat API key aktif atau generate/reset key baru.
  - `/saldo`: Cek sisa saldo (IDR) dan statistik pemakaian token.
  - `/harga`: Daftar harga token per 1 juta token per model AI (dikelompokkan rapi).
  - `/topup [nominal]`: Tiket top-up dengan kode unik 3 digit, instruksi QRIS/Transfer, dan alur upload bukti transfer (foto struk).
  - `/cara_pakai`: Panduan integrasi ke Cursor, Cline, Roo Code, dan OpenWebUI.
- **Admin Commands & Actions (restricted to `ADMIN_TELEGRAM_ID`):**
  - Menerima notifikasi tiket top-up (foto struk + tombol Inline Approve/Reject) dengan proteksi idempotency (anti-double approve).
  - `/addsaldo [telegram_id] [nominal]`: Penyesuaian saldo manual dengan log audit.
  - `/stats`: Ringkasan total user, pemakaian token hari ini, dan estimasi omzet.
  - `/setprice [model] [input_price] [output_price]`: Update tarif jual model.
- Containerized (Dockerfile).

### R3. Database Schema & Security Hardening
- PostgreSQL schema dengan tipe presisi moneter (`NUMERIC(16, 4)`):
  - `users`: id, telegram_id, username, full_name, balance, is_active, created_at.
  - `api_keys`: id, user_id, key_hash, key_prefix, label, is_active, total_spent, last_used_at.
  - `model_pricing`: model_name, display_name, input_price_per_m, output_price_per_m, is_active.
  - `usage_logs`: id, user_id, api_key_id, model, prompt_tokens, completion_tokens, total_cost, duration_ms, is_stream.
  - `topup_requests`: id, user_id, amount, unique_code, total_transfer, proof_file_id, status (pending/approved/rejected), admin_id, created_at, approved_at.
  - `balance_transactions`: audit ledger pencatatan setiap mutasi saldo (topup, usage, manual_adjust).
- Upstream `9router` diisolasi di jaringan internal Docker (`http://9router:20128`), hanya diekspos melalui `billing-proxy` atau diproteksi basic auth jika dashboard admin diakses publik.

### R4. Ansible Automation & Deployment Orchestration
- Mengintegrasikan deployment ke dalam `server-infra-with-ansible` (atau role dedicated `roles/applications/aldera-router-setup`):
  - Template `docker-compose.yml.j2` (service: `9router`, `billing-proxy`, `telegram-bot`, `postgres`).
  - Template `.env.j2` terintegrasi dengan Ansible Vault / variable structure.
  - Setup volume persisten untuk sesi OAuth `9router` dan data PostgreSQL.
  - Konfigurasi reverse proxy host (Nginx Proxy Manager) untuk domain publik `api.aldera.tech` (menuju `billing-proxy:8080`) dan `router.aldera.tech` (opsional internal/dashboard).

---

## Acceptance Criteria

### API Gateway & Billing (`billing-proxy`)
- [ ] Endpoint `/healthz` merespons status `200 OK`.
- [ ] Endpoint `/v1/models` merespons daftar model aktif dari database.
- [ ] Request tanpa API key atau dengan key invalid mengembalikan HTTP `401 Unauthorized`.
- [ ] Request dengan saldo di bawah threshold minimum ditolak dengan HTTP `402 Payment Required`.
- [ ] Request non-streaming memotong saldo secara akurat sesuai prompt & completion tokens.
- [ ] Request streaming SSE berhasil menyalurkan token secara realtime, dan saldo terpotong akurat saat stream selesai.
- [ ] Uji simulasi *race condition* (10 concurrent requests saat saldo rendah) tidak menyebabkan saldo minus (*negative balance prevented*).

### Telegram Bot
- [ ] Perintah `/start` berhasil mendaftarkan user baru di database.
- [ ] Perintah `/apikey` berhasil menerbitkan dan menampilkan key dengan format `sk-toko-...`.
- [ ] Perintah `/topup 50000` memicu alur kode unik dan meminta upload bukti struk.
- [ ] Tombol inline Approve admin berhasil menambah saldo dan mengirim notifikasi ke user, serta menolak jika diklik ulang (idempotent).
- [ ] Perintah admin `/addsaldo` dan `/stats` ditolak jika dipanggil oleh non-admin ID.

### Infrastructure & Deployability
- [ ] `docker compose up -d` (atau `docker compose config`) berjalan valid tanpa error sintaks.
- [ ] Playbook Ansible `aldera-router-setup` lulus `ansible-playbook --syntax-check`.
- [ ] Script pengujian end-to-end / verifikasi otomatis (`verify-relay.sh` atau test suite Go/Python) tersedia untuk memvalidasi alur secara mandiri.


## 2026-10-14T18:37:02Z

Melanjutkan pembangunan platform AI API Relay siap-produksi yang mencakup penyelesaian Python Telegram Management Bot (`router-telegram-bot`), otomasi deployment Ansible & Docker Compose (`server-infra-with-ansible`), integrasi dengan Golang `billing-proxy` dan `9router`, serta penataan struktur direktori agar root project hanya berisi 3 repositori mandiri (`server-infra-with-ansible`, `router-telegram-bot`, `billing-proxy`).

Working directory: `/home/alfiang/Projects/setup-aldera-router`
Integrity mode: development

---

## Context & Completed Milestones
1. **Milestone 1 (Database Schema & Security Ledger)**: Selesai. Skema PostgreSQL dengan tipe moneter `NUMERIC(16, 4)`, trigger immutability audit ledger, non-negative balance constraint, dan migrasi DDL telah dibuat.
2. **Milestone 2 (Billing Proxy Go Service)**: Selesai. API Gateway di `billing-proxy` (Go Chi, pgxpool, Bearer API Key auth dengan hash SHA-256 + memory cache, SSE flusher, injection `include_usage`, fallback token estimator, serta proteksi concurrency) telah lulus verifikasi unit test dan race condition testing.

---

## Requirements

### R1. Telegram Management Bot (`router-telegram-bot` in Python `aiogram` v3)
- Membangun aplikasi bot mandiri di direktori `router-telegram-bot/` (memiliki git repo sendiri).
- **User Handlers:**
  - `/start`: Auto-registrasi user ke PostgreSQL (menyimpan Telegram ID, username, saldo awal Rp 0).
  - `/apikey`: Menampilkan API key aktif (`sk-toko-...`) atau tombol interaktif untuk generate/reset key baru (hash SHA-256 tersimpan di DB, raw key ditampilkan sekali ke user).
  - `/saldo`: Menampilkan sisa saldo IDR (format rupiah rapi) dan statistik riwayat pemakaian token.
  - `/harga`: Menampilkan daftar model AI dan tarif per 1 juta token secara terstruktur.
  - `/topup [nominal]`: Membuat tiket top-up dengan kode unik 3 digit (contoh: Rp 50.342), menampilkan petunjuk transfer QRIS/Bank, dan menunggu user mengirim foto struk pembayaran.
  - Handler Foto Bukti Transfer: Menerima foto struk, menyimpannya di tiket pending, lalu meneruskan foto tersebut ke Telegram Admin (`ADMIN_TELEGRAM_ID`) disertai tombol Inline `[Approve]` dan `[Reject]`.
  - `/cara_pakai`: Menampilkan panduan integrasi endpoint `https://api.aldera.tech/v1` ke Cursor, Cline, Roo Code, dan OpenWebUI.
- **Admin Handlers & Security:**
  - Callback Inline `Approve`/`Reject`: Menggunakan `SELECT ... FOR UPDATE` row-level lock pada `topup_requests` agar eksekusi penambahan saldo 100% idempotent (anti-double approve).
  - `/addsaldo [telegram_id] [nominal]`: Penambahan/pengurangan saldo manual dengan audit log di `balance_transactions`.
  - `/stats`: Menampilkan total user terdaftar, total konsumsi token hari ini, dan total pendapatan deposit.
  - `/setprice [model] [input_price] [output_price]`: Memperbarui harga jual model di DB.
  - Middleware/Filter `AdminFilter`: Memastikan seluruh perintah dan callback admin hanya bisa diakses oleh `ADMIN_TELEGRAM_ID`.
- Dockerfile mandiri (Python 3.12-slim, non-root user, multi-stage/optimized).

### R2. Ansible Playbook & Deployment Orchestration (`server-infra-with-ansible`)
- Menambahkan role Ansible `roles/applications/aldera-router-setup` di `server-infra-with-ansible/`:
  - `templates/docker-compose.yml.j2`: Mengorkestrasi 4 service:
    1. `9router`: Upstream router (`decolua/9router:latest` port internal 20128) dengan volume persisten untuk OAuth tokens.
    2. `billing-proxy`: Gateway API port internal 8080.
    3. `router-telegram-bot`: Bot Python terhubung ke DB dan Telegram API.
    4. `postgres`: PostgreSQL 16 Alpine dengan volume persisten dan skrip inisialisasi schema/seeder di `docker-entrypoint-initdb.d`.
  - Jaringan internal terisolasi (`aldera_router_internal`), upstream 9router tidak mengekspos port publik secara langsung.
  - `templates/.env.j2`: Variabel lingkungan terintegrasi dengan Ansible Vault.
  - Integrasi katalog ke `group_vars/all/apps.yml` dengan reverse proxy routing (Nginx Proxy Manager):
    - Public gateway: `api.aldera.tech` -> `billing-proxy:8080` (SSL Cloudflare).
    - Optional admin: `router.aldera.tech` -> `9router:20128` (dilindungi HTTP Basic Auth / IP Whitelist).
  - Skrip pengujian & validasi deployment otomatis.

### R3. Repository Hygiene & Strict 3-Folder Structure
- Root direktori `/home/alfiang/Projects/setup-aldera-router/` **HANYA** boleh berisi 3 folder repositori:
  1. `server-infra-with-ansible/`
  2. `router-telegram-bot/`
  3. `billing-proxy/`
- Seluruh file skema/migrasi database, skrip testing/harness, dokumentasi internal, dan artefak sementara dipindahkan ke dalam repositori yang relevan:
  - File inisialisasi database (`migrations/`, `seeds/`, `docker-entrypoint-initdb.d/`) dipindahkan ke dalam `server-infra-with-ansible/roles/applications/aldera-router-setup/files/` dan/atau `billing-proxy/`.
  - Test suite dialokasikan ke masing-masing repo terkait.
  - Root folder bersih tanpa file tercecer.

---

## Acceptance Criteria

### Telegram Bot (`router-telegram-bot`)
- [ ] Command `/start` sukses mendaftarkan user baru di database.
- [ ] Command `/apikey` menghasilkan key valid berformat `sk-toko-...`.
- [ ] Command `/topup 50000` menghasilkan nominal dengan 3-digit kode unik.
- [ ] Upload foto struk berhasil mengaitkan bukti ke tiket topup dan mengirim tombol approve ke admin.
- [ ] Callback tombol Approve secara atomic menambah saldo dan mencatat transaksi ke `balance_transactions`.
- [ ] Klik ganda pada tombol Approve ditolak (idempotent, status tiket `approved`).
- [ ] Command `/addsaldo`, `/stats`, `/setprice` ditolak jika dipanggil oleh user non-admin.
- [ ] `Dockerfile` di `router-telegram-bot/` berhasil di-build tanpa error.

### Ansible & Infrastructure (`server-infra-with-ansible`)
- [ ] Role `aldera-router-setup` terkonfigurasi lengkap dengan tasks, templates (`docker-compose.yml.j2`, `.env.j2`), dan defaults.
- [ ] Sintaks Ansible valid: `ansible-playbook --syntax-check` pada playbook terkait berjalan sukses.
- [ ] `docker compose config` dari hasil template berjalan valid tanpa error sintaks.
- [ ] `group_vars/all/apps.yml` terdaftar dengan konfigurasi service dan domain proxy.

### Workspace Hygiene & Isolation
- [ ] Root direktori `/home/alfiang/Projects/setup-aldera-router` strictly hanya berisi 3 folder: `server-infra-with-ansible/`, `router-telegram-bot/`, dan `billing-proxy/`.
- [ ] Masing-masing folder repositori dapat di-git commit secara independen dan bersih.
