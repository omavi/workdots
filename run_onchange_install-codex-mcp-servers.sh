#!/usr/bin/env bash
#
# Why this script exists
# ----------------------
# Codex CLI's MCP config lives in ~/.codex/config.toml, alongside per-machine
# state like [projects.*] trust levels and [tui.*] UI nudge counters that we
# don't want in chezmoi. Instead, this script is the source of truth for which
# MCP servers Codex has registered, and chezmoi runs it on apply (whenever
# its contents change) to converge the config to match.
#
# How to use it
# -------------
# Edit the `servers` array below. Run `chezmoi apply`. After the script runs,
# complete the OAuth flow in the browser tabs Codex opens for each server
# (`codex mcp login <name>` is the manual fallback if a flow doesn't open).
#
# Idempotency
# -----------
# Each entry runs `codex mcp remove` (failure ignored — server may not exist
# yet) then `codex mcp add`. The remove is there because:
#   - `codex mcp add` errors if a server with that name already exists, so
#     a bare `add` is not safely re-runnable.
#   - If a URL in the array changes, a no-op `add` would silently leave the
#     server pointing at the stale URL forever.
#   - The same applies to any future flag (timeouts, headers, tool filters)
#     we might wire into the array — remove+add reliably re-applies it.
#
# Trade-off: every `codex mcp add` triggers an OAuth flow if the server
# supports it, so each run of this script reauthenticates every listed
# server in the browser. We accept that because the script only re-runs
# when its own contents change (chezmoi tracks the hash), which is rare.
#
# What this does NOT do: prune servers removed from the array. Deleting a
# line above does not delete the server from ~/.codex/config.toml — run
# `codex mcp remove <name>` manually if you want it gone.
#

set -euo pipefail

# Bail in non-interactive shells (CI, GitHub Codespaces, Ona, container builds).
# `codex mcp add` auto-launches an OAuth flow that waits for a 127.0.0.1
# browser callback — with no TTY and no browser, the call hangs forever and
# blocks `chezmoi apply`. After landing in an interactive session, re-run this
# script manually (`bash ~/.local/share/chezmoi/run_onchange_install-codex-mcp-servers.sh`)
# to register the MCP servers.
if [ ! -t 0 ]; then
    echo "Non-interactive shell; skipping Codex MCP server registration." >&2
    exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "codex CLI not found on PATH; skipping MCP server registration." >&2
    exit 0
fi

# Source of truth: "name|url". Edit this list and re-apply chezmoi.
servers=(
    "glean|https://vanta-be.glean.com/mcp/default"
    "guru|https://mcp.api.getguru.com/mcp"
    "incident-io|https://mcp.incident.io/mcp"
    "datadog|https://mcp.datadoghq.com/api/unstable/mcp-server/mcp"
)

for entry in "${servers[@]}"; do
    IFS='|' read -r name url <<<"$entry"
    codex mcp remove "$name" >/dev/null 2>&1 || true
    codex mcp add "$name" --url "$url"
done

echo "Done."
