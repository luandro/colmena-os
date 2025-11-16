# Balena Deployment Runbook

This guide covers provisioning a Balena fleet, pushing the unified ColmenaOS image, promoting releases, and rolling back when necessary.

## Prerequisites
- BalenaCloud account with permission to create fleets.
- Balena CLI (`npm install -g balena-cli`) and Docker installed locally.
- Repository cloned with submodules:  
  `git clone --recursive https://github.com/colmena-project/colmena-os.git`
- Access to the credentials required for production (`SECRET_KEY`, database passwords, etc.).

## 1. Create or Select a Fleet
1. Authenticate: `balena login`
2. Create a fleet (or reuse an existing one) matching your device type:
   ```bash
   balena fleet create colmena-prod --type raspberrypi4-64
   ```
   Supported types are listed in [`balena.yml`](../balena.yml) (`raspberrypi4-64`, `raspberrypi3-64`, `generic-amd64`, `intel-nuc`).

## 2. Configure Fleet Variables
Balena injects environment variables at the fleet level. Set the critical ones before deploying:

> ⚠️ **Never** keep the illustrative values below (e.g., `change_me`, `secure_db_password`).
> Generate strong, unique secrets for every fleet before running these commands.

```bash
balena env add SECRET_KEY "your-50-char-secret" --fleet colmena-prod
balena env add SUPERADMIN_EMAIL "admin@colmena.org" --fleet colmena-prod
balena env add SUPERADMIN_PASSWORD "change_me" --fleet colmena-prod
balena env add POSTGRES_PASSWORD "secure_db_password" --fleet colmena-prod
balena env add NEXTCLOUD_ADMIN_PASSWORD "secure_nextcloud_password" --fleet colmena-prod
balena env add PGADMIN_DEFAULT_PASSWORD "secure_pgadmin_password" --fleet colmena-prod
```

Additional defaults (e.g., `POSTGRES_USERNAME`, `NEXTCLOUD_TRUSTED_DOMAINS`) are defined in [`balena.yml`](../balena.yml); override as needed with `balena env add`.

## 3. Build and Push the Application
1. Ensure submodules are up to date: `git submodule update --init --recursive`
2. From the repo root, push to the fleet (Balena builds the image in the cloud):
   ```bash
   balena push colmena-prod
   ```
3. Watch the build output. On success, Balena creates a draft release and starts deploying to devices in the fleet.

## 4. Provision Devices
For each device:
1. Download an OS image:  
   `balena os download raspberrypi4-64 --output colmena.img --version latest`
2. Inject fleet configuration:  
   `balena os configure colmena.img --fleet colmena-prod --config-network wifi --config-wifi-ssid <SSID> --config-wifi-key <PASS>`
3. Flash the device: `balena local flash colmena.img`
4. Boot the device; it appears in the Balena dashboard and begins downloading the draft release.

## 5. Promote Releases
Follow the promotion workflow described in [`../30-implementation/release-flow.md`](../30-implementation/release-flow.md):
1. Validate the draft release on a staging fleet or limited production devices.
2. When ready, promote the release:
   ```bash
   balena release promote <draft-release-id> --fleet colmena-prod
   ```
   or trigger the GitHub Actions workflow `deploy-balena-production.yml` if automation is preferred.

## 6. Monitoring
- Use the Balena dashboard to monitor device status, logs, and service health.
- For CLI monitoring, use `balena logs <device-uuid>` and `balena device <device-uuid>`.
- Store build artefacts and test results from `scripts/test-compose-local.sh` for reference prior to promotion.

## 7. Rollback
- Identify the previous stable release: `balena releases colmena-prod`
- Promote the earlier release ID back to production:  
  `balena release promote <previous-release-id> --fleet colmena-prod`
- To remove a faulty release entirely, call `balena release revoke <release-id>`.
- Devices automatically roll back when the new release is promoted; monitor their update progress.

## 8. Updating Configuration
- To rotate secrets, update the fleet environment variable with `balena env add --update`.
- For per-device overrides, use `balena env add --device <uuid>`.
- When compose changes are required (e.g., port remap), update `docker-compose.yml`, commit, and rerun `balena push`.

## Troubleshooting
- **Build failures**: run `scripts/test-compose-local.sh` locally before pushing; ensure the unified Dockerfile builds on amd64 and arm64.
- **Device stuck on installing**: verify network connectivity and that the device type matches the fleet.
- **Service unhealthy**: inspect service logs from the dashboard, confirm environment variables, and compare against `docker-deployment.md`.
- **Storage exhaustion**: prune old releases or reduce container log retention (`balena device service-logs-config`).

For a high-level automation view, cross-reference [`../30-implementation/ci-cd.md`](../30-implementation/ci-cd.md) and the release flow diagram.
