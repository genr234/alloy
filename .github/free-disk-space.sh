#!/usr/bin/env bash
# GitHub's hosted runners ship with large toolchains we don't use; the kernel
# build and the image need the room.
set -euo pipefail
df -h /
sudo rm -rf \
  /usr/share/dotnet \
  /usr/local/lib/android \
  /opt/ghc \
  /usr/local/.ghcup \
  /opt/hostedtoolcache/CodeQL \
  /usr/local/share/boost \
  /usr/local/share/powershell \
  /usr/share/swift || true
sudo docker image prune --all --force >/dev/null 2>&1 || true
df -h /
