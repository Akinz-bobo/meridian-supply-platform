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
CONFTEST_VERSION=0.71.1
TERRAFORM_DOCS_VERSION=0.24.0
KUBECTL_VERSION=1.36.6
HELM_VERSION=4.3.1

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

# installed <binary> <version> [version command...]: true when that version
# is already in BIN_DIR.
# Most tools print their version with --version. kubectl and helm use a
# subcommand, passed as the remaining arguments.
installed() {
  [ -x "$BIN_DIR/$1" ] || return 1
  local binary=$1 wanted=$2
  shift 2
  [ $# -gt 0 ] || set -- --version
  # Capture first: piping straight into `grep --quiet` can close the pipe
  # early and make the tool exit non-zero under pipefail.
  local version
  version="$("$BIN_DIR/$binary" "$@" 2>/dev/null || true)"
  grep --quiet --fixed-strings "$wanted" <<<"$version"
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

install_conftest() {
  if installed conftest "$CONFTEST_VERSION"; then echo "conftest $CONFTEST_VERSION already installed"; return; fi
  local conftest_os conftest_arch
  [ "$os" = linux ] && conftest_os=Linux || conftest_os=Darwin
  [ "$arch" = amd64 ] && conftest_arch=x86_64 || conftest_arch=arm64
  local file="conftest_${CONFTEST_VERSION}_${conftest_os}_${conftest_arch}.tar.gz"
  fetch "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}" "$file" checksums.txt
  tar --extract --gzip --file "$work/$file" --directory "$BIN_DIR" conftest
  echo "conftest $CONFTEST_VERSION installed"
}

install_terraform_docs() {
  if installed terraform-docs "$TERRAFORM_DOCS_VERSION"; then
    echo "terraform-docs $TERRAFORM_DOCS_VERSION already installed"
    return
  fi
  local file="terraform-docs-v${TERRAFORM_DOCS_VERSION}-${os}-${arch}.tar.gz"
  fetch "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}" \
    "$file" "terraform-docs-v${TERRAFORM_DOCS_VERSION}.sha256sum"
  tar --extract --gzip --file "$work/$file" --directory "$BIN_DIR" terraform-docs
  echo "terraform-docs $TERRAFORM_DOCS_VERSION installed"
}

install_kubectl() {
  if installed kubectl "v$KUBECTL_VERSION" version --client; then echo "kubectl $KUBECTL_VERSION already installed"; return; fi
  local base="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${os}/${arch}"
  curl --fail --silent --show-error --location --retry 3 --output "$work/kubectl" "$base/kubectl"
  curl --fail --silent --show-error --location --retry 3 --output "$work/kubectl.sha256" "$base/kubectl.sha256"
  # The published file holds the digest alone, with no file name.
  (cd "$work" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --status) ||
    { echo 'Checksum mismatch for kubectl' >&2; exit 1; }
  install -m 0755 "$work/kubectl" "$BIN_DIR/kubectl"
  echo "kubectl $KUBECTL_VERSION installed"
}

install_helm() {
  if installed helm "v$HELM_VERSION" version; then echo "helm $HELM_VERSION already installed"; return; fi
  local file="helm-v${HELM_VERSION}-${os}-${arch}.tar.gz"
  fetch "https://get.helm.sh" "$file" "$file.sha256sum"
  tar --extract --gzip --file "$work/$file" --directory "$work" "${os}-${arch}/helm"
  install -m 0755 "$work/${os}-${arch}/helm" "$BIN_DIR/helm"
  echo "helm $HELM_VERSION installed"
}

tools=("$@")
[ ${#tools[@]} -gt 0 ] || tools=(tflint trivy conftest terraform-docs kubectl helm)

for tool in "${tools[@]}"; do
  case "$tool" in
    tflint) install_tflint ;;
    trivy) install_trivy ;;
    conftest) install_conftest ;;
    terraform-docs) install_terraform_docs ;;
    kubectl) install_kubectl ;;
    helm) install_helm ;;
    *) echo "Unknown tool: $tool" >&2; exit 1 ;;
  esac
done

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Add $BIN_DIR to your PATH to use these tools." ;;
esac
