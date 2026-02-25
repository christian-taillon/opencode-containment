# syntax=docker/dockerfile:1

# Base image
FROM ghcr.io/anomalyco/opencode

USER root

# OCI Labels
LABEL org.opencontainers.image.title="opencode-containment"
LABEL org.opencontainers.image.description="Secure, native-feeling containerized development environment for OpenCode"
LABEL org.opencontainers.image.source="https://github.com/christian-taillon/opencode-containment"

# Build arguments
ARG RUST_TOOLCHAIN=stable

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV UV_INSTALL_DIR=/usr/local/bin
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:/usr/local/bin:${PATH}

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    neovim \
    python3 \
    python3-pip \
    python3-venv \
    make \
    jq \
    pkg-config \
    build-essential \
    libssl-dev \
    ripgrep \
    fd-find \
    && rm -rf /var/lib/apt/lists/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && chmod 755 /usr/local/bin/uv /usr/local/bin/uvx

# Install Rust and Cargo
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}" \
    && chmod -R a+rX "${RUSTUP_HOME}" "${CARGO_HOME}" \
    && rustc --version \
    && cargo --version \
    && uv --version
