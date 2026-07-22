#!/usr/bin/env bash
set -euo pipefail

version="${SOPS_VERSION:-3.13.2}"
install_dir="${SOPS_INSTALL_DIR:-${HOME}/.local/bin}"

if command -v sops >/dev/null 2>&1; then
  printf 'Using SOPS: %s\n' "$(command -v sops)"
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  echo "Error: curl is required to install SOPS." >&2
  exit 1
}

case "$(uname -s)" in
  Linux) platform=linux ;;
  Darwin) platform=darwin ;;
  *)
    echo "Error: automatic SOPS installation supports Linux, WSL, and macOS." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *)
    echo "Error: unsupported CPU architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

asset="sops-v${version}.${platform}.${arch}"
release_url="https://github.com/getsops/sops/releases/download/v${version}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL "$release_url/$asset" -o "$tmp_dir/$asset"
curl -fsSL "$release_url/sops-v${version}.checksums.txt" \
  -o "$tmp_dir/checksums.txt"

expected="$(awk -v asset="$asset" '$2 == asset {print $1}' "$tmp_dir/checksums.txt")"
if [[ -z "$expected" ]]; then
  echo "Error: SOPS release checksum does not list $asset." >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$tmp_dir/$asset" | awk '{print $1}')"
else
  echo "Error: sha256sum or shasum is required to verify SOPS." >&2
  exit 1
fi

if [[ "$actual" != "$expected" ]]; then
  echo "Error: SOPS checksum verification failed." >&2
  exit 1
fi

mkdir -p "$install_dir"
install -m 0755 "$tmp_dir/$asset" "$install_dir/sops"
printf 'Installed SOPS %s at %s\n' "$version" "$install_dir/sops"
