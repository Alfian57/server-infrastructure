# Server User Model

This project separates infrastructure administration from application deploys.

| User | Used by | Groups | Sudo | Purpose |
| --- | --- | --- | --- | --- |
| `deployer` | Ansible inventory and local `make ssh` | `sudo`, `docker` | Passwordless | Full server automation through Ansible. |
| `app-deployer` | GitHub Actions `VPS_USER` | `docker` | No | Application-only deploys through `/opt/docker-stack/applications/<app>/update.sh`. |
| `alfiang` | Manual admin access | `sudo`, `docker` | Passwordless | Human break-glass/admin operations. |

Production SSH is key-only, direct root SSH is disabled, and `AllowUsers` is generated from the managed users list.

GitHub Actions should always use `secrets.VPS_USER`; do not hardcode a Linux username in workflow files. The catalog sync command writes `VPS_USER=app-deployer` to every managed repository:

```bash
./scripts/env-contracts.py github-sync
```

The CI deploy user intentionally has Docker access. Docker group membership is effectively root-equivalent on the host, so this user must not have shell password login or broad sudo.
