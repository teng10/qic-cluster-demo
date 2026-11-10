#!/bin/bash
# One-time setup on the Jed login node. Run from anywhere:
#     bash cluster/setup_jed.sh
# 1. makes sure a Julia binary is available (SCITAS module if present, otherwise juliaup in $HOME)
# 2. instantiates + precompiles this project so array jobs don't all compile at once
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

source "$REPO/cluster/julia_env.sh"

echo "Using julia: $(command -v julia)"
julia --version
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile(); using PauliPropagation; println("PauliPropagation ", pkgversion(PauliPropagation), " OK")'
echo "Setup done. Submit a sweep with:  bash cluster/submit_sweep.sh <sweep_name>"
