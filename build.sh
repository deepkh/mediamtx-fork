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

get_build_commit() {
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    git rev-parse HEAD
  else
    echo "unknown"
  fi
}

build_mediamtx() {
  local rpicam_src="${SCRIPT_DIR}/${MTXRPICAM_PATH}"
  local rpicam_build_dir
  rpicam_build_dir="$(dirname "${rpicam_src}")"
  local rpicam_prefix_dir="${rpicam_build_dir}/../prefix"
  local rpicam_lib_src_dir="${rpicam_build_dir}/../prefix/lib/aarch64-linux-gnu"
  local rpicam_dst_dir="${SCRIPT_DIR}/internal/staticsources/rpicamera/mtxrpicam_64"
  local rpicam_dst="${rpicam_dst_dir}/mtxrpicam"

  copy_and_check_md5() {
    local src="$1"
    local dst="$2"
    local dst_parent
    dst_parent="$(dirname "${dst}")"

    if [[ ! -e "${src}" ]]; then
      echo "error: required rpicamera file not found: ${src}" >&2
      exit 1
    fi

    mkdir -p "${dst_parent}"
    rm -f "${dst}"
    cp -L -p "${src}" "${dst}"

    local src_md5
    local dst_md5
    src_md5="$(md5sum "${src}" | awk '{print $1}')"
    dst_md5="$(md5sum "${dst}" | awk '{print $1}')"

    echo "Copied rpicamera runtime file: ${src} -> ${dst}"
    if [[ -L "${src}" ]]; then
      echo "  source link: ${src} -> $(readlink "${src}")"
    fi
    echo "  source md5: ${src_md5}"
    echo "  dest md5:   ${dst_md5}"

    if [[ "${src_md5}" != "${dst_md5}" ]]; then
      echo "error: md5 mismatch after copy: ${src} -> ${dst}" >&2
      echo "source md5: ${src_md5}" >&2
      echo "dest md5:   ${dst_md5}" >&2
      exit 1
    fi
  }

  copy_rpicam_runtime_files() {
    local runtime_files=(
      "libcamera/ipa_rpi_pisp.so"
      "libcamera/ipa_rpi_pisp.so.sign"
      "libcamera/ipa_rpi_vc4.so"
      "libcamera/ipa_rpi_vc4.so.sign"
      "libcamera-base.so.9.9.9"
      "libcamera-base.so.9.9"
      "libcamera-base.so"
      "libcamera.so.9.9.9"
      "libcamera.so.9.9"
      "libcamera.so"
      "libexec/libcamera/raspberrypi_ipa_proxy"
    )

    for runtime_file in "${runtime_files[@]}"; do
      local runtime_src="${rpicam_lib_src_dir}/${runtime_file}"
      if [[ "${runtime_file}" == libexec/* ]]; then
        runtime_src="${rpicam_prefix_dir}/${runtime_file}"
      fi

      copy_and_check_md5 \
        "${runtime_src}" \
        "${rpicam_dst_dir}/${runtime_file}"
    done
  }

  if [[ -f "${rpicam_src}" ]]; then
    mkdir -p "${rpicam_dst_dir}"
    install -m 0755 "${rpicam_src}" "${rpicam_dst}"
    echo "Installed custom rpicamera binary: ${rpicam_src} -> ${rpicam_dst}"
    copy_rpicam_runtime_files
    echo "Installed custom rpicamera runtime files from ${rpicam_lib_src_dir}"
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
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -ldflags "-X main.buildCommit=${BUILD_COMMIT}" -o mediamtx .
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

BUILD_COMMIT="$(get_build_commit)"

echo "Using Go: $(go version)"
echo "Building commit: ${BUILD_COMMIT}"
build_mediamtx

echo "Build complete: ${SCRIPT_DIR}/mediamtx"
echo "Custom rpicamera downloads were skipped; ${MTXRPICAM_PATH} remains the source of mtxrpicam when present."
