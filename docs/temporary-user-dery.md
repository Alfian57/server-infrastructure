# Panduan User Sementara: `dery` & SOP Penghapusan Tuntas (Purge)

> [!WARNING]
> **Status Akun: SEMENTARA (*TEMPORARY*)**  
> Akun Linux `dery` dibuat untuk keperluan penggunaan sementara pada VPS ini. Seluruh konfigurasi diatur dengan isolasi ketat agar tidak mengganggu maupun membaca aplikasi, database, dan file konfigurasi milik Alfian.

---

## 1. Detail Profil & Konfigurasi User `dery`

| Komponen | Nilai / Kebijakan | Keterangan |
| :--- | :--- | :--- |
| **Username** | `dery` | User Linux non-root |
| **Home Directory** | `/home/dery` | Terkunci khusus dengan permission `0700` |
| **Default Shell** | `/bin/bash` | Standar shell |
| **Password Awal** | `alderatech` | Disimpan terenkripsi di Vault (`vault_user_dery_password`) |
| **Hak Sudo** | **TIDAK ADA** | Dinonaktifkan (`sudo_nopasswd: false`), tidak ada akses root |
| **Grup Docker** | **TIDAK ADA** | Tidak bisa mengakses `/var/run/docker.sock` daemon utama |
| **Systemd Linger** | **AKTIF** (`true`) | Proses & container tetap berjalan saat logout SSH |

---

## 2. Kebijakan Keamanan & Batasan Akses

1. **Isolasi Folder `/opt/docker-stack`:**
   - Direktori `/opt/docker-stack` memiliki hak akses `0770` dengan kepemilikan `deployer:docker`.
   - User `dery` tidak masuk dalam grup `docker` maupun `deployer`, sehingga perintah `cd /opt/docker-stack` atau upaya membaca file `.env` akan langsung ditolak (**Permission Denied**).
2. **Isolasi Home Directory:**
   - Direktori `/home/alfiang` dan `/home/deployer` memiliki hak akses `0700`. User `dery` tidak dapat melihat isi file pribadi milik Alfian.
3. **Isolasi Docker (Jika Dery Menggunakan Docker):**
   - Dery **tidak diperbolehkan** menggunakan Docker daemon utama host (`/var/run/docker.sock`).
   - Jika Dery ingin menjalankan container, Dery harus menggunakan **Docker Rootless** di dalam `/home/dery`:
     ```bash
     # Dijalankan oleh Dery di dalam sesinya sendiri:
     dockerd-rootless-setuptool.sh install
     ```
   - Dengan Docker Rootless, container Dery berjalan di user namespace miliknya (`/run/user/<UID>/docker.sock`) dan **tidak dapat melihat atau menyentuh container milik Alfian**.

---

## 3. SOP Penghapusan Tuntas Sampai ke Akar-akarnya (Purge SOP)

Ketika masa penggunaan sementara selesai dan Anda ingin menghapus user `dery` secara bersih total tanpa meninggalkan residu di server maupun di repositori Ansible, ikuti langkah berikut:

### Opsi A: Penghapusan Otomatis Melalui Ansible (Direkomendasikan)

#### Langkah 1: Ubah status user pada `group_vars/all/vars.yml`
Buka [group_vars/all/vars.yml](file:///home/alfiang/Projects/server-infra-with-ansible/group_vars/all/vars.yml), ubah blok `dery` menjadi:
```yaml
  - name: "dery"
    state: "absent"
    remove: true # Menghapus home directory /home/dery dan mail spool
```

#### Langkah 2: Terapkan perubahan ke server
Jalankan playbook untuk role `users-setup`:
```bash
ansible-playbook playbooks/server-setup.yml -i inventory/hosts.ini --tags users-setup
```
Ansible secara otomatis akan:
- Menghapus akun Linux `dery`.
- Menghapus folder `/home/dery` dan mail spool.
- Mematikan dan menghapus file linger `/var/lib/systemd/linger/dery`.
- Menghapus sisa sudoers di `/etc/sudoers.d/dery` jika ada.

#### Langkah 3: Bersihkan entri dari Repositori Git
1. Hapus seluruh blok user `dery` dari [group_vars/all/vars.yml](file:///home/alfiang/Projects/server-infra-with-ansible/group_vars/all/vars.yml).
2. Hapus variabel `vault_user_dery_password` dari [group_vars/all/vault.yml](file:///home/alfiang/Projects/server-infra-with-ansible/group_vars/all/vault.yml) menggunakan `make vault-edit` atau ansible-vault.
3. Hapus baris placeholder `vault_user_dery_password` di [group_vars/all/vault.yml.example](file:///home/alfiang/Projects/server-infra-with-ansible/group_vars/all/vault.yml.example).
4. Hapus file panduan ini (`docs/temporary-user-dery.md`).
5. Lakukan commit Git:
   ```bash
   git commit -am "chore: purge temporary user dery and associated configurations"
   ```

---

### Opsi B: Pembersihan Manual via Terminal Server (Jika Dibutuhkan Cepat)

Jika Anda ingin langsung membersihkannya secara manual dari server VPS dalam satu sesi:

```bash
# 1. Matikan seluruh proses yang sedang dijalankan oleh user dery
sudo pkill -9 -u dery

# 2. Nonaktifkan systemd linger
sudo loginctl disable-linger dery

# 3. Hapus user beserta seluruh home directory dan mail spool
sudo userdel -r dery

# 4. Pastikan file residu benar-benar terhapus
sudo rm -f /var/lib/systemd/linger/dery
sudo rm -f /etc/sudoers.d/dery
sudo rm -rf /run/user/$(id -u dery 2>/dev/null)

# 5. Verifikasi bahwa user dery sudah tidak ada di sistem
id dery
# Output harus: id: ‘dery’: no such user
```

---

## 4. Perintah Verifikasi Saat User Aktif

- **Memeriksa status akun:**
  ```bash
  id dery
  ```
- **Memeriksa status systemd linger (harus aktif / lingering=yes):**
  ```bash
  loginctl show-user dery --property=Linger
  # Output: Linger=yes
  ```
- **Memeriksa isolasi folder /opt/docker-stack (harus ditolak):**
  ```bash
  su - dery -c "ls -la /opt/docker-stack"
  # Output harus: ls: cannot open directory '/opt/docker-stack': Permission denied
  ```
