#!/usr/bin/env bash

prepare_opencode_tui_args() {
    local index argument
    for argument in "${ARGS[@]}"; do
        case "$argument" in --standalone|--server|--server=*) return ;; esac
    done
    for ((index = 0; index < ${#ARGS[@]}; index++)); do
        argument="${ARGS[index]}"
        case "$argument" in
            --standalone|--server|--server=*|--help|-h|--version|-v|--completions|--wizard)
                return ;;
            --session|-s|--prompt|--log-level)
                index=$((index + 1)) ;;
            --) break ;;
            -*) ;;
            acp|api|auth|debug|mcp|plugin|models|stats|mini|run|session|service|reload|pair|serve|upgrade|update|uninstall)
                return ;;
            *) break ;;
        esac
    done
    ARGS=(--standalone "${ARGS[@]}")
}
