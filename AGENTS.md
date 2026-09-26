# Panduan AI Agent

Dokumen ini adalah sumber instruksi utama untuk AI agent yang bekerja di repository ini. File instruksi khusus tool hanya menunjuk ke dokumen ini agar aturan project tidak tersebar atau saling berbeda.

## Tentang project

Repository ini mengelola konfigurasi dan deployment server menggunakan Ansible. Playbook utama berada di `playbooks/server-setup.yml`; konfigurasi dibagi ke dalam roles untuk setup sistem, hardening keamanan, infrastruktur, database, aplikasi, dan optimasi. Project ini juga menyediakan skrip dan target Make untuk mengelola katalog aplikasi, kontrak environment, audit repository, dan operasi server.

## Sumber konfigurasi

- `group_vars/all/apps.yml` adalah katalog aplikasi dan sumber utama untuk metadata seperti status, repository, domain, deployment, kontrak environment, serta mapping variabel dan secret CI.
- `group_vars/all/vars.yml` berisi konfigurasi non-sensitif bersama.
- `group_vars/all/vault.yml` menyimpan credential terenkripsi dengan Ansible Vault. `group_vars/all/vault.yml.example` adalah panduan bentuk variabelnya, bukan tempat menyimpan nilai rahasia nyata.
- Template `.env` aplikasi berada di `roles/applications/<app>-setup/templates/.env.j2`. Template harus mengambil nilai rahasia dari variabel Vault, bukan menanam credential secara langsung.
- `ansible.cfg`, `inventory/`, `requirements.yml`, `playbooks/`, `roles/`, `scripts/`, `README.md`, dan `Makefile` menjelaskan cara project dijalankan dan diorganisasi. Periksa implementasi yang ada sebelum mengubah asumsi atau pola.

## Akses credential dan penanganan rahasia

Pemilik project telah memberi AI agent izin untuk membaca credential di project ini, termasuk mendekripsi `group_vars/all/vault.yml` menggunakan Ansible Vault bila tugas memang memerlukannya. `.vault_pass` adalah file lokal yang mungkin menyediakan password vault dan tidak boleh masuk Git.

- Baca atau dekripsi hanya credential yang diperlukan untuk tugas saat ini.
- Jangan menyalin nilai rahasia ke dokumentasi, contoh, template, issue, log, output terminal yang dibagikan, atau balasan kepada pengguna.
- Jangan menampilkan isi vault dalam diff atau ringkasan perubahan. Laporkan nama key atau hasil validasi tanpa nilainya.
- Simpan credential baru di Vault dan gunakan variabel Vault dari template atau konfigurasi terkait.
- Jangan mengubah, menghapus, atau mengganti credential saat tugas hanya meminta inspeksi atau dokumentasi.

## Alur kerja perubahan

1. Periksa `git status --short` sebelum mengedit. Kenali perubahan lokal yang sudah ada dan pertahankan; jangan melakukan reset, checkout massal, atau penghapusan perubahan yang bukan bagian dari tugas.
2. Baca README, katalog aplikasi, role, template, dan skrip yang berkaitan sebelum mengubah perilaku. Ikuti pola yang sudah dipakai repository.
3. Untuk perubahan aplikasi, pertahankan kesesuaian antara `apps.yml`, role aplikasi, template `.env`, repository aplikasi, dan konfigurasi CI.
4. Jika kontrak `.env.example` di repository aplikasi berubah, gunakan `make env-contract-check` atau `make env-contract-check APP=<slug>`, lalu `make env-contract-show APP=<slug>` untuk meninjau selisih. Tambahkan key yang diperlukan ke template dan mapping CI jika memang dipakai saat build atau deploy.
5. Lakukan validasi yang sesuai dengan perubahan, lalu tinjau diff dan status Git. Jangan melaporkan pemeriksaan sebagai berhasil jika belum dijalankan.

## Perintah yang berguna

- `make app-list` menampilkan katalog aplikasi.
- `make app-env-check` memeriksa template environment aplikasi; dapat dibatasi dengan `APP=<slug>`.
- `make env-contract-check` memeriksa kontrak `.env.example` dari repository aplikasi; dapat dibatasi dengan `APP=<slug>`.
- `make check` memeriksa sintaks playbook; `make lint` menjalankan ansible-lint; `make shell-check` memeriksa sintaks skrip shell; `make validate` menjalankan validasi lokal tersebut.
- `make app-dry-run APP=<slug>` melakukan dry-run deployment aplikasi. Tinjau hasilnya sebelum menjalankan `make app APP=<slug>` yang menerapkan perubahan ke server.
- `make vault-view` dan `make vault-edit` adalah target untuk melihat atau mengedit Vault. Gunakan hanya bila dibutuhkan; jangan menyalin hasilnya ke output.

Target `make env-contract-check`, `make repo-audit`, dan beberapa skrip utilitas dapat mengakses repository eksternal. Deployment, perubahan DNS, sinkronisasi GitHub secrets/variables, dan operasi jarak jauh memiliki efek di luar working tree. Jalankan operasi tersebut hanya saat diminta secara jelas dan untuk aplikasi atau target yang dimaksud.

## Panduan agent

- Utamakan perubahan kecil yang langsung memenuhi permintaan. Jangan memperluas cakupan ke aplikasi, credential, server, atau layanan eksternal lain.
- Gunakan Bahasa Indonesia sebagai bahasa komunikasi default, kecuali pengguna meminta bahasa lain.
- Ikuti instruksi yang lebih spesifik di direktori kerja bila ada file `AGENTS.md` tambahan.
- Codex dan OpenCode membaca `AGENTS.md` di root secara langsung. Adapter tool lain di root atau direktori konfigurasinya hanya menunjuk ke dokumen ini.
