#!/usr/bin/env bash
#
# Reclaim disk space on GitHub-hosted ubuntu-latest runners before the
# Android build.
#
# Why this exists: the nightly was failing at
# `:react-native-reanimated:mergeDebugNativeLibs` with
# `System.IO.IOException: No space left on device`. mergeDebugNativeLibs
# is the disk-heaviest Gradle task — it copies and merges every native
# `.so` into one staging dir: the Rarimo arm64 prebuilts (RmoCalcs +
# witnesscalc_*), rapidsnark, the witnesscalculator module, Hermes,
# reanimated and the rest of the RN/Expo native libs. On top of
# node_modules, the restored Gradle cache and the rest of the build tree,
# that overflows the runner's ~14 GB root disk and the build dies mid-merge.
#
# ubuntu-latest ships ~30 GB of preinstalled toolchains we don't use
# (Haskell, .NET, Swift, CodeQL, PowerShell, browsers, Docker images).
# Removing them up front gives the native-lib merge and D8 dex-merge room
# to finish. Every removal is best-effort (`|| true`) so a missing path on
# a future runner image never fails the build. We deliberately do NOT touch
# the Android SDK/NDK, Java, or Node — the build needs all of those.

set -uo pipefail

echo "=== Disk before cleanup ==="
df -h /

# Haskell (~9 GB) — the single biggest win.
sudo rm -rf /opt/ghc /usr/local/.ghcup || true
# .NET (~1.6 GB)
sudo rm -rf /usr/share/dotnet || true
# Swift (~2 GB)
sudo rm -rf /usr/share/swift || true
# CodeQL bundles in the hosted tool cache (~5 GB)
sudo rm -rf /opt/hostedtoolcache/CodeQL || true
# PowerShell (~1 GB)
sudo rm -rf /usr/local/share/powershell || true
# Preinstalled browsers we don't drive in this job (~1 GB)
sudo rm -rf /usr/local/share/chromium /opt/google/chrome /opt/microsoft || true
# Preloaded Docker images (~several GB) — not used by a Gradle build.
docker image prune --all --force || true

echo "=== Disk after cleanup ==="
df -h /
