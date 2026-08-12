#!/usr/bin/env bash
# Idempotent Cloud Agent setup for the "Todo Train" repository.
#
# NOTE ON PLATFORM SUPPORT:
#   "Todo Train" is a native iOS app (SwiftUI + SwiftData + CloudKit, SDKROOT=iphoneos).
#   Building or running the app, its unit tests, or its UI tests requires macOS + Xcode
#   and the iOS SDK/Simulator, none of which exist on the Linux Cloud Agent VM. SwiftUI,
#   SwiftData and XCUITest are closed-source Apple frameworks unavailable on Linux.
#
#   This script therefore provisions the open-source Swift toolchain for Linux so agents
#   can compile and run portable Swift (Foundation-based logic, SwiftPM packages, and
#   Swift Testing). Apple-framework code in this repo cannot be compiled here.

set -euo pipefail

SWIFT_VERSION="6.3.3"
SWIFT_ROOT="/opt/swift"
SWIFT_BIN="${SWIFT_ROOT}/usr/bin"
UBUNTU_TAG="ubuntu24.04"
UBUNTU_DIR="ubuntu2404"
TARBALL="swift-${SWIFT_VERSION}-RELEASE-${UBUNTU_TAG}.tar.gz"
URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/${UBUNTU_DIR}/swift-${SWIFT_VERSION}-RELEASE/${TARBALL}"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo "==> Installing Swift-on-Linux build dependencies (apt)"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq --no-install-recommends \
  binutils \
  git \
  gnupg2 \
  libc6-dev \
  libcurl4-openssl-dev \
  libedit2 \
  libgcc-13-dev \
  libncurses-dev \
  libpython3-dev \
  libsqlite3-0 \
  libstdc++-13-dev \
  libxml2-dev \
  libz3-dev \
  pkg-config \
  tzdata \
  zip \
  unzip \
  zlib1g-dev

if [ -x "${SWIFT_BIN}/swift" ] && "${SWIFT_BIN}/swift" --version 2>/dev/null | grep -q "swift-${SWIFT_VERSION}"; then
  echo "==> Swift ${SWIFT_VERSION} already present at ${SWIFT_ROOT}, skipping download"
else
  echo "==> Downloading Swift ${SWIFT_VERSION} toolchain"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  curl -fsSL -o "${tmp}/${TARBALL}" "${URL}"
  $SUDO rm -rf "${SWIFT_ROOT}"
  $SUDO mkdir -p "${SWIFT_ROOT}"
  echo "==> Extracting toolchain to ${SWIFT_ROOT}"
  $SUDO tar xzf "${tmp}/${TARBALL}" -C "${SWIFT_ROOT}" --strip-components=1
fi

echo "==> Linking swift binaries onto PATH (/usr/local/bin)"
$SUDO ln -sf "${SWIFT_BIN}/swift" /usr/local/bin/swift
$SUDO ln -sf "${SWIFT_BIN}/swiftc" /usr/local/bin/swiftc

echo "==> Swift toolchain ready:"
/usr/local/bin/swift --version
