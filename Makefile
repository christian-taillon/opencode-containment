.PHONY: help build setup run run-native run-secure run-sandbox doctor doctor-sandbox clean clean-sandbox-smoke shell-install

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
	IMAGE_NAME=$(IMAGE_NAME) bash scripts/build-image.sh

setup: ## Create persistent directories for container cache/state
	@echo "Running setup..."
	@mkdir -p $(OPENCODE_CONTAINER_HOME)/cache $(OPENCODE_CONTAINER_HOME)/local
	@echo "Setup complete."

run: ## Run container with native profile (best UX)
	@bash bin/opencode-container --profile native

run-secure: ## Run container with secure profile
	@bash bin/opencode-container --profile secure

run-native: ## Run with native profile
	@bash bin/opencode-container --profile native

run-sandbox: ## Run the sandbox backend with Docker Sandboxes
	@bash bin/opencode-sandbox --profile native

doctor: ## Check prerequisites
	@echo "Checking prerequisites..."
	@command -v docker >/dev/null 2>&1 && echo "✅ Docker is installed" || echo "❌ Docker is not installed"
	@docker image inspect $(IMAGE_NAME) >/dev/null 2>&1 && echo "✅ Image $(IMAGE_NAME) is built" || echo "❌ Image $(IMAGE_NAME) is not built"
	@[ -n "$$SSH_AUTH_SOCK" ] && [ -S "$$SSH_AUTH_SOCK" ] && echo "✅ SSH agent is running" || echo "⚠️ SSH agent is not running or socket not found"
	@[ -d "$(OPENCODE_CONTAINER_HOME)" ] && echo "✅ Persistent directory exists" || echo "❌ Persistent directory does not exist"
	@[ -f "$(HOME)/.local/share/opencode/auth.json" ] && echo "✅ Host OpenCode auth detected" || echo "⚠️ Host OpenCode auth not detected"

doctor-sandbox: ## Check Docker Sandboxes (sbx) prerequisites
	@echo "Checking sandbox prerequisites..."
	@command -v sbx >/dev/null 2>&1 && echo "✅ sbx is installed" || echo "❌ sbx is not installed"
	@sbx daemon status >/dev/null 2>&1 && echo "✅ sbx daemon is running" || echo "❌ sbx daemon is not running"
	@command -v mkfs.ext4 >/dev/null 2>&1 && echo "✅ mkfs.ext4 is available" || echo "❌ mkfs.ext4 is not in PATH"
	@command -v mkfs.erofs >/dev/null 2>&1 && echo "✅ mkfs.erofs is available" || echo "❌ mkfs.erofs is not in PATH"
	@id -nG | tr ' ' '\n' | grep -qx kvm && echo "✅ User is in kvm group" || echo "❌ User is not in kvm group in this shell"
	@[ -r /dev/kvm ] && echo "✅ /dev/kvm is accessible" || echo "❌ /dev/kvm is not accessible from this shell"

clean: ## Remove generated files and persistent data (with confirmation)
	@read -p "Are you sure you want to remove generated files and persistent data? [y/N] " ans; \
	if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
		rm -rf $(OPENCODE_CONTAINER_HOME); \
		echo "Cleaned up."; \
	else \
		echo "Aborted."; \
	fi

clean-sandbox-smoke: ## Remove the default named smoke-test sandbox
	@PATH="$$HOME/.docker/sbx/bin:$$HOME/.docker/sbx/libexec:/usr/sbin:/sbin:$$PATH"; \
	if command -v sbx >/dev/null 2>&1; then \
		sbx rm -f opencode-containment-smoke >/dev/null 2>&1 && echo "Removed sandbox opencode-containment-smoke" || echo "No sandbox named opencode-containment-smoke to remove"; \
	else \
		echo "sbx is not installed"; \
	fi

shell-install: ## Install opencode launchers to ~/.local/bin (symlinks)
	@mkdir -p $(HOME)/.local/bin
	@ln -sf $(PWD)/bin/opencode-container $(HOME)/.local/bin/opencode-container
	@ln -sf $(PWD)/bin/opencode-sandbox $(HOME)/.local/bin/opencode-sandbox
	@echo "Installed opencode-container to $(HOME)/.local/bin/opencode-container"
	@echo "Installed opencode-sandbox to $(HOME)/.local/bin/opencode-sandbox"
