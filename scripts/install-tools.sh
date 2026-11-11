#!/usr/bin/env bash
# Installs the pinned versions of the analysis tools into a local directory.
#
# Used by developers and by CI, so both run exactly the same versions. Every
# download is verified against the checksum file published with the release
# before it is unpacked.
#
# Usage: install-tools.sh [tool ...]     (default: all tools)
#        BIN_DIR=/some/dir install-tools.sh
set -euo pipefail

TFLINT_VERSION=0.66.0
TRIVY_VERSION=0.76.2

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "Unsupported operating system: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# fetch <base-url> <file> <checksums-file>: downloads <file> and verifies it.
fetch() {
  local base=$1 file=$2 sums=$3
  curl --fail --silent --show-error --location --retry 3 --output "$work/$file" "$base/$file"
  curl --fail --silent --show-error --location --retry 3 --output "$work/$sums" "$base/$sums"
  (cd "$work" && grep " $file\$" "$sums" | sha256sum --check --status) ||
    { echo "Checksum mismatch for $file" >&2; exit 1; }
}

# installed <binary> <version>: true when that version is already in BIN_DIR.
installed() {
  [ -x "$BIN_DIR/$1" ] && "$BIN_DIR/$1" --version 2>/dev/null | grep --quiet --fixed-strings "$2"
}

install_tflint() {
  if installed tflint "$TFLINT_VERSION"; then echo "tflint $TFLINT_VERSION already installed"; return; fi
  local file="tflint_${os}_${arch}.zip"
  fetch "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}" "$file" checksums.txt
  unzip -o -q "$work/$file" tflint -d "$BIN_DIR"
  echo "tflint $TFLINT_VERSION installed"
}

install_trivy() {
  if installed trivy "$TRIVY_VERSION"; then echo "trivy $TRIVY_VERSION already installed"; return; fi
  local trivy_os trivy_arch
  [ "$os" = linux ] && trivy_os=Linux || trivy_os=macOS
  [ "$arch" = amd64 ] && trivy_arch=64bit || trivy_arch=ARM64
  local file="trivy_${TRIVY_VERSION}_${trivy_os}-${trivy_arch}.tar.gz"
  fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}" "$file" "trivy_${TRIVY_VERSION}_checksums.txt"
  tar --extract --gzip --file "$work/$file" --directory "$BIN_DIR" trivy
  echo "trivy $TRIVY_VERSION installed"
}

tools=("$@")
[ ${#tools[@]} -gt 0 ] || tools=(tflint trivy)

for tool in "${tools[@]}"; do
  case "$tool" in
    tflint) install_tflint ;;
    trivy) install_trivy ;;
    *) echo "Unknown tool: $tool" >&2; exit 1 ;;
  esac
done

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Add $BIN_DIR to your PATH to use these tools." ;;
esac
