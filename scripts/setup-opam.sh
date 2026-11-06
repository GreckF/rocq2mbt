#!/usr/bin/env bash
# Create the project-local opam switch for rocq2mbt (run inside WSL / Linux).
#
# Rocq "9.4+alpha" here means the development version on rocq master: the
# git tag V9.4+alpha predates the extensible extraction API (rocq PR #22541,
# merged 2026-10-05), so we pin a master commit that contains it.
set -euo pipefail

ROCQ_COMMIT=${ROCQ_COMMIT:-04441865c6077185ad35eaeee719e8c9c5c5bb67}
OCAML_VERSION=${OCAML_VERSION:-5.4.1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# When the project lives on a Windows drive (/mnt/c, 9p), building the switch
# there is very slow. Keep the switch on the Linux filesystem and symlink it.
SWITCH_DIR="$ROOT"
if [[ "$ROOT" == /mnt/* ]]; then
  SWITCH_DIR="$HOME/.local/share/rocq2mbt"
  mkdir -p "$SWITCH_DIR"
fi

if [[ ! -d "$SWITCH_DIR/_opam" ]]; then
  opam switch create "$SWITCH_DIR" "ocaml-base-compiler.$OCAML_VERSION" --no-install -y
fi
if [[ "$SWITCH_DIR" != "$ROOT" && ! -e _opam ]]; then
  ln -s "$SWITCH_DIR/_opam" _opam
fi
eval "$(opam env --switch="$SWITCH_DIR" --set-switch)"

opam pin add -y --no-action rocq-runtime "git+https://github.com/rocq-prover/rocq.git#$ROCQ_COMMIT"
opam pin add -y --no-action rocq-core    "git+https://github.com/rocq-prover/rocq.git#$ROCQ_COMMIT"
opam install -y rocq-runtime rocq-core
rocq --version
