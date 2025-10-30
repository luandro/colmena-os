# CasaOS Deployment Runbook

ColmenaOS runs on CasaOS by reusing the unified `docker-compose.yml` shipped in this repository. This guide walks through importing the stack, wiring secrets, and operating the app from the CasaOS dashboard.

## Prerequisites
- CasaOS 0.4 or later with administrative access.
- Docker Compose support enabled on the host (CasaOS bundles it by default).
- Repository clone (or access to the published compose file) with submodules initialised:  
  `git clone --recursive https://github.com/colmena-project/colmena-os.git`
- Values for the required secrets (database passwords, admin credentials).

## 1. Prepare the Compose Bundle
1. From the repo root, ensure the CasaOS metadata block is present in `docker-compose.yml`. The `colmena-app` service must include:
   ```yaml
   x-casaos:
     store_app_id: colmena-os
     category: Media
     architectures:
       - amd64
       - arm64
     main: colmena-app
     title: ColmenaOS
     description: Offline-first community media platform
   ```
   Keep this block in sync with [`docs/30-implementation/docker-compose.md`](../30-implementation/docker-compose.md).
2. Copy `docker-compose.yml` and `.env.example` to a directory accessible by CasaOS (e.g., Shared folder). Rename `.env.example` to `.env` and populate all `CHANGE_ME` entries.

## 2. Import Into CasaOS
1. In the CasaOS dashboard, open **App Store → Custom Install → Compose**.
2. Paste the contents of the prepared `docker-compose.yml` or upload the file directly.
3. CasaOS detects the `x-casaos` metadata and displays the app icon and description. Review the environment variable prompts and map them to the values in your `.env`.
4. Confirm the volume paths. CasaOS automatically mounts named volumes; adjust only if you want to persist data to host directories.

## 3. Configure Environment Variables
Set the following variables via the CasaOS UI (match your `.env` file):

| Variable | Purpose |
|----------|---------|
| `SECRET_KEY` / `COLMENA_SECRET_KEY` | Django cryptographic secret (minimum 50 chars). |
| `SUPERADMIN_EMAIL` / `SUPERADMIN_PASSWORD` | First login credentials. |
| `POSTGRES_PASSWORD` | Database password (also used by Nextcloud). |
| `NEXTCLOUD_ADMIN_PASSWORD` | Nextcloud administrator password. |
| `PGADMIN_DEFAULT_PASSWORD` | Optional pgAdmin UI password. |

CasaOS stores these securely and injects them on container start.

## 4. Deploy and Verify
1. Click **Install**. CasaOS pulls the published image (`communityfirst/colmena-app:latest`) and the supporting services.
2. Watch the deployment status under **Apps → Running**. All services should report “running” within a few minutes.
3. Validate endpoints from your browser (replace ports if you override the defaults):
   - `http://<casaos-host>:7180` – main UI (should load login screen).
   - `http://<casaos-host>:7180/api/` – returns HTTP 401 (expected).
   - Optional: `http://<casaos-host>:7050` (pgAdmin), `:7103` (Nextcloud), `:7080` (Mailcrab).
4. On first login, open the UI, add the server `http://<casaos-host>:7180/api`, and sign in using the super admin credentials (or the port you configured via `HTTP_PORT`).

## 5. Updates
- When a new release is published, open the app in CasaOS and click **Update** (or run `docker compose pull` from the CasaOS host shell).
- For manual upgrades, replace the `image` tag in `docker-compose.yml` or repush the updated compose file, then restart the app from CasaOS.

## 6. Backups and Volumes
CasaOS maps the named volumes declared in the compose file:
- `pg_data`, `pgadmin_data` — database data and pgAdmin configuration.
- `nextcloud_data` — Nextcloud application data.
- `static_data`, `media_data` — Django static and media assets.
- Optional: `nextcloud_apps` if you enable extra Nextcloud apps during runtime.
Schedule host-level backups of these volumes to preserve database and media content.

## 7. Rollback
- CasaOS keeps previous container images. To roll back, open the app details, select the previous image version (if cached), and restart.
- Alternatively, edit `docker-compose.yml` to pin the earlier tag (e.g., `communityfirst/colmena-app:1.1.x`), reimport, and redeploy. Ensure matching database schema compatibility.

## Troubleshooting
- If the app shows as unhealthy, open the container logs from CasaOS. 404 errors on `/` usually mean the nginx config did not load; redeploy the image or run `scripts/test-compose-local.sh` locally to sanity-check the bundle.
- Port conflicts on the CasaOS host require remapping `HTTP_PORT`/`BACKEND_PORT`; update CasaOS environment variables and redeploy.
- To reset the stack, remove the app in CasaOS (tick “Delete volumes” only if you intend to wipe data) and reinstall with the compose file.

For broader operational tips, refer to [`docker-deployment.md`](./docker-deployment.md).
