# Base image: Alpine Linux-based OpenCode
FROM ghcr.io/anomalyco/opencode

USER root

# OCI Labels
LABEL org.opencontainers.image.title="opencode-containment"
LABEL org.opencontainers.image.description="Secure, native-feeling containerized development environment for OpenCode"
LABEL org.opencontainers.image.source="https://github.com/christian-taillon/opencode-containment"

# Build arguments
ARG RUST_TOOLCHAIN=stable

# Environment variables
ENV UV_INSTALL_DIR=/usr/local/bin
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:/usr/local/bin:${PATH}

# Install system dependencies (Alpine)
RUN set -eu; \
    for attempt in 1 2 3 4 5; do \
        if apk add --no-cache \
            bash \
            zsh \
            ca-certificates \
            curl \
            openssh-client \
            gnupg \
            git \
            github-cli \
            neovim \
            python3 \
            py3-pip \
            py3-virtualenv \
            nodejs \
            npm \
            make \
            jq \
            pkgconf \
            build-base \
            openssl-dev \
            ripgrep \
            fd \
            fzf \
            bat \
            eza \
            zoxide \
            direnv \
            git-crypt \
            sops \
            gcompat \
            libc6-compat; then \
            exit 0; \
        fi; \
        echo "apk add failed (attempt ${attempt}/5); retrying in 5s..." >&2; \
        sleep 5; \
    done; \
    echo "apk add failed after 5 attempts" >&2; \
    exit 1

# Ensure python is available as a command
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Install uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Rust and Cargo
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}" \
    && chmod -R a+rX "${RUSTUP_HOME}" "${CARGO_HOME}" \
    && rustc --version \
    && cargo --version \
    && uv --version

# Install marksman (Markdown LSP server) — used by LazyVim for Markdown files
RUN ARCH="$(uname -m)" && \
    case "$ARCH" in \
        x86_64)  MARKSMAN_ARCH="linux-x64" ;; \
        aarch64) MARKSMAN_ARCH="linux-arm64" ;; \
        *)       echo "Unsupported arch: $ARCH"; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/artempyanykh/marksman/releases/latest/download/marksman-${MARKSMAN_ARCH}" \
        -o /usr/local/bin/marksman && \
    chmod +x /usr/local/bin/marksman

# Install nvim wrapper to ensure runtimepath is set correctly
COPY scripts/nvim-wrapper /usr/local/bin/nvim
RUN chmod +x /usr/local/bin/nvim

# Pre-create the parser directory inside the image so native configs can
# install parsers without any extra runtime bootstrap script.
RUN mkdir -p /home/opencode/.local/share/nvim/site/parser \
    && chown -R 1000:1000 /home/opencode/.local/share/nvim

# Install startup entrypoint that enforces containment behavior
COPY scripts/container-init.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
