# AlderaTech

Baca AGENTS.md utama lalu file aplikasi yang diminta di apps/<nama>/app.yml.
Konfigurasi dan environment grup ini berada di folder ini; jangan memuat Vault grup lain.
Gunakan `make infra ACTION=plan GROUP=alderatech` sebelum `make infra ACTION=deploy GROUP=alderatech`.
Untuk satu aplikasi tambahkan `APP=<nama>`. Vault berisi rahasia; jangan tampilkan nilainya.
Role deployment bersama berada di roles/applications, layanan bersama di roles/databases dan roles/infrastructure.
Perubahan grup ini hanya boleh memengaruhi resource miliknya.
