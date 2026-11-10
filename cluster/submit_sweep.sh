#!/bin/bash
# Submit a (system size) x (field) sweep as one Slurm job array on Jed.
#
#     bash cluster/submit_sweep.sh <sweep_name>
#
# Parameter lists and solver settings are environment variables with defaults
# below, so a custom sweep is e.g.
#     Ls="20 40" hs="0.5 1.0 1.5" COMMON_ARGS="dt=0.05 nsteps=200 max_weight=10 min_abs_coeff=1e-7" \
#         bash cluster/submit_sweep.sh test1
#
# Results land in $TFIM_DATA_ROOT/<sweep_name>/data/*.json  (default ~/tfim-data),
# Slurm logs in           $TFIM_DATA_ROOT/<sweep_name>/logs/.
set -euo pipefail

SWEEP=${1:?usage: $0 <sweep_name>}
Ls=${Ls:-"20 40 80"}
hs=${hs:-"0.25 0.5 1.0 1.5 2.0"}
COMMON_ARGS=${COMMON_ARGS:-"J=1.0 dt=0.05 nsteps=100 max_weight=8 min_abs_coeff=1e-6 sites=mid"}
MAX_CONCURRENT=${MAX_CONCURRENT:-20}       # array throttle: at most this many tasks at once
SBATCH_EXTRA=${SBATCH_EXTRA:-}             # extra sbatch flags, e.g. "--cpus-per-task=16 --time=08:00:00"
DATA_ROOT=${TFIM_DATA_ROOT:-$HOME/tfim-data}

REPO=$(cd "$(dirname "$0")/.." && pwd)
SWEEP_DIR="$DATA_ROOT/$SWEEP"
if [ -e "$SWEEP_DIR/params.txt" ]; then
    echo "Sweep '$SWEEP' already exists at $SWEEP_DIR. Pick a new name or delete it." >&2
    exit 1
fi
mkdir -p "$SWEEP_DIR/data" "$SWEEP_DIR/logs"

PARAMS="$SWEEP_DIR/params.txt"
: > "$PARAMS"
for L in $Ls; do
    for h in $hs; do
        echo "L=$L h=$h" >> "$PARAMS"
    done
done
N=$(wc -l < "$PARAMS" | tr -d ' ')
{
    echo "submitted: $(date)"
    echo "repo: $REPO ($(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo no-git))"
    echo "Ls: $Ls"
    echo "hs: $hs"
    echo "COMMON_ARGS: $COMMON_ARGS"
    echo "SBATCH_EXTRA: $SBATCH_EXTRA"
} > "$SWEEP_DIR/sweep_info.txt"

echo "Sweep '$SWEEP': $N tasks  (Ls: $Ls | hs: $hs)"
echo "common args: $COMMON_ARGS"
echo "output dir:  $SWEEP_DIR"

cd "$REPO"
# shellcheck disable=SC2086
sbatch --array="1-${N}%${MAX_CONCURRENT}" \
       --output="$SWEEP_DIR/logs/%x_%A_%a.out" \
       --export=ALL,SWEEP_DIR="$SWEEP_DIR",COMMON_ARGS="$COMMON_ARGS" \
       $SBATCH_EXTRA \
       cluster/tfim_array.sbatch
