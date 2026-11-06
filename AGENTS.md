# Panduan AI

Repository ini mengelola satu VPS dengan platform bersama dan grup aplikasi terpisah.
Mulai dari `projects/index.yml`, lalu baca `projects/<grup>/AGENTS.md` dan konfigurasi aplikasi yang diminta.
Jangan membaca seluruh grup untuk perubahan satu aplikasi. Role bersama dibaca hanya jika relevan.

- Konfigurasi platform: `platform/`. Aplikasi dan template environment: `projects/<grup>/apps/<nama>/`.
- Vault platform dan grup terenkripsi. Pemilik mengizinkan pembacaan bila diperlukan; jangan tampilkan nilainya, diff plaintext, atau salin ke log/dokumentasi.
- Deploy lewat `make plan GROUP=...` lalu `make deploy GROUP=... [APP=...]`. APP dapat menentukan grup secara unik.
- Semua perubahan VPS memakai lock yang sama melalui dispatcher. Jangan melewati lock atau melakukan prune global.
- Grup hanya mengubah resource miliknya. `enabled: false` berarti dilewati. Penghapusan data memerlukan operasi decommission eksplisit dan izin pemilik.
- Jangan mengubah versi atau restart layanan bersama dari deployment grup. PostgreSQL bersama digunakan seluruh aplikasi yang dikelola.
- Periksa status Git; pertahankan pekerjaan lokal. Gunakan feature/fix branch dari main, PR ke main, dan squash merge. Jangan commit langsung ke main.
- Jalankan `make validate`; perubahan environment juga diperiksa dengan `make env-contract-check GROUP=... APP=...` jika kontrak repository tersedia.
- Untuk wrapper staging, jalankan syntax-check sebelum deployment.
- Gunakan Bahasa Indonesia dan laporkan hasil validasi yang benar-benar dijalankan.
