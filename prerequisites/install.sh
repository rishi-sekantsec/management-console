#!/usr/bin/env bash

set -euo pipefail

GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
RESET=$'\033[0m'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
DEFAULT_COMPOSE_VERSION="${DEFAULT_COMPOSE_VERSION:-v2.39.1}"
SUDO_BIN=""
DOCKER_GROUP_WAS_ADDED=0

log_info() {
  printf "%s[INFO]%s %s\n" "${CYAN}" "${RESET}" "$*"
}

log_warn() {
  printf "%s[WARN]%s %s\n" "${YELLOW}" "${RESET}" "$*"
}

log_error() {
  printf "%s[ERROR]%s %s\n" "${RED}" "${RESET}" "$*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_linux_root_path() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO_BIN=""
    return 0
  fi
  if command_exists sudo; then
    SUDO_BIN="sudo"
    return 0
  fi
  log_error "This script must run as root or with sudo on Linux."
  exit 1
}

as_root() {
  if [[ -n "${SUDO_BIN}" ]]; then
    "${SUDO_BIN}" "$@"
  else
    "$@"
  fi
}

set_release_defaults() {
  DISTRO_ID="unknown"
  DISTRO_LIKE=""
  DISTRO_NAME="Unknown Linux"
  DISTRO_VERSION_ID=""
  DISTRO_VERSION_CODENAME=""
}

detect_architecture() {
  local raw_arch raw_bits
  raw_arch="$(uname -m 2>/dev/null || printf "unknown")"
  raw_bits="$(getconf LONG_BIT 2>/dev/null || printf "unknown")"

  CPU_ARCH_RAW="${raw_arch}"
  CPU_BITS="${raw_bits}"
  CPU_ARCH="unknown"
  COMPOSE_ARCH=""

  case "${raw_arch}" in
    x86_64|amd64)
      CPU_ARCH="amd64"
      COMPOSE_ARCH="x86_64"
      ;;
    i386|i486|i586|i686)
      CPU_ARCH="386"
      COMPOSE_ARCH="i386"
      ;;
    aarch64|arm64)
      CPU_ARCH="arm64"
      COMPOSE_ARCH="aarch64"
      ;;
    armv7l|armv7|armhf)
      CPU_ARCH="armv7"
      COMPOSE_ARCH="armv7"
      ;;
    armv6l|armv6)
      CPU_ARCH="armv6"
      COMPOSE_ARCH="armv6"
      ;;
    ppc64le)
      CPU_ARCH="ppc64le"
      COMPOSE_ARCH="ppc64le"
      ;;
    s390x)
      CPU_ARCH="s390x"
      COMPOSE_ARCH="s390x"
      ;;
    riscv64)
      CPU_ARCH="riscv64"
      COMPOSE_ARCH="riscv64"
      ;;
  esac
}

detect_platform() {
  PLATFORM_FAMILY=""
  HOST_OS_RAW="$(uname -s 2>/dev/null || printf "unknown")"
  detect_architecture

  case "${HOST_OS_RAW}" in
    Linux)
      PLATFORM_FAMILY="linux"
      set_release_defaults
      if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
        DISTRO_VERSION_ID="${VERSION_ID:-}"
        DISTRO_VERSION_CODENAME="${VERSION_CODENAME:-}"
      fi
      ;;
    Darwin)
      PLATFORM_FAMILY="macos"
      MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || printf "unknown")"
      ;;
    *)
      log_error "Unsupported operating system '${HOST_OS_RAW}'. Use the Windows PowerShell installer on Windows."
      exit 1
      ;;
  esac
}

detect_package_manager() {
  PACKAGE_MANAGER=""
  if command_exists apt-get; then
    PACKAGE_MANAGER="apt"
  elif command_exists pacman; then
    PACKAGE_MANAGER="pacman"
  elif command_exists dnf; then
    PACKAGE_MANAGER="dnf"
  elif command_exists yum; then
    PACKAGE_MANAGER="yum"
  elif command_exists zypper; then
    PACKAGE_MANAGER="zypper"
  elif command_exists apk; then
    PACKAGE_MANAGER="apk"
  fi

  if [[ -z "${PACKAGE_MANAGER}" ]]; then
    log_error "No supported Linux package manager was detected."
    exit 1
  fi
}

print_summary() {
  log_info "Detected OS family : ${PLATFORM_FAMILY}"
  if [[ "${PLATFORM_FAMILY}" == "linux" ]]; then
    log_info "Detected distro    : ${DISTRO_NAME} (${DISTRO_ID})"
  else
    log_info "Detected macOS     : ${MACOS_VERSION}"
  fi
  log_info "Detected arch      : ${CPU_ARCH_RAW} (${CPU_ARCH}, ${CPU_BITS}-bit)"
}

assert_supported_docker_shape() {
  if [[ "${PLATFORM_FAMILY}" == "macos" && "${CPU_BITS}" != "64" ]]; then
    log_error "Docker Desktop requires a 64-bit macOS system."
    exit 1
  fi

  if [[ "${PLATFORM_FAMILY}" == "linux" && "${CPU_ARCH}" == "386" ]]; then
    log_warn "32-bit Linux was detected. Docker Engine is not officially supported on many 32-bit distributions."
    log_warn "The script will install the non-Docker prerequisites and then attempt Docker installation best-effort."
  fi
}

apt_install() {
  as_root apt-get update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

pacman_install() {
  as_root pacman -Sy --noconfirm --needed "$@"
}

dnf_install() {
  as_root dnf -y install "$@"
}

yum_install() {
  as_root yum -y install "$@"
}

zypper_install() {
  as_root zypper --non-interactive install --no-recommends "$@"
}

apk_install() {
  as_root apk add --no-cache "$@"
}

install_linux_basics() {
  log_info "Installing baseline tools for Linux..."
  case "${PACKAGE_MANAGER}" in
    apt)
      apt_install bash ca-certificates curl wget git openssl gnupg lsb-release coreutils grep sed gawk findutils tar gzip procps util-linux acl
      ;;
    pacman)
      pacman_install bash ca-certificates curl wget git openssl coreutils grep sed gawk findutils tar gzip procps-ng util-linux acl
      ;;
    dnf)
      dnf_install bash ca-certificates curl wget git openssl coreutils grep sed gawk findutils tar gzip procps-ng util-linux shadow-utils acl
      ;;
    yum)
      yum_install bash ca-certificates curl wget git openssl coreutils grep sed gawk findutils tar gzip procps-ng util-linux shadow-utils acl
      ;;
    zypper)
      zypper_install bash ca-certificates curl wget git openssl coreutils grep sed gawk findutils tar gzip procps util-linux shadow acl
      ;;
    apk)
      apk_install bash ca-certificates curl wget git openssl coreutils grep sed gawk findutils tar gzip procps util-linux shadow acl
      ;;
  esac
}

configure_apt_docker_repo() {
  if [[ "${DISTRO_ID}" != "ubuntu" && "${DISTRO_ID}" != "debian" ]]; then
    return 1
  fi

  if [[ "${CPU_ARCH}" == "386" ]]; then
    return 1
  fi

  local repo_arch repo_url repo_codename
  repo_arch="${CPU_ARCH}"
  repo_codename="${DISTRO_VERSION_CODENAME}"
  if [[ -z "${repo_codename}" ]]; then
    if command_exists lsb_release; then
      repo_codename="$(lsb_release -cs 2>/dev/null || true)"
    fi
  fi
  if [[ -z "${repo_codename}" ]]; then
    return 1
  fi

  repo_url="https://download.docker.com/linux/${DISTRO_ID}"
  as_root install -m 0755 -d /etc/apt/keyrings
  if command_exists curl; then
    curl -fsSL "${repo_url}/gpg" | as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  else
    wget -qO- "${repo_url}/gpg" | as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi
  as_root chmod a+r /etc/apt/keyrings/docker.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] %s %s stable\n' \
    "${repo_arch}" "${repo_url}" "${repo_codename}" | as_root tee /etc/apt/sources.list.d/docker.list >/dev/null
  as_root apt-get update
  return 0
}

configure_dnf_docker_repo() {
  local repo_family=""
  case "${DISTRO_ID}" in
    fedora)
      repo_family="fedora"
      ;;
    rhel|centos|rocky|almalinux|ol)
      repo_family="centos"
      ;;
    amzn)
      return 1
      ;;
    *)
      if [[ "${DISTRO_LIKE}" == *"rhel"* || "${DISTRO_LIKE}" == *"fedora"* ]]; then
        repo_family="centos"
      fi
      ;;
  esac

  if [[ -z "${repo_family}" ]]; then
    return 1
  fi

  if [[ "${PACKAGE_MANAGER}" == "dnf" ]]; then
    dnf_install dnf-plugins-core
    as_root dnf config-manager --add-repo "https://download.docker.com/linux/${repo_family}/docker-ce.repo"
  else
    yum_install yum-utils
    as_root yum-config-manager --add-repo "https://download.docker.com/linux/${repo_family}/docker-ce.repo"
  fi
  return 0
}

install_docker_linux() {
  log_info "Installing Docker Engine and Docker Compose support..."

  case "${PACKAGE_MANAGER}" in
    apt)
      if configure_apt_docker_repo; then
        if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
          log_warn "Official Docker packages failed. Falling back to distro Docker packages."
          as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io || true
          as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2 || true
          as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin || true
        fi
      else
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io || true
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2 || true
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin || true
      fi
      ;;
    pacman)
      pacman_install docker docker-compose
      ;;
    dnf|yum)
      if configure_dnf_docker_repo; then
        if [[ "${PACKAGE_MANAGER}" == "dnf" ]]; then
          dnf_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
        else
          yum_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
        fi
      fi
      if ! command_exists docker; then
        if [[ "${PACKAGE_MANAGER}" == "dnf" ]]; then
          dnf_install moby-engine docker-cli docker-compose-plugin containerd.io || true
        else
          yum_install moby-engine docker-cli docker-compose-plugin containerd.io || true
        fi
      fi
      ;;
    zypper)
      zypper_install docker
      ;;
    apk)
      apk_install docker docker-cli-compose
      ;;
  esac

  if ! command_exists docker; then
    log_error "Docker could not be installed automatically on this Linux host."
    exit 1
  fi
}

ensure_docker_service_linux() {
  log_info "Enabling Docker to start automatically..."

  if command_exists systemctl; then
    as_root systemctl enable docker >/dev/null 2>&1 || true
    as_root systemctl enable containerd >/dev/null 2>&1 || true
    as_root systemctl start containerd >/dev/null 2>&1 || true
    as_root systemctl start docker
    return 0
  fi

  if command_exists rc-update; then
    as_root rc-update add docker default >/dev/null 2>&1 || true
    if command_exists rc-service; then
      as_root rc-service docker start
    else
      as_root service docker start
    fi
    return 0
  fi

  if command_exists service; then
    as_root service docker start || true
    log_warn "Could not configure automatic Docker startup permanently because no supported service manager was detected."
    return 0
  fi

  log_warn "Could not configure Docker startup because no supported service manager was detected."
}

ensure_docker_group_linux() {
  local target_user
  target_user="${SUDO_USER:-$(id -un)}"

  if [[ "${target_user}" == "root" ]]; then
    return 0
  fi

  if ! getent group docker >/dev/null 2>&1; then
    as_root groupadd docker
  fi

  if id -nG "${target_user}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    return 0
  fi

  log_info "Granting Docker access to user '${target_user}'..."
  as_root usermod -aG docker "${target_user}"
  DOCKER_GROUP_WAS_ADDED=1
  log_warn "User '${target_user}' was added to the docker group."
  log_warn "A new login session is required before plain 'docker' works without sudo for that user."
}

grant_immediate_docker_socket_access_linux() {
  local target_user socket_path
  target_user="${SUDO_USER:-$(id -un)}"
  socket_path="/var/run/docker.sock"

  if [[ "${target_user}" == "root" ]]; then
    return 0
  fi

  if [[ ! -S "${socket_path}" ]]; then
    return 0
  fi

  if ! command_exists setfacl; then
    log_warn "setfacl is not available, so immediate Docker socket access cannot be granted to the current shell."
    return 0
  fi

  log_info "Granting immediate Docker socket access to user '${target_user}' for the current session..."
  as_root setfacl -m "u:${target_user}:rw" "${socket_path}" >/dev/null 2>&1 || {
    log_warn "Could not set an ACL on ${socket_path}; a re-login may still be required before docker works without sudo."
    return 0
  }
}

validate_target_user_docker_access_linux() {
  local target_user
  target_user="${SUDO_USER:-$(id -un)}"

  if [[ "${target_user}" == "root" ]]; then
    return 0
  fi

  if (( DOCKER_GROUP_WAS_ADDED == 0 )); then
    return 0
  fi

  if command_exists su; then
    log_info "Validating Docker access for '${target_user}' in a fresh login shell..."
    if as_root su - "${target_user}" -c "docker info >/dev/null 2>&1"; then
      log_info "Docker access is already valid for new login shells for '${target_user}'."
      return 0
    fi
  fi

  log_warn "Docker group membership was added, but the current parent shell still cannot have its supplementary groups rewritten by a child script."
  log_warn "Use 'newgrp docker' or log out and back in once if you want the parent shell itself to pick up the new group immediately."
}

wait_for_docker_linux() {
  local attempt=0
  until as_root docker info >/dev/null 2>&1; do
    attempt=$(( attempt + 1 ))
    if (( attempt > 30 )); then
      log_error "Docker daemon did not become ready."
      exit 1
    fi
    sleep 2
  done
}

compose_plugin_path_linux() {
  if [[ -d /usr/local/lib/docker/cli-plugins ]]; then
    printf "/usr/local/lib/docker/cli-plugins/docker-compose"
  else
    printf "/usr/local/lib/docker/cli-plugins/docker-compose"
  fi
}

ensure_compose_symlink_linux() {
  local plugin_path
  plugin_path="$(compose_plugin_path_linux)"
  if [[ -x "${plugin_path}" ]]; then
    as_root ln -sf "${plugin_path}" /usr/local/bin/docker-compose
  fi
}

install_compose_plugin_manual_linux() {
  local plugin_path plugin_dir url tmp_file

  if [[ -z "${COMPOSE_ARCH}" ]]; then
    log_error "No Docker Compose plugin binary is published for architecture '${CPU_ARCH_RAW}'."
    exit 1
  fi

  plugin_path="$(compose_plugin_path_linux)"
  plugin_dir="$(dirname "${plugin_path}")"
  url="https://github.com/docker/compose/releases/download/${DEFAULT_COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"
  tmp_file="$(mktemp)"

  log_info "Installing Docker Compose plugin manually from ${DEFAULT_COMPOSE_VERSION}..."
  if command_exists curl; then
    curl -fsSL -o "${tmp_file}" "${url}"
  else
    wget -qO "${tmp_file}" "${url}"
  fi

  as_root install -m 0755 -d "${plugin_dir}"
  as_root install -m 0755 "${tmp_file}" "${plugin_path}"
  rm -f "${tmp_file}"
  ensure_compose_symlink_linux
}

ensure_docker_compose_linux() {
  if as_root docker compose version >/dev/null 2>&1; then
    ensure_compose_symlink_linux
    return 0
  fi

  install_compose_plugin_manual_linux

  if ! as_root docker compose version >/dev/null 2>&1; then
    log_error "Docker Compose could not be enabled on this Linux host."
    exit 1
  fi
}

ensure_homebrew() {
  if command_exists brew; then
    return 0
  fi

  log_info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_macos_basics() {
  ensure_homebrew
  log_info "Installing baseline tools for macOS..."
  brew update
  brew install bash curl wget git openssl
}

configure_docker_autostart_macos() {
  local launch_agent_dir launch_agent_file docker_app_path
  docker_app_path="/Applications/Docker.app"
  launch_agent_dir="${HOME}/Library/LaunchAgents"
  launch_agent_file="${launch_agent_dir}/com.sekant.docker-desktop-autostart.plist"

  mkdir -p "${launch_agent_dir}"
  cat > "${launch_agent_file}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.sekant.docker-desktop-autostart</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>${docker_app_path}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF

  launchctl unload "${launch_agent_file}" >/dev/null 2>&1 || true
  launchctl load "${launch_agent_file}" >/dev/null 2>&1 || true
}

wait_for_docker_macos() {
  local attempt=0
  until docker info >/dev/null 2>&1; do
    attempt=$(( attempt + 1 ))
    if (( attempt > 120 )); then
      log_error "Docker Desktop did not become ready."
      exit 1
    fi
    sleep 5
  done
}

install_docker_macos() {
  log_info "Installing Docker Desktop for macOS..."
  brew install --cask docker
  configure_docker_autostart_macos
  open -a Docker
  wait_for_docker_macos

  if ! docker compose version >/dev/null 2>&1; then
    log_error "Docker Compose is not available after Docker Desktop startup."
    exit 1
  fi
}

verify_tool() {
  if ! command_exists "$1"; then
    log_error "Expected tool '$1' is not available after installation."
    exit 1
  fi
}

verify_linux_install() {
  verify_tool bash
  verify_tool curl
  verify_tool wget
  verify_tool git
  verify_tool openssl
  verify_tool docker
  wait_for_docker_linux
  ensure_docker_compose_linux
  as_root docker compose version >/dev/null
}

verify_macos_install() {
  verify_tool bash
  verify_tool curl
  verify_tool wget
  verify_tool git
  verify_tool openssl
  verify_tool docker
  docker compose version >/dev/null
}

main() {
  detect_platform
  print_summary
  assert_supported_docker_shape

  case "${PLATFORM_FAMILY}" in
    linux)
      require_linux_root_path
      detect_package_manager
      log_info "Using package manager: ${PACKAGE_MANAGER}"
      install_linux_basics
      install_docker_linux
      ensure_docker_service_linux
      ensure_docker_group_linux
      grant_immediate_docker_socket_access_linux
      validate_target_user_docker_access_linux
      verify_linux_install
      ;;
    macos)
      install_macos_basics
      install_docker_macos
      verify_macos_install
      ;;
  esac

  printf "%s[SUCCESS]%s Prerequisites are installed.\n" "${GREEN}" "${RESET}"
  if [[ "${PLATFORM_FAMILY}" == "linux" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf "%s[NOTE]%s Immediate access was granted to the current Docker socket for '%s'. After any Docker restart, the normal long-term access still depends on the docker group, so log out and back in once before relying on plain 'docker compose' in future sessions.\n" \
      "${YELLOW}" "${RESET}" "${SUDO_USER}"
  fi
}

main "$@"
