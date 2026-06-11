#!/usr/bin/env bash
set -euo pipefail

CONTROLLER_REPO_URL="${CONTROLLER_REPO_URL:-${REPO_URL:-https://github.com/ghztomash/FLX-Mixxx.git}}"
CONTROLLER_REPO_BRANCH="${CONTROLLER_REPO_BRANCH:-${REPO_BRANCH:-main}}"
CONTROLLER_REPO_DIR="${CONTROLLER_REPO_DIR:-${REPO_DIR:-$HOME/.local/share/standalone-mixxx/FLX-Mixxx}}"
CONTROLLERS_DIR="${CONTROLLERS_DIR:-$HOME/.mixxx/controllers}"

SKIN_NAME="${SKIN_NAME:-LateNightMini}"
SKIN_REPO_URL="${SKIN_REPO_URL:-https://github.com/ghztomash/LateNightMini.git}"
SKIN_REPO_BRANCH="${SKIN_REPO_BRANCH:-main}"
SKIN_REPO_DIR="${SKIN_REPO_DIR:-$HOME/.local/share/standalone-mixxx/LateNightMini}"
SKINS_DIR="${SKINS_DIR:-$HOME/.mixxx/skins}"
SKIN_TARGET="$SKINS_DIR/$SKIN_NAME"

declare -a CONTROLLER_SOURCES=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [--controllers] [--skin] [--remove] [--help]

Install or update the managed FLX-Mixxx controller mapping checkout and the
LateNightMini skin checkout under ~/.local/share/standalone-mixxx.

By default, installs or removes both components. Use --controllers or --skin
to limit the action to one component.

Options:
  --controllers  Operate only on controller mappings.
  --skin         Operate only on the LateNightMini skin.
  --remove       Remove managed symlinks and delete clean managed checkouts.
  --help         Show this help text.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

print_section() {
  local title="$1"

  printf '\n==> %s\n' "$title"
}

require_command() {
  local cmd="$1"

  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

ensure_prerequisites() {
  require_command git
  require_command readlink
}

managed_link_path() {
  local path="$1"
  local repo_dir="$2"
  local raw_target
  local resolved_target

  [ -L "$path" ] || return 1

  raw_target=$(readlink "$path")
  case "$raw_target" in
    "$repo_dir"|"$repo_dir"/*) return 0 ;;
  esac

  resolved_target=$(readlink -f "$path" 2>/dev/null || true)
  case "$resolved_target" in
    "$repo_dir"|"$repo_dir"/*) return 0 ;;
  esac

  return 1
}

canonical_github_repo() {
  local url="$1"
  local repo_path

  case "$url" in
    https://github.com/*)
      repo_path="${url#https://github.com/}"
      ;;
    git@github.com:*)
      repo_path="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      repo_path="${url#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  repo_path="${repo_path%/}"
  repo_path="${repo_path%.git}"

  case "$repo_path" in
    */*) ;;
    *) return 1 ;;
  esac

  printf 'github.com/%s\n' "${repo_path,,}"
}

repo_urls_match() {
  local expected_url="$1"
  local actual_url="$2"
  local expected_repo
  local actual_repo

  [ "$expected_url" = "$actual_url" ] && return 0

  expected_repo=$(canonical_github_repo "$expected_url" 2>/dev/null || true)
  actual_repo=$(canonical_github_repo "$actual_url" 2>/dev/null || true)

  [ -n "$expected_repo" ] && [ "$expected_repo" = "$actual_repo" ]
}

ensure_clean_checkout() {
  local repo_dir="$1"
  local repo_url="$2"
  local repo_branch="$3"
  local repo_label="$4"
  local origin_url
  local current_branch
  local repo_status

  [ -d "$repo_dir/.git" ] || die "Existing $repo_label path is not a git repository: $repo_dir"

  origin_url=$(git -C "$repo_dir" config --get remote.origin.url || true)
  repo_urls_match "$repo_url" "$origin_url" || die "Existing $repo_label repository origin mismatch at $repo_dir. Expected $repo_url or an equivalent GitHub HTTPS/SSH URL but found ${origin_url:-<none>}"

  current_branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)
  [ "$current_branch" = "$repo_branch" ] || die "Existing $repo_label repository must be on branch $repo_branch, found $current_branch at $repo_dir"

  repo_status=$(git -C "$repo_dir" status --porcelain)
  [ -z "$repo_status" ] || die "Existing $repo_label repository has local changes at $repo_dir. Commit, stash, or discard them before rerunning."
}

clone_or_update_repo() {
  local repo_dir="$1"
  local repo_url="$2"
  local repo_branch="$3"
  local repo_label="$4"

  mkdir -p "$(dirname "$repo_dir")"

  if [ ! -e "$repo_dir" ]; then
    printf 'Cloning %s repository into %s\n' "$repo_label" "$repo_dir"
    git clone --branch "$repo_branch" "$repo_url" "$repo_dir"
    return
  fi

  ensure_clean_checkout "$repo_dir" "$repo_url" "$repo_branch" "$repo_label"

  printf 'Updating %s repository in %s\n' "$repo_label" "$repo_dir"
  git -C "$repo_dir" fetch origin "$repo_branch"
  git -C "$repo_dir" merge --ff-only FETCH_HEAD
}

remove_checkout_if_clean() {
  local repo_dir="$1"
  local repo_label="$2"
  local repo_status

  [ -e "$repo_dir" ] || return 0
  [ -d "$repo_dir/.git" ] || die "Managed $repo_label checkout path exists but is not a git repository: $repo_dir"

  repo_status=$(git -C "$repo_dir" status --porcelain)
  if [ -n "$repo_status" ]; then
    printf 'Keeping %s checkout with local changes: %s\n' "$repo_label" "$repo_dir"
    return 0
  fi

  rm -rf "$repo_dir"
  printf 'Removed clean %s checkout %s\n' "$repo_label" "$repo_dir"
}

collect_controller_sources() {
  shopt -s nullglob
  CONTROLLER_SOURCES=("$CONTROLLER_REPO_DIR"/*.js "$CONTROLLER_REPO_DIR"/*.xml)
  shopt -u nullglob

  [ "${#CONTROLLER_SOURCES[@]}" -gt 0 ] || die "No top-level .js or .xml controller files found in $CONTROLLER_REPO_DIR"
}

verify_controller_targets() {
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

install_controller_symlinks() {
  local source
  local target
  local link_target
  local resolved_target

  mkdir -p "$CONTROLLERS_DIR"
  verify_controller_targets

  for source in "${CONTROLLER_SOURCES[@]}"; do
    target="$CONTROLLERS_DIR/$(basename "$source")"

    if [ -L "$target" ]; then
      link_target=$(readlink "$target")
      resolved_target=$(readlink -f "$target" 2>/dev/null || true)

      if [ "$link_target" = "$source" ] || [ "$resolved_target" = "$source" ]; then
        printf 'Keeping existing controller symlink %s\n' "$target"
        continue
      fi
    fi

    ln -s "$source" "$target"
    printf 'Linked %s -> %s\n' "$target" "$source"
  done
}

remove_controller_symlinks() {
  local path
  local removed=0

  [ -d "$CONTROLLERS_DIR" ] || return 0

  shopt -s nullglob
  for path in "$CONTROLLERS_DIR"/*; do
    if managed_link_path "$path" "$CONTROLLER_REPO_DIR"; then
      rm "$path"
      printf 'Removed controller symlink %s\n' "$path"
      removed=1
    fi
  done
  shopt -u nullglob

  if [ "$removed" -eq 0 ]; then
    printf 'No managed controller symlinks found in %s\n' "$CONTROLLERS_DIR"
  fi
}

verify_skin_checkout() {
  [ -f "$SKIN_REPO_DIR/skin.xml" ] || die "Expected skin.xml at the repository root: $SKIN_REPO_DIR"
}

verify_skin_target() {
  local link_target
  local resolved_target

  if [ -L "$SKIN_TARGET" ]; then
    link_target=$(readlink "$SKIN_TARGET")
    resolved_target=$(readlink -f "$SKIN_TARGET" 2>/dev/null || true)

    if [ "$link_target" = "$SKIN_REPO_DIR" ] || [ "$resolved_target" = "$SKIN_REPO_DIR" ]; then
      return 0
    fi

    die "Skin target already points elsewhere: $SKIN_TARGET -> $link_target"
  fi

  [ ! -e "$SKIN_TARGET" ] || die "Skin target already exists and is not a managed symlink: $SKIN_TARGET"
}

install_skin_symlink() {
  mkdir -p "$SKINS_DIR"
  verify_skin_target

  if [ -L "$SKIN_TARGET" ]; then
    printf 'Keeping existing skin symlink %s\n' "$SKIN_TARGET"
    return
  fi

  ln -s "$SKIN_REPO_DIR" "$SKIN_TARGET"
  printf 'Linked %s -> %s\n' "$SKIN_TARGET" "$SKIN_REPO_DIR"
}

remove_skin_symlink() {
  if managed_link_path "$SKIN_TARGET" "$SKIN_REPO_DIR"; then
    rm "$SKIN_TARGET"
    printf 'Removed skin symlink %s\n' "$SKIN_TARGET"
    return
  fi

  printf 'No managed skin symlink found at %s\n' "$SKIN_TARGET"
}

install_controllers() {
  print_section "Installing controller mappings"
  clone_or_update_repo "$CONTROLLER_REPO_DIR" "$CONTROLLER_REPO_URL" "$CONTROLLER_REPO_BRANCH" "controller"
  collect_controller_sources
  install_controller_symlinks
}

remove_controllers() {
  print_section "Removing controller mappings"
  remove_controller_symlinks
  remove_checkout_if_clean "$CONTROLLER_REPO_DIR" "controller"
}

install_skin() {
  print_section "Installing $SKIN_NAME skin"
  clone_or_update_repo "$SKIN_REPO_DIR" "$SKIN_REPO_URL" "$SKIN_REPO_BRANCH" "skin"
  verify_skin_checkout
  install_skin_symlink
}

remove_skin() {
  print_section "Removing $SKIN_NAME skin"
  remove_skin_symlink
  remove_checkout_if_clean "$SKIN_REPO_DIR" "skin"
}

main() {
  local remove_mode=0
  local help_mode=0
  local do_controllers=0
  local do_skin=0
  local target_specified=0
  local arg

  ensure_prerequisites

  for arg in "$@"; do
    case "$arg" in
      --controllers)
        do_controllers=1
        target_specified=1
        ;;
      --skin)
        do_skin=1
        target_specified=1
        ;;
      --remove)
        remove_mode=1
        ;;
      --help)
        help_mode=1
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
  done

  if [ "$help_mode" -eq 1 ]; then
    [ "$#" -eq 1 ] || die "--help cannot be combined with other arguments"
    usage
    return
  fi

  if [ "$target_specified" -eq 0 ]; then
    do_controllers=1
    do_skin=1
  fi

  if [ "$remove_mode" -eq 1 ]; then
    [ "$do_controllers" -eq 0 ] || remove_controllers
    [ "$do_skin" -eq 0 ] || remove_skin
    return
  fi

  [ "$do_controllers" -eq 0 ] || install_controllers
  [ "$do_skin" -eq 0 ] || install_skin
}

main "$@"
