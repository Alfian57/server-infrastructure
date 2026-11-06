# Mengelola credential Ansible

Credential bersama berada di Vault platform; credential aplikasi berada di Vault grup. Contoh nama variabel tersedia di berkas `.vault.yml.example` terkait.

```sh
make infra ACTION=vault-view
make infra ACTION=vault-edit GROUP=lomba
make infra ACTION=env-check GROUP=lomba APP=guardian-lab
```

Jangan menaruh nilai credential pada dokumentasi, log, atau commit plaintext. Validasi lengkap tersedia lewat `make infra ACTION=validate`.
