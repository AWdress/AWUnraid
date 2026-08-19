# AW Companion

AW Companion is the native file gateway used by AW Unraid. It exposes `/mnt/user` through a small JSON/streaming API and validates every request by forwarding the App's existing `x-api-key` to the local Unraid GraphQL endpoint.

## Run on Unraid

```bash
docker compose up -d --build
```

Local access uses `http://UNRAID-IP:8089`. For remote access, route `https://YOUR-NAS/aw-files/*` to `http://127.0.0.1:8089/*` in the same reverse proxy that exposes GraphQL. Do not expose SMB, NFS, port 8089, or the Unraid WebGUI directly to the public internet.

The container only receives `/mnt/user`; `/boot`, individual disks and other host paths are not mounted. Path traversal and symlink escapes outside `/mnt/user` are rejected.
