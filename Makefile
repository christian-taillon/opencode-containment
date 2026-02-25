.PHONY: help build setup run run-native doctor clean shell-install

# Project variables
PROJECT_NAME := opencode-containment
IMAGE_NAME := opencode-containment:latest
OPENCODE_CONTAINER_HOME ?= $(HOME)/.local/share/opencode-container

help: ## Show all targets with descriptions
	@echo "========================================"
	@echo " $(PROJECT_NAME) Makefile"
	@echo "========================================"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the Docker image as opencode-containment:latest
	docker build -t $(IMAGE_NAME) .

setup: ## Run scripts/generate-container-zshrc.sh + create persistent dirs + validate
	@echo "Running setup..."
	@bash scripts/generate-container-zshrc.sh
	@mkdir -p $(OPENCODE_CONTAINER_HOME)/cache $(OPENCODE_CONTAINER_HOME)/state
	@echo "Setup complete."

run: ## Run container with secure profile
	@bash bin/opencode-container --profile secure

run-native: ## Run with native profile
	@bash bin/opencode-container --profile native

doctor: ## Check prerequisites
	@echo "Checking prerequisites..."
	@command -v docker >/dev/null 2>&1 && echo "✅ Docker is installed" || echo "❌ Docker is not installed"
	@docker image inspect $(IMAGE_NAME) >/dev/null 2>&1 && echo "✅ Image $(IMAGE_NAME) is built" || echo "❌ Image $(IMAGE_NAME) is not built"
	@[ -n "$$SSH_AUTH_SOCK" ] && [ -S "$$SSH_AUTH_SOCK" ] && echo "✅ SSH agent is running" || echo "⚠️ SSH agent is not running or socket not found"
	@[ -d "$(OPENCODE_CONTAINER_HOME)" ] && echo "✅ Persistent directory exists" || echo "❌ Persistent directory does not exist"

clean: ## Remove generated files and persistent data (with confirmation)
	@read -p "Are you sure you want to remove generated files and persistent data? [y/N] " ans; \
	if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
		rm -f .zshrc.local; \
		rm -rf $(OPENCODE_CONTAINER_HOME); \
		echo "Cleaned up."; \
	else \
		echo "Aborted."; \
	fi

shell-install: ## Install the opencode-container command to ~/.local/bin (symlink)
	@mkdir -p $(HOME)/.local/bin
	@ln -sf $(PWD)/bin/opencode-container $(HOME)/.local/bin/opencode-container
	@echo "Installed opencode-container to $(HOME)/.local/bin/opencode-container"
