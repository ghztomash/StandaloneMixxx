#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ghztomash/FLX-Mixxx.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
REPO_DIR="${REPO_DIR:-$HOME/.local/share/standalone-mixxx/FLX-Mixxx}"
CONTROLLERS_DIR="${CONTROLLERS_DIR:-$HOME/.mixxx/controllers}"

declare -a CONTROLLER_SOURCES=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [--remove|--help]

Install or update the FLX-Mixxx controller mapping checkout and symlink its
top-level .js and .xml files into $CONTROLLERS_DIR.

Options:
  --remove  Remove managed controller symlinks. Delete the managed checkout
            only if it is clean.
  --help    Show this help text.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  local cmd="$1"

  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

ensure_prerequisites() {
  require_command git
  require_command readlink
}

collect_controller_sources() {
  shopt -s nullglob
  CONTROLLER_SOURCES=("$REPO_DIR"/*.js "$REPO_DIR"/*.xml)
  shopt -u nullglob

  [ "${#CONTROLLER_SOURCES[@]}" -gt 0 ] || die "No top-level .js or .xml controller files found in $REPO_DIR"
}

managed_link_path() {
  local path="$1"
  local raw_target
  local resolved_target

  [ -L "$path" ] || return 1

  raw_target=$(readlink "$path")
  case "$raw_target" in
    "$REPO_DIR"/*) return 0 ;;
  esac

  resolved_target=$(readlink -f "$path" 2>/dev/null || true)
  case "$resolved_target" in
    "$REPO_DIR"/*) return 0 ;;
  esac

  return 1
}

ensure_clean_checkout() {
  local origin_url
  local current_branch
  local repo_status

  [ -d "$REPO_DIR/.git" ] || die "Existing path is not a git repository: $REPO_DIR"

  origin_url=$(git -C "$REPO_DIR" config --get remote.origin.url || true)
  [ "$origin_url" = "$REPO_URL" ] || die "Existing repository origin mismatch at $REPO_DIR. Expected $REPO_URL but found ${origin_url:-<none>}"

  current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
  [ "$current_branch" = "$REPO_BRANCH" ] || die "Existing repository must be on branch $REPO_BRANCH, found $current_branch at $REPO_DIR"

  repo_status=$(git -C "$REPO_DIR" status --porcelain)
  [ -z "$repo_status" ] || die "Existing repository has local changes at $REPO_DIR. Commit, stash, or discard them before rerunning."
}

clone_or_update_repo() {
  mkdir -p "$(dirname "$REPO_DIR")" "$CONTROLLERS_DIR"

  if [ ! -e "$REPO_DIR" ]; then
    printf 'Cloning controller repository into %s\n' "$REPO_DIR"
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
    return
  fi

  ensure_clean_checkout

  printf 'Updating controller repository in %s\n' "$REPO_DIR"
  git -C "$REPO_DIR" fetch origin "$REPO_BRANCH"
  git -C "$REPO_DIR" merge --ff-only FETCH_HEAD
}

verify_install_targets() {
  local source
  local target
  local link_target
  local resolved_target

  for source in "${CONTROLLER_SOURCES[@]}"; do
    target="$CONTROLLERS_DIR/$(basename "$source")"

    if [ -L "$target" ]; then
      link_target=$(readlink "$target")
      resolved_target=$(readlink -f "$target" 2>/dev/null || true)

      if [ "$link_target" = "$source" ] || [ "$resolved_target" = "$source" ]; then
        continue
      fi

      die "Controller target already points elsewhere: $target -> $link_target"
    fi

    if [ -e "$target" ]; then
      die "Controller target already exists and is not a managed symlink: $target"
    fi
  done
}

install_symlinks() {
  local source
  local target
  local link_target
  local resolved_target

  verify_install_targets

  for source in "${CONTROLLER_SOURCES[@]}"; do
    target="$CONTROLLERS_DIR/$(basename "$source")"

    if [ -L "$target" ]; then
      link_target=$(readlink "$target")
      resolved_target=$(readlink -f "$target" 2>/dev/null || true)

      if [ "$link_target" = "$source" ] || [ "$resolved_target" = "$source" ]; then
        printf 'Keeping existing symlink %s\n' "$target"
        continue
      fi
    fi

    ln -s "$source" "$target"
    printf 'Linked %s -> %s\n' "$target" "$source"
  done
}

remove_symlinks() {
  local path
  local removed=0

  [ -d "$CONTROLLERS_DIR" ] || return 0

  shopt -s nullglob
  for path in "$CONTROLLERS_DIR"/*; do
    if managed_link_path "$path"; then
      rm "$path"
      printf 'Removed symlink %s\n' "$path"
      removed=1
    fi
  done
  shopt -u nullglob

  if [ "$removed" -eq 0 ]; then
    printf 'No managed controller symlinks found in %s\n' "$CONTROLLERS_DIR"
  fi
}

remove_checkout_if_clean() {
  local repo_status

  [ -e "$REPO_DIR" ] || return 0
  [ -d "$REPO_DIR/.git" ] || die "Managed checkout path exists but is not a git repository: $REPO_DIR"

  repo_status=$(git -C "$REPO_DIR" status --porcelain)
  if [ -n "$repo_status" ]; then
    printf 'Keeping checkout with local changes: %s\n' "$REPO_DIR"
    return 0
  fi

  rm -rf "$REPO_DIR"
  printf 'Removed clean checkout %s\n' "$REPO_DIR"
}

install() {
  clone_or_update_repo
  collect_controller_sources
  install_symlinks
}

remove_installation() {
  remove_symlinks
  remove_checkout_if_clean
}

main() {
  ensure_prerequisites

  case "${1:-}" in
    "")
      install
      ;;
    --remove)
      remove_installation
      ;;
    --help)
      usage
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
