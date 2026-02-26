# syntax=docker/dockerfile:1

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
RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    neovim \
    python3 \
    py3-pip \
    py3-virtualenv \
    make \
    jq \
    pkgconf \
    build-base \
    openssl-dev \
    ripgrep \
    fd \
    gcompat \
    libc6-compat

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

# Install startup entrypoint that enforces containment behavior
COPY scripts/container-init.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
