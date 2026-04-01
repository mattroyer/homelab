SCRIPTS_DIR := ./scripts

.PHONY: bootstrap render doctor validate up force-up down backup help

help:
	@echo "Makefile targets:"
	@echo "  make bootstrap  - create .env, render configs, and prep the starter stack"
	@echo "  make render     - regenerate Traefik, homepage, and other derived config files"
	@echo "  make doctor     - check local prerequisites and current .env choices"
	@echo "  make validate   - run compose validation for all compose files"
	@echo "  make up         - docker compose up -d for the beginner-safe starter stack"
	@echo "  make force-up   - docker compose up -d (root compose) ---force-recreate"
	@echo "  make down       - docker compose down"
	@echo "  make backup     - run backup script for named volumes (see scripts/backup-volumes.sh)"

bootstrap:
	@$(SCRIPTS_DIR)/bootstrap.sh

render:
	@$(SCRIPTS_DIR)/render-configs.sh

doctor:
	@$(SCRIPTS_DIR)/doctor.sh

validate:
	@$(SCRIPTS_DIR)/validate-compose.sh

up:
	@docker compose up -d $(filter-out $@,$(MAKECMDGOALS))

force-up:
	@docker compose up -d $(filter-out $@,$(MAKECMDGOALS)) --force-recreate

down:
	@docker compose down $(filter-out $@,$(MAKECMDGOALS))

backup:
	@chmod +x $(SCRIPTS_DIR)/backup-volumes.sh || true
	@$(SCRIPTS_DIR)/backup-volumes.sh

%:
	@:
