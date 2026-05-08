#!/usr/bin/env bash
set -u

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

install_apt_tools() {
  have apt-get || return 0

  local packages=()
  have bat || have batcat || packages+=(bat)
  have jq || packages+=(jq)
  have tldr || packages+=(tldr)
  have tree || packages+=(tree)

  [ "${#packages[@]}" -gt 0 ] || return 0

  log "installing apt packages: ${packages[*]}"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update &&
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}" ||
    warn "apt install failed"
}

install_chezmoi() {
  have chezmoi && return 0

  log "installing chezmoi"
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" ||
    warn "chezmoi install failed"
}

install_starship() {
  have starship && return 0

  log "installing starship"
  curl -fsSL https://starship.rs/install.sh |
    sh -s -- --yes --bin-dir "$HOME/.local/bin" ||
    warn "starship install failed"
}

install_zellij() {
  have zellij && return 0

  local arch
  case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *)
      warn "unsupported architecture for zellij: $(uname -m)"
      return 0
      ;;
  esac

  local dir archive
  dir=$(mktemp -d "${TMPDIR:-/tmp}/zellij.XXXXXX") || return 0
  archive="$dir/zellij.tar.gz"

  log "installing zellij"
  if curl -fsSL -o "$archive" "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz" &&
    tar -xzf "$archive" -C "$dir" &&
    cp "$dir/zellij" "$HOME/.local/bin/zellij"; then
    chmod +x "$HOME/.local/bin/zellij"
  else
    warn "zellij install failed"
  fi

  rm -rf "$dir"
}

use_zsh_shell() {
  have zsh || {
    warn "zsh not found; leaving login shell unchanged"
    return 0
  }

  sudo chsh "$(id -un)" --shell "$(command -v zsh)" ||
    warn "failed to set login shell to zsh"
}

install_ubuntu_tools() {
  mkdir -p "$HOME/.local/bin"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac

  install_apt_tools
  install_chezmoi
  install_starship
  install_zellij
  use_zsh_shell
}

apply_dotfiles() {
  have chezmoi || {
    warn "chezmoi is not installed; cannot apply dotfiles"
    return 1
  }

  log "applying chezmoi source"
  chezmoi apply --source "$script_dir"
}

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"

case "$(uname -s)" in
  Darwin)
    apply_dotfiles
    ;;
  Linux)
    if [ -r /etc/os-release ] && grep -Eq '(^ID=ubuntu$|^ID_LIKE=.*ubuntu|^ID_LIKE=.*debian)' /etc/os-release; then
      install_ubuntu_tools
    else
      warn "unsupported Linux distribution; skipping package installation"
    fi
    apply_dotfiles
    ;;
  *)
    warn "unsupported OS: $(uname -s)"
    apply_dotfiles
    ;;
esac
