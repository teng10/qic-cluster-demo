# qic-cluster-test — TFIM Z-dynamics with Pauli propagation on Jed

Heisenberg-picture time evolution of `Z_i` for the 1D transverse-field Ising model

    H = J Σ Z_i Z_{i+1} + h Σ X_i ,   |ψ(0)⟩ = |0…0⟩

computed with [PauliPropagation.jl](https://github.com/MSRudolph/PauliPropagation.jl)
(second-order Trotter, step `dt`), swept over system size `L` and field `h` as a Slurm
job array on EPFL's Jed cluster, then analysed locally in a notebook.

```
src/tfim_dynamics.jl      simulation: one (L, h, …) point -> one JSON file
cluster/setup_jed.sh      one-time: Julia + project instantiate on Jed
cluster/submit_sweep.sh   writes params.txt and submits the job array
cluster/tfim_array.sbatch Slurm array script (one task = one parameter line)
cluster/julia_env.sh      finds/installs julia on Jed (sourced by the two above)
scripts/fetch_data.sh     rsync results from Jed into ./data/
notebooks/analysis.ipynb  plots + exact-diagonalization check (Python, numpy/matplotlib)
```

## 1. Run locally (quick test)

```bash
julia -t auto --project=. src/tfim_dynamics.jl L=12 h=1.0 dt=0.05 nsteps=60 sites=mid out=data/local/data
```

All arguments are `key=value` with defaults (see the header of `src/tfim_dynamics.jl`):
`L`, `h`, `J`, `dt`, `nsteps`, `max_weight` (Pauli-weight truncation, default none),
`min_abs_coeff` (coefficient truncation, default `1e-6`), `sites` (`mid` | `all` | `half` | `3,7,12`),
`periodic`, `out`, `tag`.

## 2. One-time setup on Jed

Add to `~/.ssh/config` on your Mac (replace the username with your GASPAR login):

```
Host jed
    HostName jed.hpc.epfl.ch
    User <gaspar-username>
```

Then

```bash
ssh jed
git clone https://github.com/teng10/qic-cluster-test.git && cd qic-cluster-test
bash cluster/setup_jed.sh
```

`setup_jed.sh` uses an existing `julia`, else `module load julia`, else installs Julia 1.10
via juliaup into `~/.juliaup` (set `JULIA_BIN=/path/to/julia` to force a specific binary).
It then instantiates and precompiles the project so the array tasks start immediately.

If your Slurm account is not picked up by default, `export SBATCH_ACCOUNT=<lab-account>`
before submitting (or add `#SBATCH --account=…` to `cluster/tfim_array.sbatch`).

## 3. Submit a sweep

```bash
bash cluster/submit_sweep.sh sweep1
```

Defaults: `Ls="20 40 80"`, `hs="0.25 0.5 1.0 1.5 2.0"`,
`COMMON_ARGS="J=1.0 dt=0.05 nsteps=100 max_weight=8 min_abs_coeff=1e-6 sites=mid"`,
8 cores / 16 GB / 2 h per task, at most 20 tasks at once. Everything is overridable:

```bash
Ls="40 80 120" hs="0.5 1.0 1.5" \
COMMON_ARGS="J=1.0 dt=0.05 nsteps=200 max_weight=10 min_abs_coeff=1e-7 sites=mid" \
SBATCH_EXTRA="--cpus-per-task=16 --mem=64G --time=12:00:00" MAX_CONCURRENT=10 \
bash cluster/submit_sweep.sh sweep2
```

Output on Jed: `~/tfim-data/<sweep>/data/*.json`, logs in `~/tfim-data/<sweep>/logs/`,
and `params.txt` / `sweep_info.txt` recording what was submitted.
Check progress with `squeue -u $USER` and `tail ~/tfim-data/<sweep>/logs/*.out`.

Rough cost guide: the Pauli sum grows until `max_weight` / `min_abs_coeff` kick in; with
`max_weight=8` the per-step cost saturates and is roughly independent of `L`. Increase
`max_weight` and decrease `min_abs_coeff` until ⟨Z(t)⟩ stops changing (the notebook overlays
runs with identical `(L, h)` and different truncations).

## 4. Fetch and analyse locally

```bash
bash scripts/fetch_data.sh sweep1          # -> data/sweep1/data/*.json
```

Then open `notebooks/analysis.ipynb`. It needs Python with numpy, matplotlib and scipy
(your pyenv 3.10.17 has them) plus a notebook frontend:

```bash
pip install jupyter      # or run it in VS Code with ipykernel
```

The notebook lists all runs, plots ⟨Z_mid(t)⟩ vs `h` at fixed `L`, vs `L` at fixed `h`,
the number of Pauli terms vs time (truncation diagnostic), site-resolved heatmaps for
`sites=all` runs, and checks runs with `L ≤ 12` against exact diagonalization (both the
exact continuous-time result and the exactly-Trotterized one, to separate Trotter error
from truncation error).

## Output format

```json
{
  "params": {"L": 20, "h": 1.0, "J": 1.0, "dt": 0.05, "nsteps": 100, "max_weight": 8, "min_abs_coeff": 1e-6, ...},
  "meta":   {"nthreads": 8, "walltime_total_s": 12.3, "hostname": "...", "slurm_job_id": "...", ...},
  "times":  [0.0, 0.05, ...],
  "sites":  [10],
  "Z":      [[1.0, 0.995, ...]],      // Z[site_index][time_index]
  "nterms": [[1, 5, ...]]             // Pauli terms after each step
}
```
