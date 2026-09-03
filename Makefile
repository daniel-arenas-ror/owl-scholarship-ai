COMPOSE := docker compose

.DEFAULT_GOAL := help
.PHONY: help setup up down restart build logs ps \
        sh-api sh-admin sh-web db \
        test test-api test-admin test-web fmt lint clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## One-time: build images and prepare the database
	@test -f .env || (cp .env.example .env && echo "created .env — add your OPENAI_API_KEY")
	$(COMPOSE) build
	$(COMPOSE) run --rm admin bin/rails db:prepare
	@echo "setup complete — run 'make up'"

up: ## Start Postgres + all three services
	$(COMPOSE) up

down: ## Stop and remove containers
	$(COMPOSE) down

restart: ## Recreate all services
	$(COMPOSE) up -d --force-recreate

build: ## Rebuild all images
	$(COMPOSE) build

logs: ## Tail logs from every service
	$(COMPOSE) logs -f --tail=100

ps: ## Show running services
	$(COMPOSE) ps

sh-api: ## Shell into owl-api
	$(COMPOSE) exec api bash

sh-admin: ## Shell into owl-admin
	$(COMPOSE) exec admin bash

sh-web: ## Shell into owl-web
	$(COMPOSE) exec web sh

db: ## psql into the Postgres container
	$(COMPOSE) exec postgres psql -U owl -d owl

test: test-api test-admin test-web ## Run every test suite

test-api: ## Run owl-api tests
	$(COMPOSE) run --rm api pytest

test-admin: ## Run owl-admin tests
	$(COMPOSE) run --rm admin bin/rails test

test-web: ## Run owl-web tests
	$(COMPOSE) run --rm web npm test --silent

fmt: ## Format every project
	$(COMPOSE) run --rm api ruff format .
	$(COMPOSE) run --rm admin bin/rubocop -A
	$(COMPOSE) run --rm web npm run format

lint: ## Lint every project
	$(COMPOSE) run --rm api ruff check .
	$(COMPOSE) run --rm admin bin/rubocop
	$(COMPOSE) run --rm web npm run lint

clean: ## Remove containers, volumes, and build artifacts
	$(COMPOSE) down -v --remove-orphans
