#!/usr/bin/env bash
set -euo pipefail

CONTROLLER_REPO_URL="${CONTROLLER_REPO_URL:-${REPO_URL:-https://github.com/ghztomash/FLX-Mixxx.git}}"
CONTROLLER_REPO_BRANCH="${CONTROLLER_REPO_BRANCH:-${REPO_BRANCH:-main}}"
CONTROLLER_REPO_DIR="${CONTROLLER_REPO_DIR:-${REPO_DIR:-$HOME/.local/share/standalone-mixxx/FLX-Mixxx}}"
CONTROLLERS_DIR="${CONTROLLERS_DIR:-$HOME/.mixxx/controllers}"

MIXXX_SOURCE="${MIXXX_SOURCE:-vanilla}"
MIXXX_APT_PACKAGES="${MIXXX_APT_PACKAGES:-mixxx}"
MIXXX_QT_SVG_PACKAGE_CANDIDATES="${MIXXX_QT_SVG_PACKAGE_CANDIDATES:-qt6-svg-plugins libqt6svg6 libqt6svgwidgets6}"
MIXXX_CUSTOM_RELEASE_API_URL="${MIXXX_CUSTOM_RELEASE_API_URL:-https://api.github.com/repos/ghztomash/mixxx/releases/latest}"
MIXXX_CUSTOM_ASSET_GLOB="${MIXXX_CUSTOM_ASSET_GLOB:-}"
MIXXX_DOWNLOAD_DIR="${MIXXX_DOWNLOAD_DIR:-$HOME/.cache/standalone-mixxx}"
MIXXX_REALTIME_GROUP="${MIXXX_REALTIME_GROUP:-audio}"
MIXXX_REALTIME_LIMITS_FILE="${MIXXX_REALTIME_LIMITS_FILE:-/etc/security/limits.d/95-audio.conf}"
MIXXX_REALTIME_LIMITS_CONF="${MIXXX_REALTIME_LIMITS_CONF:-/etc/security/limits.conf}"

SKIN_NAME="${SKIN_NAME:-LateNightMini}"
SKIN_REPO_URL="${SKIN_REPO_URL:-https://github.com/ghztomash/LateNightMini.git}"
SKIN_REPO_BRANCH="${SKIN_REPO_BRANCH:-main}"
SKIN_REPO_DIR="${SKIN_REPO_DIR:-$HOME/.local/share/standalone-mixxx/LateNightMini}"
SKINS_DIR="${SKINS_DIR:-$HOME/.mixxx/skins}"
SKIN_TARGET="$SKINS_DIR/$SKIN_NAME"

declare -a CONTROLLER_SOURCES=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [--mixxx] [--realtime] [--controllers] [--skin] [--custom|--vanilla] [--remove] [--help]

Install or update Mixxx, the managed FLX-Mixxx controller mapping checkout,
and the LateNightMini skin checkout under ~/.local/share/standalone-mixxx.

By default, installs all components. Use --mixxx, --realtime, --controllers, or --skin
to limit the action to one component.

Options:
  --mixxx       Operate only on Mixxx.
  --realtime    Operate only on real-time audio permissions.
  --controllers  Operate only on controller mappings.
  --skin         Operate only on the LateNightMini skin.
  --custom       Install the custom GitHub release Mixxx .deb.
  --vanilla      Install vanilla Mixxx from apt. Default.
  --remove       Remove selected managed symlinks and delete clean managed checkouts.
                 Mixxx package and real-time config removal are intentionally unmanaged.
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

require_sudo_if_needed() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    require_command sudo
  fi
}

ensure_prerequisites() {
  local need_mixxx="$1"
  local need_realtime="$2"
  local need_controllers="$3"
  local need_skin="$4"

  if [ "$need_controllers" -eq 1 ] || [ "$need_skin" -eq 1 ]; then
    require_command git
    require_command readlink
  fi

  if [ "$need_mixxx" -eq 1 ] || [ "$need_realtime" -eq 1 ]; then
    require_sudo_if_needed
  fi

  if [ "$need_mixxx" -eq 1 ]; then
    require_command apt-get

    if [ "$MIXXX_SOURCE" = "custom" ]; then
      require_command curl
      require_command python3
      require_command sha256sum
      require_command uname
    fi
  fi

  if [ "$need_realtime" -eq 1 ]; then
    require_command getent
    require_command id
    require_command mkdir
    require_command tee
  fi
}

run_as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
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

validate_mixxx_source() {
  case "$MIXXX_SOURCE" in
    custom|vanilla) ;;
    *) die "Invalid Mixxx source: $MIXXX_SOURCE. Expected custom or vanilla." ;;
  esac
}

resolve_available_packages() {
  local package
  local resolved=()

  for package in "$@"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      resolved+=("$package")
    fi
  done

  printf '%s\n' "${resolved[@]}"
}

resolve_qt_svg_packages() {
  # shellcheck disable=SC2086
  resolve_available_packages $MIXXX_QT_SVG_PACKAGE_CANDIDATES
}

install_apt_packages() {
  local -a packages=("$@")

  [ "${#packages[@]}" -gt 0 ] || return 0

  printf 'Installing apt packages: %s\n' "${packages[*]}"
  run_as_root apt-get install -y "${packages[@]}"
}

target_realtime_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi

  id -un
}

user_in_group() {
  local user="$1"
  local group="$2"
  local user_group

  for user_group in $(id -nG "$user"); do
    [ "$user_group" != "$group" ] || return 0
  done

  return 1
}

ensure_realtime_group_membership() {
  local user="$1"
  local group="$MIXXX_REALTIME_GROUP"

  getent group "$group" >/dev/null || die "Required real-time audio group does not exist: $group"
  id "$user" >/dev/null 2>&1 || die "Target real-time audio user does not exist: $user"

  if user_in_group "$user" "$group"; then
    printf 'Keeping %s in %s group\n' "$user" "$group"
    return 0
  fi

  printf 'Adding %s to %s group\n' "$user" "$group"
  run_as_root usermod -aG "$group" "$user"
  return 0
}

realtime_limit_exists() {
  local item="$1"
  local value="$2"
  local group="$MIXXX_REALTIME_GROUP"
  local limits_dir="${MIXXX_REALTIME_LIMITS_FILE%/*}"
  local file
  local line
  local parsed_line
  local domain
  local limit_type
  local parsed_item
  local parsed_value
  local rest
  local -a limit_files=()

  [ "$limits_dir" != "$MIXXX_REALTIME_LIMITS_FILE" ] || limits_dir="."

  [ ! -f "$MIXXX_REALTIME_LIMITS_CONF" ] || limit_files+=("$MIXXX_REALTIME_LIMITS_CONF")

  shopt -s nullglob
  for file in "$limits_dir"/*.conf; do
    limit_files+=("$file")
  done
  shopt -u nullglob

  for file in "${limit_files[@]}"; do
    [ -r "$file" ] || continue

    while IFS= read -r line || [ -n "$line" ]; do
      parsed_line="${line%%#*}"
      if read -r domain limit_type parsed_item parsed_value rest <<< "$parsed_line"; then
        if [ "$domain" = "@$group" ] &&
          [ "$limit_type" = "-" ] &&
          [ "$parsed_item" = "$item" ] &&
          [ "$parsed_value" = "$value" ]; then
          return 0
        fi
      fi
    done < "$file"
  done

  return 1
}

append_realtime_limit() {
  local line="$1"
  local limits_dir="${MIXXX_REALTIME_LIMITS_FILE%/*}"

  [ "$limits_dir" != "$MIXXX_REALTIME_LIMITS_FILE" ] || limits_dir="."

  run_as_root mkdir -p "$limits_dir"
  printf '%s\n' "$line" | run_as_root tee -a "$MIXXX_REALTIME_LIMITS_FILE" >/dev/null
  printf 'Added real-time limit: %s\n' "$line"
}

ensure_realtime_limits() {
  local group="$MIXXX_REALTIME_GROUP"
  local changed=0

  if ! realtime_limit_exists rtprio 95; then
    append_realtime_limit "@$group - rtprio 95"
    changed=1
  fi

  if ! realtime_limit_exists memlock unlimited; then
    append_realtime_limit "@$group - memlock unlimited"
    changed=1
  fi

  if ! realtime_limit_exists nice -19; then
    append_realtime_limit "@$group - nice -19"
    changed=1
  fi

  if [ "$changed" -eq 0 ]; then
    printf 'Keeping existing real-time limits for @%s\n' "$group"
  fi
}

detect_mixxx_package_architecture() {
  local machine

  machine=$(uname -m)

  case "$machine" in
    aarch64|arm64)
      printf 'aarch64\n'
      ;;
    x86_64|amd64)
      printf 'x86_64\n'
      ;;
    *)
      die "Unsupported Mixxx custom package architecture: $machine. Supported: aarch64, x86_64."
      ;;
  esac
}

custom_mixxx_asset_glob() {
  local package_architecture

  if [ -n "$MIXXX_CUSTOM_ASSET_GLOB" ]; then
    printf '%s\n' "$MIXXX_CUSTOM_ASSET_GLOB"
    return
  fi

  package_architecture=$(detect_mixxx_package_architecture)
  printf '*-%s.deb\n' "$package_architecture"
}

select_custom_mixxx_asset() {
  local release_json="$1"
  local asset_glob="$2"

  python3 - "$release_json" "$asset_glob" <<'PY'
import fnmatch
import json
import sys

release_path, pattern = sys.argv[1], sys.argv[2]

with open(release_path, "r", encoding="utf-8") as release_file:
    release = json.load(release_file)

assets = release.get("assets", [])
matches = [
    asset
    for asset in assets
    if fnmatch.fnmatch(asset.get("name", ""), pattern)
]

if len(matches) != 1:
    names = ", ".join(asset.get("name", "<unnamed>") for asset in assets) or "<none>"
    print(
        f"Expected exactly one release asset matching {pattern!r}, found {len(matches)}. "
        f"Available assets: {names}",
        file=sys.stderr,
    )
    sys.exit(1)

asset = matches[0]
download_url = asset.get("browser_download_url")
if not download_url:
    print(f"Matched asset {asset.get('name', '<unnamed>')} has no browser_download_url", file=sys.stderr)
    sys.exit(1)

print(download_url)
print(asset.get("name", "mixxx-custom.deb"))
print(asset.get("digest", ""))
PY
}

download_custom_mixxx_deb() {
  local release_json
  local asset_info
  local asset_url
  local asset_name
  local asset_digest
  local deb_path
  local checksum
  local asset_glob
  local -a asset_lines

  mkdir -p "$MIXXX_DOWNLOAD_DIR"
  release_json=$(mktemp "$MIXXX_DOWNLOAD_DIR/mixxx-release.XXXXXX.json")

  printf 'Fetching latest Mixxx release metadata from %s\n' "$MIXXX_CUSTOM_RELEASE_API_URL" >&2
  curl -fsSL "$MIXXX_CUSTOM_RELEASE_API_URL" -o "$release_json"

  asset_glob=$(custom_mixxx_asset_glob)
  printf 'Selecting custom Mixxx release asset matching %s\n' "$asset_glob" >&2
  asset_info=$(select_custom_mixxx_asset "$release_json" "$asset_glob") || die "Could not select a unique custom Mixxx .deb asset matching $asset_glob"
  mapfile -t asset_lines <<< "$asset_info"
  asset_url="${asset_lines[0]}"
  asset_name="${asset_lines[1]}"
  asset_name="${asset_name##*/}"
  asset_digest="${asset_lines[2]:-}"
  deb_path="$MIXXX_DOWNLOAD_DIR/$asset_name"
  rm -f "$release_json"

  printf 'Downloading custom Mixxx package %s\n' "$asset_name" >&2
  curl -fsSL "$asset_url" -o "$deb_path"

  case "$asset_digest" in
    sha256:*)
      checksum="${asset_digest#sha256:}"
      printf 'Verifying SHA256 digest for %s\n' "$asset_name" >&2
      printf '%s  %s\n' "$checksum" "$deb_path" | sha256sum -c - >&2
      ;;
    "")
      printf 'No SHA256 digest found in release metadata for %s\n' "$asset_name" >&2
      ;;
    *)
      printf 'Skipping unsupported release asset digest format for %s: %s\n' "$asset_name" "$asset_digest" >&2
      ;;
  esac

  printf '%s\n' "$deb_path"
}

install_mixxx_vanilla() {
  local -a qt_svg_packages

  run_as_root apt-get update
  mapfile -t qt_svg_packages < <(resolve_qt_svg_packages)
  # shellcheck disable=SC2086
  install_apt_packages $MIXXX_APT_PACKAGES "${qt_svg_packages[@]}"
}

install_mixxx_custom() {
  local deb_path
  local -a qt_svg_packages

  deb_path=$(download_custom_mixxx_deb)
  printf 'Installing custom Mixxx package %s\n' "$deb_path"
  run_as_root apt-get update
  mapfile -t qt_svg_packages < <(resolve_qt_svg_packages)
  install_apt_packages "$deb_path" "${qt_svg_packages[@]}"
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

install_mixxx() {
  print_section "Installing Mixxx ($MIXXX_SOURCE)"

  case "$MIXXX_SOURCE" in
    custom)
      install_mixxx_custom
      ;;
    vanilla)
      install_mixxx_vanilla
      ;;
  esac
}

install_realtime() {
  local target_user

  print_section "Configuring real-time audio permissions"

  target_user=$(target_realtime_user)
  ensure_realtime_group_membership "$target_user"
  ensure_realtime_limits
  printf 'Log out and back in, or reboot, before checking groups, ulimit -r, or ulimit -l.\n'
}

remove_mixxx() {
  print_section "Removing Mixxx"
  printf 'Mixxx package removal is intentionally unmanaged. Remove it with apt if needed.\n'
}

remove_realtime() {
  print_section "Removing real-time audio permissions"
  printf 'Real-time audio permission removal is intentionally unmanaged. Edit group membership and limits files manually if needed.\n'
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
  local do_mixxx=0
  local do_realtime=0
  local do_controllers=0
  local do_skin=0
  local target_specified=0
  local original_arg_count="$#"
  local arg

  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --mixxx)
        do_mixxx=1
        target_specified=1
        ;;
      --realtime)
        do_realtime=1
        target_specified=1
        ;;
      --controllers)
        do_controllers=1
        target_specified=1
        ;;
      --skin)
        do_skin=1
        target_specified=1
        ;;
      --custom)
        MIXXX_SOURCE="custom"
        ;;
      --vanilla)
        MIXXX_SOURCE="vanilla"
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
    shift
  done

  if [ "$help_mode" -eq 1 ]; then
    [ "$original_arg_count" -eq 1 ] || die "--help cannot be combined with other arguments"
    usage
    return
  fi

  validate_mixxx_source

  if [ "$target_specified" -eq 0 ]; then
    if [ "$remove_mode" -eq 1 ]; then
      do_controllers=1
      do_skin=1
    else
      do_mixxx=1
      do_realtime=1
      do_controllers=1
      do_skin=1
    fi
  fi

  if [ "$remove_mode" -eq 1 ]; then
    ensure_prerequisites 0 0 "$do_controllers" "$do_skin"
  else
    ensure_prerequisites "$do_mixxx" "$do_realtime" "$do_controllers" "$do_skin"
  fi

  if [ "$remove_mode" -eq 1 ]; then
    [ "$do_mixxx" -eq 0 ] || remove_mixxx
    [ "$do_realtime" -eq 0 ] || remove_realtime
    [ "$do_controllers" -eq 0 ] || remove_controllers
    [ "$do_skin" -eq 0 ] || remove_skin
    return
  fi

  [ "$do_mixxx" -eq 0 ] || install_mixxx
  [ "$do_realtime" -eq 0 ] || install_realtime
  [ "$do_controllers" -eq 0 ] || install_controllers
  [ "$do_skin" -eq 0 ] || install_skin
}

main "$@"
