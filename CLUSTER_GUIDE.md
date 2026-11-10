# Running TFIM sweeps on Jed: step by step

This is the checklist for running a sweep of 1D transverse-field Ising simulations
on EPFL's Jed cluster and getting the results back to your laptop.
Each array task computes ⟨Z_i(t)⟩ for one (L, h) point and writes one JSON file.

Commands marked **[Mac]** run on your laptop in this repo.
Commands marked **[Jed]** run on the Jed login node in `~/qic-cluster-test`.

---

## 0. One-time setup

### 0.1 SSH alias [Mac]

Add this to `~/.ssh/config`, using your GASPAR username:

```
Host jed
    HostName jed.hpc.epfl.ch
    User <gaspar-username>
```

Check that it works:

```bash
ssh jed hostname
```

### 0.2 Clone and install [Jed]

```bash
ssh jed
git clone https://github.com/teng10/qic-cluster-test.git
cd qic-cluster-test
bash cluster/setup_jed.sh
```

`setup_jed.sh` looks for Julia in this order:

1. a `julia` already on your PATH,
2. `module load julia`,
3. an install of Julia 1.10 through juliaup into `~/.juliaup`.

It then installs and precompiles the packages from `Manifest.toml`.
The final line should say `PauliPropagation 0.9.2 OK`.
To force a specific binary, set `JULIA_BIN=/path/to/julia` first.

### 0.3 Slurm account (only if needed) [Jed]

If `sbatch` complains about a missing or invalid account, find yours and export it.
Adding the export line to `~/.bashrc` makes it permanent.

```bash
sacctmgr show assoc user=$USER format=account,qos%40
export SBATCH_ACCOUNT=<lab-account>
```

---

## 1. Run a tiny test sweep first [Jed]

This checks the whole pipeline in a minute or two before you spend real compute time.

```bash
cd ~/qic-cluster-test
Ls="20" hs="1.0" \
COMMON_ARGS="J=1.0 dt=0.05 nsteps=20 max_weight=6 min_abs_coeff=1e-6 sites=mid" \
bash cluster/submit_sweep.sh test0
```

Then check the output:

```bash
squeue -u $USER                      # wait until the job is gone
cat ~/tfim-data/test0/logs/*.out     # should end with "done in ...s, wrote ..."
ls ~/tfim-data/test0/data/           # one .json file
```

---

## 2. Submit the real sweep [Jed]

### 2.1 Choose parameters

`submit_sweep.sh` takes its settings from environment variables.
Anything you leave out uses the default.

| Variable | Default | Meaning |
|---|---|---|
| `Ls` | `"20 40 80"` | system sizes, space-separated |
| `hs` | `"0.25 0.5 1.0 1.5 2.0"` | transverse fields, space-separated |
| `COMMON_ARGS` | `"J=1.0 dt=0.05 nsteps=100 max_weight=8 min_abs_coeff=1e-6 sites=mid"` | arguments shared by every task |
| `SBATCH_EXTRA` | empty | extra `sbatch` flags such as cores, memory or time limit |
| `MAX_CONCURRENT` | `20` | at most this many array tasks running at once |
| `TFIM_DATA_ROOT` | `~/tfim-data` | where sweep folders are created |

The sweep runs every combination of `Ls` and `hs`, one array task each.

The simulation arguments you can put in `COMMON_ARGS` are:

| Argument | Meaning |
|---|---|
| `J`, `h`, `L` | coupling, field and chain length. `h` and `L` usually come from the sweep lists. |
| `dt`, `nsteps` | Trotter step and number of steps. The final time is `dt × nsteps`. |
| `max_weight` | drop Pauli strings with more than this many non-identity sites. Omit it for no cutoff. |
| `min_abs_coeff` | drop Pauli strings whose coefficient is below this. |
| `sites` | `mid`, `all`, `half`, or a list such as `3,7,12`. Each site is a separate propagation. |
| `periodic` | `true` for a ring. The default is an open chain. |
| `tag` | suffix added to the output file name. |

### 2.2 Choose resources

Each task gets 8 cores, 16 GB and 2 hours by default, under the `serial` QOS.
On Jed that QOS is low priority, allows one node per job and runs up to 7 days.

Increase resources for large L, long times or loose truncation:

```bash
SBATCH_EXTRA="--cpus-per-task=16 --mem=64G --time=12:00:00"
```

A task writes its JSON only at the very end.
A task killed by the time limit or the memory limit leaves no data, so size the limits generously.
The `nterms` printed in the log every 10 steps shows how fast the Pauli sum is growing.

### 2.3 Submit

Every sweep needs a new name. The script refuses to reuse an existing one.

```bash
cd ~/qic-cluster-test
git pull                                  # pick up any code changes
Ls="20 40 80" hs="0.25 0.5 1.0 1.5 2.0" \
COMMON_ARGS="J=1.0 dt=0.05 nsteps=100 max_weight=8 min_abs_coeff=1e-6 sites=mid" \
bash cluster/submit_sweep.sh sweep1
```

The script prints the job ID and creates:

```
~/tfim-data/sweep1/
├── params.txt        # one "L=.. h=.." line per array task
├── sweep_info.txt    # exactly what was submitted, plus the git commit
├── data/             # results, one JSON per task
└── logs/             # tfim_<jobid>_<task>.out
```

### 2.4 Check truncation convergence

Results are only trustworthy if they don't change when the truncation is tightened.
Submit the same `Ls` and `hs` a second time with a tighter cutoff under a new sweep name:

```bash
Ls="20 40 80" hs="0.25 0.5 1.0 1.5 2.0" \
COMMON_ARGS="J=1.0 dt=0.05 nsteps=100 max_weight=10 min_abs_coeff=1e-7 sites=mid" \
SBATCH_EXTRA="--mem=32G --time=06:00:00" \
bash cluster/submit_sweep.sh sweep1_tight
```

The notebook overlays runs with the same (L, h) and different truncations.

---

## 3. Monitor [Jed]

```bash
squeue -u $USER                                   # pending (PD) and running (R) tasks
tail -f ~/tfim-data/sweep1/logs/*.out             # live progress
sacct -j <jobid> --format=JobID,State,Elapsed,MaxRSS,ReqMem
scancel <jobid>                                   # cancel the whole array
scancel <jobid>_7                                 # cancel one task
```

Logs of tasks that did not finish:

```bash
grep -L "^done in" ~/tfim-data/sweep1/logs/*.out
```

In `sacct`, `TIMEOUT` means raise `--time` and `OUT_OF_MEMORY` means raise `--mem`.
Tightening the truncation also makes tasks slower and larger.

### Resubmit only the failed tasks

The task number is the line number in `params.txt`.
This reruns tasks 3 and 7 into the same sweep folder with the original settings:

```bash
cd ~/qic-cluster-test
export SWEEP_DIR=~/tfim-data/sweep1
export COMMON_ARGS="$(sed -n 's/^COMMON_ARGS: //p' $SWEEP_DIR/sweep_info.txt)"
sbatch --array=3,7 --mem=64G --time=12:00:00 \
       --output="$SWEEP_DIR/logs/%x_%A_%a.out" --export=ALL \
       cluster/tfim_array.sbatch
```

---

## 4. Fetch the results [Mac]

```bash
bash scripts/fetch_data.sh sweep1                # -> data/sweep1/
bash scripts/fetch_data.sh                       # every sweep
WITH_LOGS=1 bash scripts/fetch_data.sh sweep1    # also copy the Slurm logs
```

The script only copies `.json` and `.txt` files and is safe to rerun while jobs are still going.
`data/` is gitignored, so results never end up in the repo.

Then open `notebooks/analysis.ipynb` and run all cells.

---

## 5. Changing the code

1. Edit and test locally [Mac]:
   ```bash
   julia -t auto --project=. src/tfim_dynamics.jl L=12 h=1.0 nsteps=40 out=data/local/data
   ```
2. Commit and push [Mac].
3. `git pull` in `~/qic-cluster-test` [Jed]. If `Project.toml` changed, rerun `bash cluster/setup_jed.sh`.
4. Submit under a new sweep name. Each sweep's `sweep_info.txt` records the commit it ran from.

Slurm copies the `.sbatch` file at submit time, but each task reads `src/tfim_dynamics.jl` and
`cluster/julia_env.sh` from the repo when it starts.
So don't `git pull` while a sweep still has pending tasks, or its later tasks will run the new code.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `julia still not found` in a log | Run `bash cluster/setup_jed.sh` on the login node, or set `JULIA_BIN`. |
| `Invalid account or account/partition combination` | Set `SBATCH_ACCOUNT` as in step 0.3. |
| `Invalid qos specification` | Delete the `#SBATCH --qos=serial` line in `cluster/tfim_array.sbatch`. |
| Tasks wait a long time in `PD` | The `serial` QOS is low priority. Lower `--time` and `--cpus-per-task`, or switch QOS. |
| `Sweep 'x' already exists` | Pick a new name, or remove `~/tfim-data/x` if you really want to redo it. |
| Precompiling at the start of a log | Expected on the first tasks that land on a new CPU type. Later tasks reuse the cache. |
| `fetch_data.sh` asks for a password | Set up an SSH key for Jed, or type your GASPAR password when prompted. |
