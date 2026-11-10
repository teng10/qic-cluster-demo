# From an empty folder to cluster numerics with Claude Code

This is how this repo was set up, written as a recipe you can repeat for a new project.
You write code with Claude Code on your laptop, track it on GitHub, run it on EPFL's Jed cluster,
and analyse the results back on your laptop.

```
laptop ──git push──▶ GitHub ──git pull──▶ Jed
  ▲                                         │
  └──────────── rsync (results) ◀───────────┘
```

Only code travels through GitHub. Results come back with `rsync`, and data and figures never go into git.

---

## 1. Create the repo

1. Create an empty repository on GitHub
   ([guide](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository)).
   GitHub then shows the commands that connect a local folder to it. Run them in your project folder.
   More detail: [Adding locally hosted code to GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github).
2. Your first `git push` asks you to log in, and your GitHub password won't work there.
   Use [`gh auth login`](https://cli.github.com/manual/gh_auth_login)
   or a [personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

## 2. Set up Julia

Install Julia with [juliaup](https://github.com/JuliaLang/juliaup), then create the project environment in the folder:

```bash
julia --project=. -e 'using Pkg; Pkg.add("PauliPropagation")'
```

This writes `Project.toml` and `Manifest.toml`, which pin the package versions so Jed installs the same ones.
They get committed together with the code in step 4. You can also ask Claude to do this step.

## 3. Ask Claude for the code

Open [Claude Code](https://code.claude.com/docs/en/overview) in the folder.
Give the context first, then the physics and the workflow. These are the prompts used here:

> Before we start, we are working in a local folder where we want to save the code/results.
> I have set up a remote GitHub repo for version control of the code.

> I want to write cluster scripts for simulating transverse field Ising model in 1d, e.g. I want
> different field value, different system size.
>
> I want the cluster script to run dynamics for Z operator using EPFL Jed and save the data locally.
>
> Then I want to transfer relevant data to process them locally here using a notebook.

Saying where each piece runs matters, because it decides what gets committed later. Claude produced:

| Files | Runs on | Committed? |
|---|---|---|
| `src/` simulation, `Project.toml`, `Manifest.toml` | laptop and Jed | yes |
| `cluster/` setup and Slurm job-array scripts | Jed | yes |
| `scripts/fetch_data.sh`, `notebooks/` | laptop | no, kept local |
| `data/`, `figures/` from local test runs | laptop | no, ignored by git |

Ask Claude to test what it writes, for example small runs compared against exact diagonalization.

## 4. Stage only what the cluster needs

Claude also creates files for local testing. Ask it to stage only the cluster files:

> Can you stage the relevant files only for the cluster? You seem to have produced
> figures/notebooks locally which we don't need to add for the cluster.

Then check for yourself what will be committed:

```bash
git status            # files under "Changes to be committed" go in
git diff --staged     # the exact changes
```

For the basics of staging, see [Recording changes to the repository](https://git-scm.com/book/en/v2/Git-Basics-Recording-Changes-to-the-Repository).

## 5. Commit, push, and get the cluster instructions

> Can you commit the current staged files? And how do I submit the jobs on the cluster?

> Can you push the code to remote?

> Can you write a md document for descriptions I should follow to submit the jobs on the cluster?
> Also add this to the remote.

The last prompt produced [CLUSTER_GUIDE.md](CLUSTER_GUIDE.md), the step-by-step guide for Jed.

Before using cluster scripts for real, ask Claude to dry-run them locally.
Here a dry run with a fake `sbatch` caught a bug before anything reached Jed.

## 6. Get the code onto Jed

> I need to clone this repo on the cluster, how do I do the GitHub authentication, the easiest way?

1. Get Jed access and log in. See the [SCITAS documentation](https://scitas-doc.epfl.ch/)
   and [Connecting to the clusters](https://scitas-doc.epfl.ch/user-guide/using-clusters/connecting-to-the-clusters/).
2. On your laptop, add a shortcut so that `ssh jed` logs you in.
   The script that fetches results in step 7 uses this shortcut, so it won't work without it.
   Add these lines to the file `~/.ssh/config`, creating the file if it doesn't exist:
   ```
   Host jed
       HostName jed.hpc.epfl.ch
       User <username>
   ```
   Replace `<username>` with your Jed username, which is your EPFL GASPAR username.
   If you're not sure, log in to Jed and run `echo $USER`.
   Then check the shortcut from your laptop. It should print the name of a Jed login node:
   ```bash
   ssh jed hostname
   ```
3. Clone the repo on Jed.
   - **Public repo:** no GitHub login is needed.
     ```bash
     git clone https://github.com/teng10/qic-cluster-test.git
     ```
   - **Private repo, or pushing from Jed:** add an SSH key from Jed to your GitHub account
     ([generate a key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent),
     [add it to GitHub](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)).
     Then clone with the `git@github.com:teng10/qic-cluster-test.git` address.

## 7. Run, fetch, analyse

1. On Jed, follow [CLUSTER_GUIDE.md](CLUSTER_GUIDE.md): one-time setup, a tiny test sweep, then the real sweep.
   For Slurm basics, see SCITAS's [Running jobs](https://scitas-doc.epfl.ch/user-guide/using-clusters/running-jobs/).
2. On your laptop, copy the results back:
   ```bash
   bash scripts/fetch_data.sh sweep1
   ```
   The script prints the login it uses, such as `<username>@jed.hpc.epfl.ch`.
   If that login is wrong or fails, the script says what to fix.
3. Open `notebooks/analysis.ipynb` and run all cells.

## 8. Change and repeat

1. Ask Claude for the change, and for a local test of it.
2. Check `git status` and `git diff --staged`, then commit and push.
3. On Jed, run `git pull`, but not while a sweep still has pending tasks.
   If `Project.toml` changed, also rerun `bash cluster/setup_jed.sh`.
4. Submit under a new sweep name.
