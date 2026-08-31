# Base image: Alpine Linux-based OpenCode. Defaults intentionally follow latest.
FROM ghcr.io/anomalyco/opencode:latest

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
ARG UV_VERSION=latest
ARG UV_INSTALLER_SHA256=
ARG MARKSMAN_VERSION=latest
ARG MARKSMAN_SHA256_X86_64=
ARG MARKSMAN_SHA256_AARCH64=
ARG OPENCODE2_VERSION=0.0.0-beta-18743
ARG OPENCODE2_TARBALL_SHA512=20e9c365b0ecb02fd473ed7b3a19a808eee12afe554a817c78464af362c7ac1d2ecae760852c81f1a9ca5bd9e827a89d5d66c7432f0ddabfd73a689f26dd3804
ARG OPENCODE2_TARBALL_SHA512_X86_64=
ARG OPENCODE2_TARBALL_SHA512_AARCH64=2704d623c3d05f3aec95d6f2de9a4f781502ee224db04e4464154ee160de143de66f87ae5c5784a7c918a1b5121871de13094c32a486d312f888bea74b46c60a

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
    if [ "${UV_VERSION}" = "latest" ]; then \
        UV_INSTALLER_URL="https://astral.sh/uv/install.sh"; \
    else \
        UV_INSTALLER_URL="https://astral.sh/uv/${UV_VERSION}/install.sh"; \
    fi; \
    curl -fsSL "${UV_INSTALLER_URL}" -o /tmp/uv-installer.sh; \
    if [ -n "${UV_INSTALLER_SHA256}" ]; then \
        echo "${UV_INSTALLER_SHA256}  /tmp/uv-installer.sh" | sha256sum -c -; \
    fi; \
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
    if [ "${MARKSMAN_VERSION}" = "latest" ]; then \
        MARKSMAN_URL="https://github.com/artempyanykh/marksman/releases/latest/download/marksman-${MARKSMAN_ARCH}"; \
    else \
        MARKSMAN_URL="https://github.com/artempyanykh/marksman/releases/download/${MARKSMAN_VERSION}/marksman-${MARKSMAN_ARCH}"; \
    fi; \
    curl -fsSL "${MARKSMAN_URL}" \
        -o /usr/local/bin/marksman; \
    if [ -n "${MARKSMAN_SHA256}" ]; then \
        echo "${MARKSMAN_SHA256}  /usr/local/bin/marksman" | sha256sum -c -; \
    fi; \
    chmod +x /usr/local/bin/marksman

# Install the pinned OpenCode 2.0 preview CLI alongside the stable `opencode`
# binary supplied by the base image. npm publishes different verified musl
# artifacts for x86_64 and arm64; stable image builds remain supported on both.
RUN set -eu; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
        x86_64) \
            OPENCODE2_PACKAGE="cli-linux-x64-baseline-musl"; \
            OPENCODE2_SHA512="${OPENCODE2_TARBALL_SHA512_X86_64:-${OPENCODE2_TARBALL_SHA512}}"; \
            ;; \
        aarch64) \
            OPENCODE2_PACKAGE="cli-linux-arm64-musl"; \
            OPENCODE2_SHA512="${OPENCODE2_TARBALL_SHA512_AARCH64}"; \
            ;; \
        *) \
            echo "OpenCode 2 preview has no pinned musl artifact for this architecture (found: $ARCH)" >&2; \
            exit 1; \
            ;; \
    esac; \
    test -n "$OPENCODE2_SHA512"; \
    OPENCODE2_URL="https://registry.npmjs.org/@opencode-ai/${OPENCODE2_PACKAGE}/-/${OPENCODE2_PACKAGE}-${OPENCODE2_VERSION}.tgz"; \
    curl -fsSL "$OPENCODE2_URL" -o /tmp/opencode2.tgz; \
    echo "${OPENCODE2_SHA512}  /tmp/opencode2.tgz" | sha512sum -c -; \
    mkdir -p /tmp/opencode2; \
    tar -xzf /tmp/opencode2.tgz -C /tmp/opencode2; \
    package_name="$(sed -n 's/.*"name": "\([^"]*\)".*/\1/p' /tmp/opencode2/package/package.json | head -n 1)"; \
    package_version="$(sed -n 's/.*\"version\": \"\([^\"]*\)\".*/\1/p' /tmp/opencode2/package/package.json | head -n 1)"; \
    test "$package_name" = "@opencode-ai/$OPENCODE2_PACKAGE"; \
    test "$package_version" = "$OPENCODE2_VERSION"; \
    test -x /tmp/opencode2/package/bin/opencode2; \
    install -m 0755 /tmp/opencode2/package/bin/opencode2 /usr/local/bin/opencode2; \
    rm -rf /tmp/opencode2 /tmp/opencode2.tgz

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
