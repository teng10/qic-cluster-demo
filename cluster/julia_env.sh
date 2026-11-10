# Sourced by setup_jed.sh and the sbatch script. Puts a `julia` on PATH on Jed.
# Order: an existing julia, then a SCITAS module, then juliaup in $HOME (installed if missing).
# Override with JULIA_BIN=/path/to/julia if you keep Julia somewhere else.
if [ -n "${JULIA_BIN:-}" ]; then
    export PATH="$(dirname "$JULIA_BIN"):$PATH"
fi
if ! command -v julia >/dev/null 2>&1; then
    if command -v module >/dev/null 2>&1; then
        # module scripts may reference unset variables; don't let `set -u` in the caller abort
        _jl_opts=$-; set +u
        module load julia >/dev/null 2>&1 || true
        case $_jl_opts in *u*) set -u ;; esac
    fi
fi
if ! command -v julia >/dev/null 2>&1; then
    if [ ! -x "$HOME/.juliaup/bin/julia" ]; then
        echo "No julia found: installing Julia 1.10 (lts) via juliaup into \$HOME/.juliaup"
        curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel lts
    fi
    export PATH="$HOME/.juliaup/bin:$PATH"
fi
command -v julia >/dev/null 2>&1 || { echo "julia still not found" >&2; exit 1; }
