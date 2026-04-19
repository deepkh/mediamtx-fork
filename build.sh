#!/usr/bin/env bash

set -euo pipefail

MTXRPICAM_PATH="../mediamtx-rpicamera-fork/build/mtxrpicam"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ ! -f go.mod ]]; then
  echo "error: go.mod not found; run this script from the MediaMTX repository root" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "error: this script supports Linux only" >&2
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
if [[ "${ARCH}" != "arm64" ]]; then
  echo "error: this script is intended for Debian arm64 systems; detected '${ARCH}'" >&2
  exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=()
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  else
    echo "error: sudo is required to install packages and Go" >&2
    exit 1
  fi
fi

APT_PACKAGES=(
  ca-certificates
  curl
  git
  tar
)

build_mediamtx() {
  local rpicam_src="${SCRIPT_DIR}/${MTXRPICAM_PATH}"
  local rpicam_dst_dir="${SCRIPT_DIR}/internal/staticsources/rpicamera/mtxrpicam_64"
  local rpicam_dst="${rpicam_dst_dir}/mtxrpicam"

  if [[ -f "${rpicam_src}" ]]; then
    mkdir -p "${rpicam_dst_dir}"
    install -m 0755 "${rpicam_src}" "${rpicam_dst}"
    echo "Installed custom rpicamera binary: ${rpicam_src} -> ${rpicam_dst}"
  else
    if [[ -f "${rpicam_dst}" ]]; then
      echo "Custom rpicamera binary not found at ${rpicam_src}; using existing bundled binary"
    else
      echo "Custom rpicamera binary not found at ${rpicam_src}; downloading bundled rpicamera binaries"
      (
        cd internal/staticsources/rpicamera
        go generate .
      )
    fi
  fi

  echo "Running targeted code generation..."
  (
    cd internal/core
    go generate .
  )
  (
    cd internal/servers/hls
    go generate .
  )

  echo "Building mediamtx..."
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o mediamtx .
}

need_apt_update=0
for pkg in "${APT_PACKAGES[@]}"; do
  if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
    need_apt_update=1
    break
  fi
done

if (( need_apt_update )); then
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y "${APT_PACKAGES[@]}"
fi

GO_VERSION="$(awk '/^go / { print $2; exit }' go.mod)"
if [[ -z "${GO_VERSION}" ]]; then
  echo "error: unable to determine Go version from go.mod" >&2
  exit 1
fi

GO_TARBALL="go${GO_VERSION}.linux-arm64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
GO_BIN="/usr/local/go/bin/go"

install_go=1
if [[ -x "${GO_BIN}" ]]; then
  INSTALLED_GO_VERSION="$("${GO_BIN}" version | awk '{print $3}' | sed 's/^go//')"
  if [[ "${INSTALLED_GO_VERSION}" == "${GO_VERSION}" ]]; then
    install_go=0
  fi
fi

if (( install_go )); then
  TMP_GO_ARCHIVE="$(mktemp "/tmp/${GO_TARBALL}.XXXXXX")"
  trap 'rm -f "${TMP_GO_ARCHIVE}"' EXIT

  curl -fL "${GO_URL}" -o "${TMP_GO_ARCHIVE}"
  "${SUDO[@]}" rm -rf /usr/local/go
  "${SUDO[@]}" tar -C /usr/local -xzf "${TMP_GO_ARCHIVE}"
fi

export PATH="/usr/local/go/bin:${PATH}"

echo "Using Go: $(go version)"
build_mediamtx

echo "Build complete: ${SCRIPT_DIR}/mediamtx"
echo "Custom rpicamera downloads were skipped; ${MTXRPICAM_PATH} remains the source of mtxrpicam when present."
