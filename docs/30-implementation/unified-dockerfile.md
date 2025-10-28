# Unified Dockerfile

**Related roadmap item:** ISSUE-001  
**Primary objective:** [2 — Ship a Unified Deployable Stack](../10-objectives.md#2-ship-a-unified-deployable-stack)

## Build Strategy
- Multi-stage build on `node:18-alpine` to compile both backend (Django REST + Gunicorn) and frontend (React PWA).
- Install `nginx` and `supervisor` to host static assets and keep backend running.
- Copy production build artifacts into `/opt/colmena/frontend` and `/opt/colmena/backend`.

## Process Supervision
`supervisord.conf` must launch two long-lived processes:
1. `python -m gunicorn colmena.wsgi:application --bind 0.0.0.0:8000` (backend). Using `python -m gunicorn` avoids PATH issues when the `gunicorn` shim is not installed globally.
2. `nginx -g 'daemon off;'` serving the compiled frontend from `/usr/share/nginx/html`.

Expose ports `8080` (frontend) and `8000` (backend) for compatibility with Docker Compose and CasaOS metadata. Add log rotation if supervisors emit high-volume logs.

## nginx Configuration
The image must **not** rely on the submodule’s default nginx config: that file only returns static assets and breaks `/api/` proxying. Generate a unified config inside the Dockerfile, e.g.:

```nginx
server {
    listen 80;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    location /static/ { alias /opt/app/static/; }
    location /media/  { alias /opt/app/media/; }
}
```

Place the file in `/etc/nginx/http.d/default.conf` so Alpine nginx loads it automatically. Keep the backend running on localhost:8000 to simplify networking.

## Health Checks
- Backend: `curl -f http://127.0.0.1:8000/api/health/`
- Frontend: `curl -f http://127.0.0.1:8080/`

## Build Args
- `BUILDPLATFORM` / `TARGETPLATFORM` to support Buildx multi-arch flows.
- `COLMENA_VERSION` to stamp images with SemVer.

For the earlier brainstorming and alternative approaches, refer to [`../context/unified-dockerfile.md`](../context/unified-dockerfile.md).
