#!/bin/bash
# Slurm job array: one task = one (L, h) point of a TFIM sweep.
# Don't submit this directly; use cluster/submit_sweep.sh, which writes the
# parameter file and exports SWEEP_DIR / COMMON_ARGS.
#
# Resources below are per array task (one Julia process, multithreaded).
# Override on the command line of submit_sweep.sh via SBATCH_EXTRA, e.g.
#     SBATCH_EXTRA="--cpus-per-task=16 --mem=64G --time=12:00:00" bash cluster/submit_sweep.sh big
#SBATCH --job-name=tfim
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --qos=serial
set -euo pipefail

: "${SWEEP_DIR:?SWEEP_DIR not set (use cluster/submit_sweep.sh)}"
: "${COMMON_ARGS:=}"
REPO=${SLURM_SUBMIT_DIR:-$(pwd)}
cd "$REPO"

source "$REPO/cluster/julia_env.sh"
export JULIA_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}

LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SWEEP_DIR/params.txt")
[ -n "$LINE" ] || { echo "no parameters for task $SLURM_ARRAY_TASK_ID" >&2; exit 1; }

echo "host=$(hostname) job=$SLURM_JOB_ID task=$SLURM_ARRAY_TASK_ID threads=$JULIA_NUM_THREADS"
echo "params: $LINE $COMMON_ARGS"
echo "start: $(date)"

# shellcheck disable=SC2086
julia --project=. src/tfim_dynamics.jl $LINE $COMMON_ARGS out="$SWEEP_DIR/data"

echo "end: $(date)"
