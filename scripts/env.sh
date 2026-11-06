# Source this file (inside WSL) to enter the project-local opam switch.
ROCQ2MBT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ "$ROCQ2MBT_ROOT" == /mnt/* ]]; then
  _sw="$HOME/.local/share/rocq2mbt"
else
  _sw="$ROCQ2MBT_ROOT"
fi
eval "$(opam env --switch="$_sw" --set-switch)"
export PATH="$HOME/.moon/bin:$PATH"
unset _sw
