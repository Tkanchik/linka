#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$(mktemp)"
trap 'rm -f -- "$bundle"' EXIT

for script in "$root/linka" "$root/install.sh" "$root"/lib/*.sh "$root"/qa/*.sh; do
    bash -n "$script"
done

cat "$root"/lib/*.sh "$root/linka" > "$bundle"
shellcheck -S warning -s bash -e SC1090 "$bundle"
shellcheck -S warning "$root/install.sh"
shellcheck -S warning -s bash -e SC2034 "$root"/qa/*.sh
