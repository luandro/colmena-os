# Running Code in ColmenaOS Environment

This guide explains how to run arbitrary code (backend, frontend, or infrastructure tests) against the actual ColmenaOS docker-compose stack.

## Overview

The `run-in-environment.sh` script provides a unified interface to:
- Run backend code against the live database
- Execute frontend commands in the container
- Test infrastructure components
- Debug issues in the running stack

## Quick Start

### 1. Set up environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env and replace all CHANGE_ME values
# Required: POSTGRES_PASSWORD, SECRET_KEY, COLMENA_SECRET_KEY, SUPERADMIN_PASSWORD
```

### 2. Run your code

```bash
# Run a Django management command
./scripts/run-in-environment.sh backend manage.py showmigrations

# Execute a Python script against the live database
./scripts/run-in-environment.sh backend scripts/my_script.py

# Run frontend tests
./scripts/run-in-environment.sh test frontend

# Run infrastructure tests
./scripts/run-in-environment.sh test infra
```

## Detailed Usage

### Running Backend Code

Use the `backend` command to execute any Python/Django code in the container:

```bash
# Django management commands
./scripts/run-in-environment.sh backend manage.py migrate
./scripts/run-in-environment.sh backend manage.py createsuperuser
./scripts/run-in-environment.sh backend manage.py shell

# Run custom Python scripts
./scripts/run-in-environment.sh backend scripts/analyze_data.py

# Execute arbitrary Python code
./scripts/run-in-environment.sh backend python -c "from django.conf import settings; print(settings.DEBUG)"
```

**Example: Running a Database Analysis Script**

```python
# scripts/analyze_db.py
import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'colmena.settings')
django.setup()

from django.contrib.auth import get_user_model
User = get_user_model()

# Now you can use Django ORM
print(f"Total users: {User.objects.count()}")
```

Run it with:
```bash
./scripts/run-in-environment.sh backend scripts/analyze_db.py
```

**Example: Testing Database Connectivity**

```python
# scripts/test_db.py
import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'colmena.settings')
django.setup()

from django.db import connection

with connection.cursor() as cursor:
    cursor.execute("SELECT version();")
    version = cursor.fetchone()
    print(f"PostgreSQL version: {version[0]}")
```

Run it with:
```bash
./scripts/run-in-environment.sh backend scripts/test_db.py
```

### Running Frontend Code

Use the `frontend` command for frontend operations:

```bash
# Start development server (for hot reload, run on host)
cd frontend && npm run dev -- --host 0.0.0.0 --port 3000

# Build for production
./scripts/run-in-environment.sh frontend build

# Run tests
./scripts/run-in-environment.sh frontend test

# Lint code
./scripts/run-in-environment.sh frontend lint
```

### Testing Infrastructure

Use the `test` command to run different test suites:

```bash
# Backend tests (Django)
./scripts/run-in-environment.sh test backend

# Frontend tests (React/Vitest)
./scripts/run-in-environment.sh test frontend

# Smoke tests (Playwright)
./scripts/run-in-environment.sh test smoke

# Infrastructure tests
./scripts/run-in-environment.sh test infra
```

The infrastructure test checks:
- All services are running (postgres, colmena-app, nextcloud, mail)
- Database connectivity
- Backend API health

### Interactive Shell

Drop into a shell in the running container:

```bash
./scripts/run-in-environment.sh shell
```

This gives you a shell where you can:
- Navigate the filesystem
- Run commands interactively
- Debug issues
- Inspect logs and configuration

### Execute Arbitrary Commands

Run any command in the container without starting an interactive shell:

```bash
# Execute Python code
./scripts/run-in-environment.sh exec python -c "print('Hello from container')"

# Check Django settings
./scripts/run-in-environment.sh exec python -c "from django.conf import settings; import json; print(json.dumps({k: v for k, v in vars(settings).items() if not k.startswith('_')}, indent=2))"

# List installed packages
./scripts/run-in-environment.sh exec pip list

# Check logs
./scripts/run-in-environment.sh exec tail -f /var/log/supervisor/colmena-app-stdout.log
```

### Managing the Stack

```bash
# Bring up the stack
./scripts/run-in-environment.sh up

# Build images before starting
./scripts/run-in-environment.sh up --build

# Bring up and keep running after script exits
./scripts/run-in-environment.sh up --keep-up

# Stop the stack
./scripts/run-in-environment.sh down

# Check stack status
./scripts/run-in-environment.sh status

# View logs
./scripts/run-in-environment.sh logs
./scripts/run-in-environment.sh logs colmena-app
./scripts/run-in-environment.sh logs postgres
```

## Environment Variables

All environment variables from `.env` are automatically loaded and available to your scripts:

```python
# In Python
import os
db_name = os.environ['POSTGRES_DATABASE']  # 'colmena'
debug_mode = os.environ['DEBUG']  # '1' or '0'
```

```javascript
// In Node.js
const dbName = process.env.POSTGRES_DATABASE; // 'colmena'
const debugMode = process.env.DEBUG; // '1' or '0'
```

## Common Use Cases

### 1. Database Operations

```bash
# Run raw SQL
./scripts/run-in-environment.sh backend python -c "
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'colmena.settings')
django.setup()

from django.db import connection
with connection.cursor() as cursor:
    cursor.execute('SELECT COUNT(*) FROM auth_user;')
    count = cursor.fetchone()[0]
    print(f'Total users: {count}')
"

# Create a backup
./scripts/run-in-environment.sh exec pg_dump -U colmena colmena > backup.sql
```

### 2. Model Inspection

```bash
# Inspect Django models
./scripts/run-in-environment.sh backend python -c "
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'colmena.settings')
django.setup()

from django.apps import apps
for model_name, model in apps.all_models.items():
    print(f'{model_name}.{model.__name__}')
"
```

### 3. API Testing

```bash
# Test API endpoints from inside the container
./scripts/run-in-environment.sh exec python -c "
import http.client
conn = http.client.HTTPConnection('localhost', '${BACKEND_PORT:-7100}')
conn.request('GET', '/api/')
response = conn.getresponse()
print(response.status, response.reason)
print(response.read().decode())
"
```

### 4. Log Analysis

```bash
# View application logs in real-time
./scripts/run-in-environment.sh exec tail -f /var/log/supervisor/colmena-app-stdout.log

# View nginx access logs
./scripts/run-in-environment.sh exec tail -f /var/log/nginx/access.log

# View error logs
./scripts/run-in-environment.sh exec tail -f /var/log/nginx/error.log
```

### 5. Debugging

```bash
# Start a Python debugger session
./scripts/run-in-environment.sh backend python -c "
import pdb; pdb.set_trace()
# Your code here - execution will pause at this line
"

# Inspect Django settings
./scripts/run-in-environment.sh backend manage.py diffsettings

# Check database migrations
./scripts/run-in-environment.sh backend manage.py showmigrations
```

## Example Scripts

### Python Script Example

See `scripts/run-code-example.py` for a complete example that:
- Tests database connectivity
- Checks Django models
- Validates environment variables
- Demonstrates ORM usage

Run it with:
```bash
./scripts/run-in-environment.sh backend scripts/run-code-example.py
```

### Node.js Script Example

See `scripts/test-infrastructure.js` for a complete example that:
- Tests HTTP endpoints
- Validates environment variables
- Checks Node.js capabilities
- Demonstrates database connectivity

Run it with:
```bash
./scripts/run-in-environment.sh exec node /opt/app/scripts/test-infrastructure.js
```

## Troubleshooting

### Port Conflicts

If ports are already in use:
```bash
# The script will auto-detect and suggest alternatives
# Or manually set different ports in .env:
HTTP_PORT=7181
BACKEND_PORT=7101
POSTGRES_HOST_PORT=7433
```

### Container Not Running

```bash
# Check container status
./scripts/run-in-environment.sh status

# Check logs for errors
./scripts/run-in-environment.sh logs colmena-app

# Ensure .env is properly configured
cat .env
```

### Database Connection Issues

```bash
# Verify database is running
./scripts/run-in-environment.sh exec pg_isready -U colmena

# Test from Python
./scripts/run-in-environment.sh backend python -c "
from django.db import connection
print('DB connection OK' if connection.cursor() else 'DB connection FAILED')
"
```

### Permission Issues

```bash
# Use exec instead of shell for one-off commands
./scripts/run-in-environment.sh exec "chmod +x /opt/app/my_script.sh && /opt/app/my_script.sh"
```

## Best Practices

1. **Use the script interface**: Always use `./scripts/run-in-environment.sh` instead of direct docker commands for consistency

2. **Leverage environment variables**: Access configuration through `os.environ` (Python) or `process.env` (Node.js)

3. **Use exec for one-liners**: For quick commands, use `./scripts/run-in-environment.sh exec`

4. **Create reusable scripts**: For complex operations, create Python or Node.js scripts in the `scripts/` directory

5. **Test with infra tests**: Run `./scripts/run-in-environment.sh test infra` before deploying changes

6. **Use shell for debugging**: When debugging, use `./scripts/run-in-environment.sh shell` for an interactive session

## Integration with IDEs

You can configure your IDE to use this script for running code:

### VSCode

Create `.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Run in Environment",
      "type": "shell",
      "command": "${workspaceFolder}/scripts/run-in-environment.sh",
      "args": ["backend", "${file}"],
      "group": "build",
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared"
      }
    }
  ]
}
```

### PyCharm

1. Go to Run → Edit Configurations
2. Create a new "Shell Script" configuration
3. Set script path: `${workspaceFolder}/scripts/run-in-environment.sh`
4. Set script parameters: `backend ${filePath}`
5. Set working directory: `${workspaceFolder}`

## Additional Resources

- [Django Documentation](https://docs.djangoproject.com/)
- [React Documentation](https://react.dev/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## Need Help?

Run with help flag for full command reference:
```bash
./scripts/run-in-environment.sh help
```
