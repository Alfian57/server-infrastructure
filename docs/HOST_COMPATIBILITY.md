# Host Compatibility Policy

This project is intended to survive VPS changes where CPU generation, CPU architecture, or distro version changes.

## Host Detection

The `host-profile` role runs before infrastructure roles. It detects:

- OS family and distro release.
- Container architecture (`linux/amd64`, `linux/arm64`, `linux/arm/v7`).
- x86_64-v2 CPU feature support for images that may not run on older VPS CPUs.

Unsupported OS families fail early with a clear message instead of failing halfway through package installation.

## Image Selection

New VPS behavior:

- Prefer `mysql:8.4` when the host can run it.
- Fall back to `mariadb:10.11` for older `x86_64` CPUs without x86_64-v2 features.
- Prefer recent PostgreSQL, Redis, Nginx Proxy Manager, and MinIO images from the central image policy.
- Use `jc21/nginx-proxy-manager:2.13.7` on `linux/arm/v7` because Nginx Proxy Manager 2.14+ no longer publishes armv7/armhf images.

Existing VPS behavior:

- Stateful services preserve their existing container image by default. This prevents accidental major upgrades against existing volumes.
- This applies to MySQL/MariaDB, PostgreSQL, Redis, Nginx Proxy Manager, and MinIO.

To force an image after taking backups, set an override variable:

```yaml
mysql_image_override: "mysql:8.4"
postgres_image_override: "postgres:18-bookworm"
redis_image_override: "redis:8"
npm_image_override: "jc21/nginx-proxy-manager:2.14.0"
minio_image_override: "minio/minio:latest"
```

For MySQL/MariaDB, you can also force the engine selection on a fresh host:

```yaml
mysql_engine: "mysql"    # auto, mysql, mariadb
```

Do not force-switch an existing MariaDB volume to MySQL without a dump/restore migration.

## Distro Support

Docker installation supports Debian/Ubuntu and RedHat-family hosts. Debian/Ubuntu uses the matching Docker APT repository (`debian` or `ubuntu`), not a hardcoded Ubuntu repository.

Security hardening, WARP, and cost optimization are currently Debian-family only because they use UFW/APT-specific tasks.
