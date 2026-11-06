#!/usr/bin/env bash
# Build everything and run all tests:
#   1. the plugin and theories (dune),
#   2. the MoonBit runtime rocqrt and the mbti2rocq tool,
#   3. mbti2rocq on tests/moon/mlib  ->  tests/gen/Mlib.v,
#   4. extraction of tests/*.v into the packages of tests/moon,
#   5. `moon test` of the extracted code.
# Usage: tests/run.sh [moon targets...]   (default: wasm-gc wasm native)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/env.sh"
cd "$ROOT"
dune build 2>&1

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(wasm-gc wasm native)

echo "== rocqrt"
(cd "$ROOT/mbt/rocqrt" && for t in "${targets[@]}"; do moon test --target "$t"; done)

echo "== mbti2rocq"
(cd "$ROOT/mbt/mbti2rocq" && moon build --target native --release)
MBTI2ROCQ="$ROOT/mbt/mbti2rocq/_build/native/release/build/cmd/main/main.exe"

export OCAMLPATH="$ROOT/_build/install/default/lib${OCAMLPATH:+:$OCAMLPATH}"
ROCQ_FLAGS=(-w -extraction-default-directory
            -Q "$ROOT/_build/default/theories" RocqMbt -R "$ROOT/tests/gen" Gen)

cd "$ROOT/tests/moon"
echo "== moon info + mbti2rocq (mlib)"
moon info --target native -p rocq2mbt/tests/mlib >/dev/null
"$MBTI2ROCQ" mlib/pkg.generated.mbti -o "$ROOT/tests/gen/Mlib.v"
(cd "$ROOT/tests/gen" && rocq c "${ROCQ_FLAGS[@]}" Mlib.v)

for v in "$ROOT"/tests/*.v; do
  echo "== extracting $(basename "$v")"
  rocq c "${ROCQ_FLAGS[@]}" "$v"
done

for t in "${targets[@]}"; do
  for p in basic advanced prim interop; do
    echo "== moon test --target $t ($p)"
    moon test --target "$t" -p "rocq2mbt/tests/$p"
  done
done
# Code needing rocq_magic only runs on backends with a uniform representation.
echo "== moon test --target wasm (magic)"
moon test --target wasm -p rocq2mbt/tests/magic
