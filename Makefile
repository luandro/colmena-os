.PHONY: help up-local down-local test-local clean-ports prod-up prod-down prod-logs logs-app logs-local

COMPOSE_FILE ?= docker-compose.local.yml
PROJECT_NAME ?= colmena

help:
	@echo "Available targets:"
	@echo "  up-local      - Build and start local compose in background"
	@echo "  down-local    - Stop local compose and remove orphans"
	@echo "  test-local    - Run scripts/test-compose-local.sh (health + curl checks)"
	@echo "  clean-ports   - List or kill processes on required dev ports (FORCE=1 to kill)"
	@echo "  prod-up       - Start production compose (docker-compose.yml)"
	@echo "  prod-down     - Stop production compose and remove orphans"
	@echo "  prod-logs     - Tail colmena-app logs (production compose)"
	@echo "  logs-local    - Tail colmena-app logs (local compose)"

up-local:
	bash scripts/up-local.sh

down-local:
	docker compose -f $(COMPOSE_FILE) --project-name $(PROJECT_NAME) down --remove-orphans

test-local:
	bash scripts/test-compose-local.sh

clean-ports:
	@bash scripts/cleanup-local-ports.sh

# Production compose (docker-compose.yml)
prod-up:
	docker compose -f docker-compose.yml --project-name colmena-os up -d

prod-down:
	docker compose -f docker-compose.yml --project-name colmena-os down --remove-orphans

prod-logs:
	docker compose -f docker-compose.yml --project-name colmena-os logs -f colmena-app

# Log tail helpers
logs-local:
	docker compose -f $(COMPOSE_FILE) --project-name $(PROJECT_NAME) logs -f colmena-app
