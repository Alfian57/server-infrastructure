# Infrastruktur VPS dengan Ansible

Satu VPS, lima grup aplikasi, dan layanan platform bersama. Pengelompokan mengikuti kebutuhan operasional, terpisah dari pemilik repository GitHub.

| ID | Nama | Isi utama |
|---|---|---|
| personal | Personal | PUI, portofolio, Panca Trivia, Presensi Skansaba, File Pod |
| uty | UTY | Sistertika API dan web |
| lomba | Lomba | Ruang Tenang, SATU, Guardian Lab dan AI |
| alderatech | AlderaTech | Aldera web, Router produksi/staging, aplikasi Aldera lainnya |
| gamblock-ai | Gamblock-AI | Backend, website, dan konfigurasi CI aplikasi native |

`make infra ACTION=list` menampilkan domain dan status enabled/disabled seluruh aplikasi. Aplikasi mobile mengikuti grup proyeknya dan bukan container VPS.

## Perintah tunggal

```sh
make infra ACTION=list GROUP=uty
make infra ACTION=plan GROUP=uty
make infra ACTION=deploy GROUP=lomba APP=guardian-lab
make infra ACTION=check APP=sistertika-uty-api
make infra ACTION=platform SERVICE=postgres
make infra ACTION=decommission DESTROY_DATA=yes
```

Semua operasi operator menggunakan bentuk `make infra ACTION=...`. Tanpa `ACTION`, perintah menampilkan bantuan. Deployment harus menyebut `GROUP` atau `APP`; tidak ada default deploy-all. Aksi `all`, `rollout`, dan `resume-rollout` tersedia untuk operasi eksplisit. Operasi yang dapat menghapus data tetap memerlukan `DESTROY_DATA=yes`.

Daftar aksi, termasuk bootstrap SSH, security-hardening, pemeriksaan, sinkronisasi, dan operasi platform, tersedia lewat `make infra ACTION=help`. Playbook dan perintah Ansible langsung adalah detail internal dispatcher, bukan antarmuka operator.

## Konfigurasi

`projects/index.yml` memetakan aplikasi ke grup. Konfigurasi setiap aplikasi dan template `.env` berada di folder aplikasinya. Vault grup hanya dimuat untuk grup tersebut; credential engine, DNS, dan proxy disimpan di Vault platform.

Role umum mempertahankan logika deployment bersama. AGENTS.md setiap grup menunjukkan konteks yang perlu dibaca. Nilai credential tidak boleh disalin ke dokumentasi atau output pemeriksaan.

## Batas operasi

PostgreSQL, MySQL, Redis, proxy, dan jaringan dikelola sebagai platform VPS. Deployment grup menggunakan layanan sehat yang sudah tersedia dan hanya melakukan provisioning database/user aplikasinya. Engine yang belum ada dipasang dari konfigurasi platform. Engine yang bermasalah memerlukan maintenance eksplisit.

Seluruh entrypoint Ansible dan update.sh menggunakan lock VPS yang sama. Build image tetap bisa paralel. Konfigurasi registry setiap update terpisah, dan tidak ada prune global. Ansible mempertahankan image aplikasi yang sedang berjalan; CI tetap dapat memperbarui aplikasi melalui update.sh.

DNS/proxy diubah berdasarkan domain aplikasi terpilih. Resource grup lain dan host manual tidak dianggap usang saat deploy satu grup. `enabled: false` melewati aplikasi tanpa menghapusnya.

## Operasi data

Enam aplikasi pensiun didefinisikan pada manifest operasi: Posyandu, Materi Ku, Ruang Istirahat, Tech Talk, Campus Project Hub API dan web. `make infra ACTION=decommission DESTROY_DATA=yes` menghapus hanya resource yang terverifikasi milik keenam aplikasi. Operasi ini tidak menghapus repository GitHub atau layanan platform.

`make infra ACTION=consolidate DESTROY_DATA=yes` menginisialisasi database Router staging lalu produksi pada PostgreSQL bersama menggunakan migration/seeder. Data dummy sumber tidak disalin dan sumber lama dibersihkan setelah pemeriksaan berhasil. Database aplikasi yang sudah berada pada engine bersama dipertahankan. Deploy rutin tidak membuat ulang database atau menjalankan seed ulang.

Workflow Scoped Infrastructure Operations menyediakan preflight, helper installation, deployment/check satu grup, platform maintenance, decommission, dan konsolidasi. Host key SSH dipin melalui VPS_KNOWN_HOSTS; secret tidak dicetak.
