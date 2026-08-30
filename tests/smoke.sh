#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_dir/biliup.sh"

bash -n "$script"
[[ "$(bash "$script" --version)" == "$(<"$repo_dir/VERSION")" ]]
bash "$script" --help >/dev/null

if bash "$script" --samples 0 >/dev/null 2>&1; then
  printf 'expected --samples 0 to fail\n' >&2
  exit 1
fi

printf 'smoke tests passed\n'
