#!/usr/bin/env bash
# Build the plugin, extract tests/*.v to MoonBit, then compile & run the
# MoonBit tests.  Usage: tests/run.sh [moon targets...]  (default: all
# backends that do not need node: wasm-gc wasm native)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/env.sh"
cd "$ROOT"
dune build 2>&1

export OCAMLPATH="$ROOT/_build/install/default/lib${OCAMLPATH:+:$OCAMLPATH}"
cd "$ROOT/tests/moon"
for v in "$ROOT"/tests/*.v; do
  echo "== extracting $(basename "$v")"
  rocq c -w -extraction-default-directory -Q "$ROOT/_build/default/theories" RocqMbt "$v"
done

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(wasm-gc wasm native)
for t in "${targets[@]}"; do
  for p in basic advanced; do
    echo "== moon test --target $t ($p)"
    moon test --target "$t" -p "rocq2mbt/tests/$p"
  done
done
# Code needing rocq_magic only runs on backends with a uniform representation.
echo "== moon test --target wasm (magic)"
moon test --target wasm -p rocq2mbt/tests/magic
