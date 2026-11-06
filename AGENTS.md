# Panduan AI

Repository ini mengelola satu VPS dengan platform bersama dan grup aplikasi terpisah.
Mulai dari `projects/index.yml`, lalu baca `projects/<grup>/AGENTS.md` dan konfigurasi aplikasi yang diminta.
Jangan membaca seluruh grup untuk perubahan satu aplikasi. Role bersama dibaca hanya jika relevan.

- Konfigurasi platform: `platform/`. Aplikasi dan template environment: `projects/<grup>/apps/<nama>/`.
- Vault platform dan grup terenkripsi. Pemilik mengizinkan pembacaan bila diperlukan; jangan tampilkan nilainya, diff plaintext, atau salin ke log/dokumentasi.
- Gunakan hanya `make infra ACTION=...` sebagai antarmuka operator. Contoh: `make infra ACTION=plan GROUP=...` lalu `make infra ACTION=deploy GROUP=... [APP=...]`. APP dapat menentukan grup secara unik.
- Semua perubahan VPS memakai lock yang sama melalui dispatcher. Jangan melewati lock atau melakukan prune global.
- `enabled` hanya mengatur deployment website. `production` di `projects/<grup>/apps/<app>/app.yml` adalah status lifecycle yang terpisah dan menjadi acuan keselamatan data; jangan menyimpulkannya dari `.env`, `NODE_ENV`, atau `APP_ENV`.
- `production: false` berarti aplikasi menggunakan data disposable/dummy. Agen boleh menjalankan reset database terarah tanpa meminta konfirmasi tambahan dengan `make infra ACTION=reset-db APP=<app>`. Perintah ini hanya menerima satu aplikasi enabled non-production, memeriksa ownership lebih dulu, lalu menerapkan skema dan seeder yang tersedia.
- Reset hanya menyentuh database yang terbukti dimiliki aplikasi itu. Jangan menghapus database yang shared, system, tidak tercatat, atau ownership-nya tidak jelas. Layanan database bersama, volume aplikasi, DNS, dan proxy tetap di luar cakupan reset.
- `production: true` melarang `ACTION=reset-db`; minta persetujuan pemilik sebelum tindakan destruktif lain. Penghapusan aplikasi beserta resource-nya memakai `ACTION=decommission DESTROY_DATA=yes` dan izin pemilik.
- Jangan mengubah versi atau restart layanan bersama dari deployment grup. PostgreSQL bersama digunakan seluruh aplikasi yang dikelola.
- Periksa status Git; pertahankan pekerjaan lokal. Gunakan feature/fix branch dari main, PR ke main, dan squash merge. Jangan commit langsung ke main.
- Pemeriksaan lengkap: `make infra ACTION=validate`; kontrak environment: `make infra ACTION=env-check GROUP=... APP=...`.
- Jangan menjalankan playbook Ansible langsung; dispatcher memvalidasi target dan memakai lock yang diwajibkan.
- Gunakan Bahasa Indonesia dan laporkan hasil validasi yang benar-benar dijalankan.
