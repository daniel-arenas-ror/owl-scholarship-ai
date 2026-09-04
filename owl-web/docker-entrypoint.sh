#!/bin/sh
# node_modules lives in a named volume (owl_web_node_modules) so it survives
# an image rebuild — but that means it doesn't auto-update when
# package-lock.json changes. Reconcile on every boot before exec'ing.
#
# (npm's own node_modules/.package-lock.json omits the root package entry, so
# it never byte-compares equal to package-lock.json — hence our own marker.)
set -e

if ! cmp -s package-lock.json node_modules/.owl-lockfile-marker 2>/dev/null; then
  echo "package-lock.json changed — running npm ci"
  npm ci
  cp package-lock.json node_modules/.owl-lockfile-marker
fi

exec "$@"
