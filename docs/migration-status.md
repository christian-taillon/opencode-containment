# Migration Status and Handoff

This document captures the current migration status, key fixes made on this host, and what to validate on the next host.

## Objective

Ship a secure, native-feeling OpenCode container workflow with host Neovim config compatibility and clear operational handoff.

## Completed Work

- Project scaffold and tooling (`bin/`, `config/`, `scripts/`, `Makefile`, `README`, `LICENSE`, `.gitignore`)
- Hardened Docker runtime wrapper with profile support (`secure`, `native`)
- Alpine-compatible Docker image and core dev tooling
- Native Neovim host mount strategy (read-only config/plugins with writable persistent state)
- Tree-sitter bootstrap and parser persistence workflow
- Markdown LSP (`marksman`) install and compatibility hardening
- Compatibility additions for prebuilt binaries on Alpine (`gcompat`, `libc6-compat`)

## Recent Change Log (Head)

- `f3a5481` fix: add gcompat for binary compatibility, nvim wrapper for runtimepath, and blink.cmp overlay
- `b3aad40` fix: redirect tree-sitter parser install to writable site/parser dir
- `f6b1de0` fix: writable parser overlay for nvim-treesitter + add marksman LSP
- `3b13fdb` fix: add tree-sitter parser auto-compilation for Alpine/musl container
- `d5a7d2d` fix: native Neovim experience and defaults

## Known Constraints

- Host-specific plugin binary artifacts can still vary across machines (especially prebuilt native plugin components).
- First-run parser/bootstrap actions may take longer due to compile/setup behavior.
- Clipboard behavior in terminal Neovim depends on terminal capabilities on the target host.

## Migration Steps for New Host

1. Install prerequisites: Docker, bash, zsh.
2. Clone repo and build image:
   - `make build`
3. Initialize local runtime directories/config:
   - `make setup`
4. Optional diagnostics:
   - `make doctor`
5. Run native profile:
   - `make run`

## Validation Checklist on New Host

- OpenCode launches and can access mounted workspace
- Neovim starts with no blocking startup errors
- Markdown buffer opens and parser-dependent plugins initialize
- Markdown LSP (`marksman`) attaches in markdown files
- Git/SSH agent forwarding works for repo operations

## If Something Fails

- Rebuild image: `make build`
- Re-run setup: `make setup`
- Re-test in native mode: `make run`
- Compare with `bin/opencode-container`, `scripts/container-init.sh`, and `Dockerfile` behavior in this repo
