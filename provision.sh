#!/usr/bin/env bash
set -euo pipefail

PROVISION_PACKAGE_CANDIDATES="${PROVISION_PACKAGE_CANDIDATES:-rpi-connect cloud-init chromium chromium-browser cups cups-browsed system-config-printer geany thonny agnostics rpi-imager piclone rp-bookshelf rp-prefapps rpi-userguide rpinters libreoffice-base libreoffice-base-core libreoffice-calc libreoffice-common libreoffice-core libreoffice-draw libreoffice-gtk3 libreoffice-help-common libreoffice-help-en-us libreoffice-impress libreoffice-math libreoffice-style-colibre libreoffice-writer evince realvnc-vnc-server}"
PROVISION_SERVICE_CANDIDATES="${PROVISION_SERVICE_CANDIDATES:-NetworkManager-wait-online.service ModemManager.service cups.service cups-browsed.service rpi-connect.service cloud-config.service cloud-final.service cloud-init.service cloud-init-local.service avahi-daemon.service rpcbind.service nfs-blkmap.service rpi-eeprom-update.service e2scrub_reap.service rpi-resize-swap-file.service sshswitch.service glamor-test.service plymouth-start.service plymouth-quit-wait.service systemd-binfmt.service}"
PROVISION_TIMER_CANDIDATES="${PROVISION_TIMER_CANDIDATES:-apt-daily.timer apt-daily-upgrade.timer}"
PROVISION_BOOT_BLAME_LINES="${PROVISION_BOOT_BLAME_LINES:-20}"
PROVISION_ALLOW_UNSUPPORTED_OS="${PROVISION_ALLOW_UNSUPPORTED_OS:-0}"

DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--updates] [--packages] [--services] [--report] [--dry-run] [--help]

Prepare a Raspberry Pi OS Desktop system for a standalone Mixxx setup.

By default, runs all provisioning steps: updates, package cleanup, service cleanup,
apt cleanup, and a report-only tuning check.

Options:
  --updates   Run apt update/full-upgrade and apt cleanup.
  --packages  Purge installed packages from the cleanup candidate list.
  --services  Disable and mask installed optional services and timers.
  --report    Print report-only system and tuning diagnostics.
  --dry-run   Print privileged changes instead of applying them.
  --help      Show this help text.
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
  if [ "$DRY_RUN" -eq 1 ]; then
    return
  fi

  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    require_command sudo
  fi
}

print_command() {
  local arg

  printf '+'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

run_as_root() {
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      print_command "$@"
    else
      print_command sudo "$@"
    fi
    return
  fi

  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

ensure_prerequisites() {
  local need_updates="$1"
  local need_packages="$2"
  local need_services="$3"
  local need_report="$4"

  if [ "$need_updates" -eq 1 ] || [ "$need_packages" -eq 1 ]; then
    require_command apt-get
    require_command dpkg-query
    require_sudo_if_needed
  fi

  if [ "$need_services" -eq 1 ]; then
    require_command systemctl
    require_sudo_if_needed
  fi

  if [ "$need_report" -eq 1 ]; then
    require_command uname
    require_command df
    require_command free
  fi
}

is_supported_os() {
  if [ -f /etc/rpi-issue ]; then
    return 0
  fi

  if [ -r /etc/os-release ] && grep -Eiq 'raspberry pi os|raspbian' /etc/os-release; then
    return 0
  fi

  return 1
}

ensure_supported_os() {
  if [ "$DRY_RUN" -eq 1 ] || [ "$PROVISION_ALLOW_UNSUPPORTED_OS" = "1" ]; then
    return
  fi

  is_supported_os || die "This provisioning script is intended for Raspberry Pi OS. Set PROVISION_ALLOW_UNSUPPORTED_OS=1 to override."
}

package_installed() {
  local package="$1"

  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed'
}

collect_installed_packages() {
  local package
  local installed_packages=()

  # shellcheck disable=SC2086
  for package in $PROVISION_PACKAGE_CANDIDATES; do
    if package_installed "$package"; then
      installed_packages+=("$package")
    fi
  done

  printf '%s\n' "${installed_packages[@]}"
}

unit_exists() {
  local unit="$1"

  systemctl list-unit-files "$unit" --no-legend --no-pager 2>/dev/null | grep -q .
}

disable_and_mask_unit() {
  local unit="$1"

  if ! unit_exists "$unit"; then
    printf 'Skipping missing unit %s\n' "$unit"
    return
  fi

  printf 'Disabling and masking %s\n' "$unit"
  run_as_root systemctl disable --now "$unit"
  run_as_root systemctl mask "$unit"
}

run_updates() {
  print_section "Updating Raspberry Pi OS packages"

  run_as_root apt-get update
  run_as_root apt-get full-upgrade -y
}

run_package_cleanup() {
  local packages=()

  print_section "Removing unnecessary desktop packages"

  mapfile -t packages < <(collect_installed_packages)
  if [ "${#packages[@]}" -eq 0 ]; then
    printf 'No cleanup package candidates are installed.\n'
    return
  fi

  printf 'Purging installed cleanup packages: %s\n' "${packages[*]}"
  run_as_root apt-get purge -y "${packages[@]}"
}

run_service_cleanup() {
  local unit

  print_section "Disabling slow or unused services"

  # shellcheck disable=SC2086
  for unit in $PROVISION_SERVICE_CANDIDATES $PROVISION_TIMER_CANDIDATES; do
    disable_and_mask_unit "$unit"
  done
}

run_apt_cleanup() {
  print_section "Cleaning apt state"

  run_as_root apt-get autoremove -y
  run_as_root apt-get autoclean -y
}

print_file_if_readable() {
  local path="$1"

  if [ -r "$path" ]; then
    sed -n '1,80p' "$path"
  else
    printf 'Cannot read %s\n' "$path"
  fi
}

print_command_output() {
  local label="$1"
  shift

  printf '\n%s\n' "$label"
  if command -v "$1" >/dev/null 2>&1; then
    "$@" || true
  else
    printf 'Command not available: %s\n' "$1"
  fi
}

print_reboot_status() {
  if [ -f /var/run/reboot-required ]; then
    printf 'Reboot required: yes\n'
    print_file_if_readable /var/run/reboot-required.pkgs
  else
    printf 'Reboot required: no marker found at /var/run/reboot-required\n'
  fi
}

print_report() {
  print_section "Reporting system status and tuning hints"

  printf 'OS release:\n'
  print_file_if_readable /etc/os-release

  printf '\nArchitecture: %s\n' "$(uname -m)"
  print_command_output "Disk usage:" df -h /
  print_command_output "Memory:" free -h
  print_command_output "Boot time:" systemd-analyze time
  printf '\nSlow boot units:\n'
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze blame --no-pager | head -n "$PROVISION_BOOT_BLAME_LINES" || true
  else
    printf 'Command not available: systemd-analyze\n'
  fi
  print_command_output "Critical boot chain:" systemd-analyze critical-chain --no-pager
  print_command_output "Throttle status:" vcgencmd get_throttled
  print_command_output "ALSA playback devices:" aplay -l

  printf '\nUSB autosuspend:\n'
  if [ -r /sys/module/usbcore/parameters/autosuspend ]; then
    cat /sys/module/usbcore/parameters/autosuspend
  else
    printf 'Cannot read /sys/module/usbcore/parameters/autosuspend\n'
  fi

  printf '\n'
  print_reboot_status

  printf '\nDisplay overlays, boot cmdline, USB tuning, and real-time audio limits were not changed.\n'
  printf 'Run ./install.sh --realtime to configure Mixxx real-time audio permissions.\n'
  printf 'Review display-specific changes manually in /boot/firmware/config.txt.\n'
}

main() {
  local help_mode=0
  local do_updates=0
  local do_packages=0
  local do_services=0
  local do_report=0
  local target_specified=0
  local original_arg_count="$#"
  local arg

  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
    --updates)
      do_updates=1
      target_specified=1
      ;;
    --packages)
      do_packages=1
      target_specified=1
      ;;
    --services)
      do_services=1
      target_specified=1
      ;;
    --report)
      do_report=1
      target_specified=1
      ;;
    --dry-run)
      DRY_RUN=1
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

  if [ "$target_specified" -eq 0 ]; then
    do_updates=1
    do_packages=1
    do_services=1
    do_report=1
  fi

  ensure_supported_os
  ensure_prerequisites "$do_updates" "$do_packages" "$do_services" "$do_report"

  if [ "$DRY_RUN" -eq 1 ]; then
    print_section "Dry run"
    printf 'Privileged changes will be printed instead of applied.\n'
  fi

  [ "$do_updates" -eq 0 ] || run_updates
  [ "$do_packages" -eq 0 ] || run_package_cleanup
  [ "$do_services" -eq 0 ] || run_service_cleanup
  [ "$do_updates" -eq 0 ] || run_apt_cleanup
  [ "$do_report" -eq 0 ] || print_report
}

main "$@"
