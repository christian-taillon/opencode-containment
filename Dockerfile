# Base image: Alpine Linux-based OpenCode
FROM ghcr.io/anomalyco/opencode

USER root

# OCI Labels
LABEL org.opencontainers.image.title="opencode-containment"
LABEL org.opencontainers.image.description="Secure, native-feeling containerized development environment for OpenCode"
LABEL org.opencontainers.image.source="https://github.com/christian-taillon/opencode-containment"

# Build arguments
ARG RUST_TOOLCHAIN=stable
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG all_proxy
ARG no_proxy
ARG NODE_EXTRA_CA_CERTS
ARG EXTRA_APK_PACKAGES=
ARG OPENCODE_BUILD_EXTRA_APK_PACKAGES=
ARG UV_VERSION=0.11.0
ARG UV_INSTALLER_SHA256=90a46cecbc558ed0a50e50cc0b5775fba8346f362e67ed8da7daf0018261048d
ARG MARKSMAN_VERSION=2026-02-08
ARG MARKSMAN_SHA256_X86_64=d33df4544bb1f9f1b93b862ea78375ca8c04cd467ed2bcee354d605fc483ceee
ARG MARKSMAN_SHA256_AARCH64=cd3b91b630042cc09b20505583203f875fbb4bf2fdf74dd6d87fddc3238d2798

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

# Optional local-only extra Alpine packages.
# `EXTRA_APK_PACKAGES` is intended to come from the local hook via the build script.
RUN set -eu; \
    extra_packages="${EXTRA_APK_PACKAGES:-${OPENCODE_BUILD_EXTRA_APK_PACKAGES:-}}"; \
    if [ -z "$extra_packages" ]; then \
        exit 0; \
    fi; \
    if apk add --no-cache $extra_packages; then \
        exit 0; \
    fi; \
    echo "Failed to install requested extra Alpine packages: $extra_packages" >&2; \
    echo "Check package names in opencode-local.sh and rebuild." >&2; \
    exit 1

# Ensure python is available as a command
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Install uv (Python package manager)
RUN set -eu; \
    curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" -o /tmp/uv-installer.sh; \
    echo "${UV_INSTALLER_SHA256}  /tmp/uv-installer.sh" | sha256sum -c -; \
    sh /tmp/uv-installer.sh; \
    rm -f /tmp/uv-installer.sh

# Install Rust and Cargo
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}" \
    && chmod -R a+rX "${RUSTUP_HOME}" "${CARGO_HOME}" \
    && rustc --version \
    && cargo --version \
    && uv --version

# Install marksman (Markdown LSP server) — used by LazyVim for Markdown files
RUN set -eu; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
        x86_64) \
            MARKSMAN_ARCH="linux-musl-x64"; \
            MARKSMAN_SHA256="${MARKSMAN_SHA256_X86_64}"; \
            ;; \
        aarch64) \
            MARKSMAN_ARCH="linux-musl-arm64"; \
            MARKSMAN_SHA256="${MARKSMAN_SHA256_AARCH64}"; \
            ;; \
        *) \
            echo "Unsupported arch: $ARCH" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl -fsSL "https://github.com/artempyanykh/marksman/releases/download/${MARKSMAN_VERSION}/marksman-${MARKSMAN_ARCH}" \
        -o /usr/local/bin/marksman; \
    echo "${MARKSMAN_SHA256}  /usr/local/bin/marksman" | sha256sum -c -; \
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
