#!/usr/bin/env bash
#
# Measure cold + warm build times for a pinned workload on a github-hosted
# runner, using the toolchain that the upstream setup-* actions put on PATH.
# Emits rows in the same schema the Fjord bench harness uses, with
# scenario=github, so rasterstate/fjord-actions can drop the CSV straight into
# its results dir and render the "GitHub Actions" column.
#
# Usage: measure.sh <rust|node|go> <out.csv>
#
# "warm" is a second build with the toolchain's on-disk caches left intact:
# exactly the state actions/cache restores at the start of a steady-state run.
# That makes it the fair comparison to the Fjord warm (cache-restored) number.

set -euo pipefail

lang="${1:?usage: measure.sh <rust|node|go> <out.csv>}"
out="${2:?usage: measure.sh <rust|node|go> <out.csv>}"
run_id="${RUN_ID:-$(date +%s)}"
bench_dir="$(mktemp -d)"
ws="${bench_dir}/workload"

case "$lang" in
  rust) url=https://github.com/BurntSushi/ripgrep.git; ref=14.1.1 ;;
  node) url=https://github.com/axios/axios.git;        ref=v1.7.9 ;;
  go)   url=https://github.com/cli/cli.git;            ref=v2.62.0 ;;
  *) echo "unknown lang: $lang" >&2; exit 2 ;;
esac

echo "[gh-bench] ${lang} ${url}@${ref}"
git clone --depth 1 --branch "$ref" "$url" "$ws" >/dev/null 2>&1

os="$(uname -s)"
arch="$(uname -m)"
emit() { # emit phase seconds
  printf '%s,github,%s,%s,%s,%s,%s,%s\n' "$lang" "$1" "$2" "$os" "$arch" "$run_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$out"
}
now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
elapsed() { python3 -c "print(f'{${1}-${2}:.3f}')"; }

# Isolated caches so we control cold vs warm, never the runner's shared dirs.
cargo_home="${bench_dir}/cargo-home"
npm_cache="${bench_dir}/npm-cache"
gomodcache="${bench_dir}/gomodcache"
gocache="${bench_dir}/gocache"

build() { # build [offline]
  case "$lang" in
    rust)
      ( cd "$ws" && CARGO_HOME="$cargo_home" CARGO_TERM_COLOR=never cargo build --release --quiet ) ;;
    node)
      local extra=()
      [ "${1:-}" = "offline" ] && extra=(--prefer-offline)
      local cmd=install
      if [ -f "${ws}/package-lock.json" ] || [ -f "${ws}/npm-shrinkwrap.json" ]; then
        cmd=ci
      fi
      ( cd "$ws" && npm "$cmd" --cache "$npm_cache" --no-audit --no-fund --silent "${extra[@]}" ) ;;
    go)
      ( cd "$ws" && GOMODCACHE="$gomodcache" GOCACHE="$gocache" GOFLAGS=-mod=mod go build ./... ) ;;
  esac
}

reset_cold() {
  case "$lang" in
    rust) rm -rf "$cargo_home" "${ws}/target" ;;
    node) rm -rf "$npm_cache" "${ws}/node_modules" ;;
    go)   rm -rf "$gomodcache" "$gocache" ;;
  esac
}

# Cold: empty caches.
reset_cold
t0=$(now); build; t1=$(now)
emit cold "$(elapsed "$t1" "$t0")"

# Warm: rebuild with caches intact. npm ci always wipes node_modules, so the
# warm win there comes from the populated download cache (offline reinstall).
if [ "$lang" = node ]; then
  rm -rf "${ws}/node_modules"
  t0=$(now); build offline; t1=$(now)
else
  t0=$(now); build; t1=$(now)
fi
emit warm "$(elapsed "$t1" "$t0")"

echo "[gh-bench] ${lang} done"
