#!/usr/bin/env bash
# ============================================================
# Compile UVVM utility library into the local sim library.
# Verified against UVVM 2.21.4 + GHDL 4.1.0.
# Driven by the repo's own compile_order.txt — never a hardcoded list.
# ============================================================
set -euo pipefail

UVVM="sub/uvvm/uvvm_util"          # submodule location (matches Makefile)
LIB="sim/uvvm_lib/uvvm_util"       # compiled output (gitignored)
ORDER="$UVVM/script/compile_order.txt"

if [[ ! -f "$ORDER" ]]; then
  echo "ERROR: $ORDER not found." >&2
  echo "       Did you pull the submodule?  git submodule update --init --recursive" >&2
  exit 1
fi

mkdir -p "$LIB"

# Parse compile_order.txt: strip comments + blanks, resolve its ../src/ paths,
# compile each file in order into the uvvm_util library.
grep -v '^#' "$ORDER" | grep -v '^[[:space:]]*$' \
  | sed "s#\.\./src/#$UVVM/src/#" \
  | while read -r f; do
      ghdl -a --std=08 -frelaxed --work=uvvm_util --workdir="$LIB" "$f"
    done

echo "uvvm_util compiled OK -> $LIB"
