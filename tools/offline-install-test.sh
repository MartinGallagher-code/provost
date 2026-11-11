#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# offline-install-test.sh -- the offline bundle's install test, in a container
# with networking off.
#
# Usage: tools/offline-install-test.sh BUNDLE_DIR IMAGE
#
# IMAGE is a Debian-based python image (python:3.8-slim, the floor
# pyproject.toml promises) or a RHEL UBI image (registry.access.redhat.com/
# ubi9/ubi). The image first gets the host tools provost needs and an air-gapped
# host is assumed to have (git, and python3 on UBI), with the network on;
# then tools/offline-install-check.sh runs in it with --network none and the
# bundle mounted read-only. Needs docker.
set -euo pipefail

bundle="${1:?usage: offline-install-test.sh BUNDLE_DIR IMAGE}"
image="${2:?usage: offline-install-test.sh BUNDLE_DIR IMAGE}"
bundle="$(cd "$bundle" && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$image" in
    python:*)
        prep='apt-get update -qq && apt-get install -y -qq --no-install-recommends git >/dev/null && rm -rf /var/lib/apt/lists/*' ;;
    *ubi*|*rhel*|*rocky*|*almalinux*)
        prep='dnf install -y -q python3 python3-pip git-core && dnf clean all' ;;
    *)
        echo "offline-install-test.sh: no recipe for image $image" >&2; exit 2 ;;
esac

tag="provost-offline-test:$(printf '%s' "$image" | tr -c 'A-Za-z0-9_.-' '_')"
printf 'FROM %s\nRUN %s\n' "$image" "$prep" | docker build -q -t "$tag" - >/dev/null

docker run --rm --network none \
    -e PROVOST_OFFLINE_EXPECT_NO_NETWORK=1 \
    -v "$bundle:/bundle:ro" \
    -v "$here/offline-install-check.sh:/offline-install-check.sh:ro" \
    "$tag" bash /offline-install-check.sh /bundle python3
