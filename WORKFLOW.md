# From an empty folder to cluster numerics with Claude Code

This document records how this repo was built: a local folder tracked on GitHub,
a simulation codebase written with Claude Code, and jobs run on EPFL's Jed cluster
with the results analysed back on the laptop.
It is meant as a recipe you can repeat for a new project.

The flow has three places and one rule:

- **Laptop:** where you write code, talk to Claude, and analyse results.
- **GitHub:** the only way code reaches the cluster.
- **Jed:** where the heavy simulations run. Results come back by `rsync`, never through git.
- **Rule:** only code goes into git. Data, figures and local experiments stay out.

```
laptop ──git push──▶ GitHub ──git clone / pull──▶ Jed
  ▲                                                │
  └──────────────── rsync (results) ◀──────────────┘
```

---

## Step 1. Make a local folder and connect it to GitHub

1. Create an empty repository on GitHub, without a README.
   See [Creating a new repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository).
2. Create the local folder, turn it into a git repo and connect it to the GitHub one.
   See [Adding locally hosted code to GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github).
   In short:
   ```bash
   mkdir qic-cluster-test && cd qic-cluster-test
   git init -b main
   echo "# qic-cluster-test" > README.md
   git add README.md && git commit -m "first commit"
   git remote add origin https://github.com/<user>/qic-cluster-test.git
   git push -u origin main
   ```
3. The first push asks you to log in to GitHub. GitHub no longer accepts your account password here.
   The easiest options are the GitHub CLI's [`gh auth login`](https://cli.github.com/manual/gh_auth_login)
   or a [personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
   To avoid typing it every time, see [Caching your GitHub credentials](https://docs.github.com/en/get-started/getting-started-with-git/caching-your-github-credentials-in-git).

## Step 2. Set up the software environment

This project uses Julia with [PauliPropagation.jl](https://github.com/MSRudolph/PauliPropagation.jl).
Install Julia with [juliaup](https://github.com/JuliaLang/juliaup), then create a project environment in the folder:

```bash
julia --project=. -e 'using Pkg; Pkg.add("PauliPropagation")'
git add Project.toml Manifest.toml && git commit -m "add PP environment" && git push
```

`Project.toml` and `Manifest.toml` pin exact package versions, so the cluster installs the same ones.
See [Julia environments](https://pkgdocs.julialang.org/v1/environments/) for details.

## Step 3. Ask Claude Code to write the codebase

Open [Claude Code](https://code.claude.com/docs/en/overview) in the folder.
Start by telling it the context, then describe the physics and the workflow you want.
These are the prompts used for this repo:

> Before we start, we are working in a local folder where we want to save the code/results.
> I have set up a remote GitHub repo for version control of the code.

> I want to write cluster scripts for simulating transverse field Ising model in 1d, e.g. I want
> different field value, different system size.
>
> I want the cluster script to run dynamics for Z operator using EPFL Jed and save the data locally.
>
> Then I want to transfer relevant data to process them locally here using a notebook.

From this, Claude wrote:

| File | Where it runs | What it does |
|---|---|---|
| `src/tfim_dynamics.jl` | laptop and Jed | one simulation for one (L, h) point, saved as JSON |
| `cluster/*.sh`, `cluster/tfim_array.sbatch` | Jed | setup, and submitting a sweep as a Slurm job array |
| `scripts/fetch_data.sh` | laptop | copies results from Jed with `rsync` |
| `notebooks/analysis.ipynb` | laptop | plots, plus a check against exact diagonalization |

It also ran small simulations locally and checked them against exact results.
It's worth asking for that kind of check explicitly if Claude doesn't do it.

## Step 4. Stage only what the cluster needs

Claude also creates files for local testing, such as figures, test data and notebooks.
Those don't belong on the cluster. Ask for selective staging:

> Can you stage the relevant files only for the cluster? You seem to have produced
> figures/notebooks locally which we don't need to add for the cluster.

Then look at what is staged yourself before committing:

```bash
git status            # staged files are listed under "Changes to be committed"
git diff --staged     # the exact changes that will be committed
```

A `.gitignore` containing `data/` and `figures/` makes sure results never get committed by accident.
For more on staging, see [Recording changes to the repository](https://git-scm.com/book/en/v2/Git-Basics-Recording-Changes-to-the-Repository).

## Step 5. Commit, push, and get the cluster instructions

Once the staged files look right:

> Can you commit the current staged files? And how do I submit the jobs on the cluster?

> Can you push the code to remote?

> Can you write a md document for descriptions I should follow to submit the jobs on the cluster?
> Also add this to the remote.

The last prompt produced [CLUSTER_GUIDE.md](CLUSTER_GUIDE.md), the step-by-step guide for Jed.

Claude also dry-ran the submission locally with a fake `sbatch` and found a bug before anything
reached the cluster. Asking for a local dry run of the cluster scripts is a cheap way to catch mistakes.

## Step 6. Get the code onto Jed

1. Get Jed access and learn how to log in. See the [SCITAS documentation](https://scitas-doc.epfl.ch/)
   and [Connecting to the clusters](https://scitas-doc.epfl.ch/user-guide/using-clusters/connecting-to-the-clusters/).
2. Clone the repo on Jed.
   - **Public repo:** no GitHub login is needed:
     ```bash
     git clone https://github.com/<user>/qic-cluster-test.git
     ```
   - **Private repo, or you want to push from Jed:** add an SSH key on Jed to your GitHub account.
     See [Generating a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)
     and [Adding a new SSH key to your GitHub account](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account).
     Then clone with the `git@github.com:<user>/<repo>.git` address.

The prompt used here:

> I need to clone this repo on the cluster, how do I do the GitHub authentication, the easiest way?

## Step 7. Run the jobs

Follow [CLUSTER_GUIDE.md](CLUSTER_GUIDE.md). In short:

```bash
bash cluster/setup_jed.sh                 # once
bash cluster/submit_sweep.sh test0        # with a tiny sweep first, see the guide
bash cluster/submit_sweep.sh sweep1       # the real sweep
squeue -u $USER                           # watch it
```

For Slurm itself, see SCITAS's [Running jobs](https://scitas-doc.epfl.ch/user-guide/using-clusters/running-jobs/)
and [QOS and partitions](https://scitas-doc.epfl.ch/user-guide/using-clusters/slurm-qos-partitions/).

## Step 8. Bring results back and analyse

On the laptop:

```bash
bash scripts/fetch_data.sh sweep1          # copies Jed's results into data/sweep1/
```

Then open `notebooks/analysis.ipynb` and run all cells.

## Step 9. Change things and repeat

1. Ask Claude for the change, and ask it to test locally.
2. Check `git status` and `git diff --staged`, then commit and push.
3. On Jed, run `git pull`, but not while a sweep still has pending tasks.
4. Submit under a new sweep name. Each sweep records the git commit it ran from.

---

## Tips for working with Claude on this

- **Say where things run.** "This runs on Jed" or "this stays local" helps Claude decide what to commit.
- **Ask for checks, not just code.** A small exact-diagonalization comparison or a dry run catches most errors.
- **Review before committing.** Claude stages and commits when asked, but `git diff --staged` is your last look.
- **Keep data out of git.** Use `rsync` for results, and keep the `.gitignore` up to date.
