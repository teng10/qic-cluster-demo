#!/usr/bin/env julia
#
# Heisenberg-picture dynamics of Z_i for the 1D transverse-field Ising model
# using Pauli propagation (PauliPropagation.jl).
#
#     H = J Σ_i Z_i Z_{i+1}  +  h Σ_i X_i          (open chain unless periodic=true)
#     |ψ(0)⟩ = |0…0⟩                               (all spins up in Z)
#
# Time evolution is a second-order Trotter step of size dt,
#     V = e^{-i (h dt/2) ΣX} · e^{-i J dt ΣZZ} · e^{-i (h dt/2) ΣX} ≈ e^{-i H dt},
# and ⟨Z_i(t_k)⟩ with t_k = k·dt is obtained by back-propagating Z_i through k layers.
# Because every layer is identical, Z_i(t_{k+1}) = V† Z_i(t_k) V, so the k-th data point
# is one extra layer of propagation on the already-evolved Pauli sum.
#
# Usage (all arguments are key=value, every one has a default):
#   julia -t auto --project=. src/tfim_dynamics.jl L=20 h=1.0 J=1.0 dt=0.05 nsteps=100 \
#       max_weight=8 min_abs_coeff=1e-6 sites=mid periodic=false out=data/local
#
#   sites = mid            -> middle site only
#           all            -> every site 1..L (L separate propagations)
#           half           -> sites 1..ceil(L/2) (rest follows by reflection symmetry)
#           3,7,12         -> explicit comma-separated list
#
# Output: one JSON file per run in `out`, containing parameters, times,
# ⟨Z_i(t)⟩ for each requested site, and the number of Pauli terms vs time.

using PauliPropagation
using JSON
using Dates
using Printf

# --------------------------------------------------------------------------- args
function parseargs(args)
    opts = Dict{String,String}()
    for a in args
        m = match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", a)
        m === nothing && error("Arguments must be key=value, got: '$a'")
        opts[m.captures[1]] = m.captures[2]
    end
    return opts
end

getopt(opts, key, default::String)  = get(opts, key, default)
getopt(opts, key, default::Bool)    = haskey(opts, key) ? parse(Bool, opts[key]) : default
getopt(opts, key, default::Int)     = haskey(opts, key) ? parse(Int, opts[key]) : default
getopt(opts, key, default::Float64) = haskey(opts, key) ? parse(Float64, opts[key]) : default

function parsesites(spec::AbstractString, L::Int)
    spec == "mid"  && return [cld(L, 2)]
    spec == "all"  && return collect(1:L)
    spec == "half" && return collect(1:cld(L, 2))
    sites = [parse(Int, s) for s in split(spec, ",") if !isempty(strip(s))]
    all(1 .<= sites .<= L) || error("sites out of range 1..$L: $sites")
    return sites
end

# --------------------------------------------------------------------------- main
function main(args)
    opts = parseargs(args)

    L             = getopt(opts, "L", 20)
    h             = getopt(opts, "h", 1.0)
    J             = getopt(opts, "J", 1.0)
    dt            = getopt(opts, "dt", 0.05)
    nsteps        = getopt(opts, "nsteps", 100)
    max_weight    = getopt(opts, "max_weight", Inf)      # Inf = no weight truncation
    min_abs_coeff = getopt(opts, "min_abs_coeff", 1e-6)
    periodic      = getopt(opts, "periodic", false)
    sites_spec    = getopt(opts, "sites", "mid")
    outdir        = getopt(opts, "out", "data/local")
    tag           = getopt(opts, "tag", "")

    sites = parsesites(sites_spec, L)
    mkpath(outdir)

    wstr = isfinite(max_weight) ? string(Int(max_weight)) : "inf"
    cstr = @sprintf("%.0e", min_abs_coeff)
    fname = "tfim_L$(L)_h$(h)_J$(J)_dt$(dt)_n$(nsteps)_W$(wstr)_c$(cstr)" *
            (periodic ? "_pbc" : "") * (isempty(tag) ? "" : "_$tag") * ".json"
    outfile = joinpath(outdir, fname)

    println("TFIM Z-dynamics via Pauli propagation")
    println("  L=$L h=$h J=$J dt=$dt nsteps=$nsteps (t_max=$(nsteps*dt))")
    println("  max_weight=$max_weight min_abs_coeff=$min_abs_coeff periodic=$periodic")
    println("  sites=$sites  threads=$(Threads.nthreads())")
    println("  -> $outfile")
    flush(stdout)

    # one second-order Trotter layer; the parameter vector follows the gate order
    topo  = bricklayertopology(L; periodic=periodic)
    layer = Gate[]
    rxlayer!(layer, L)                     # e^{-i (h dt/2) X}   : θ = h dt
    rzzlayer!(layer, topo)                 # e^{-i  J dt  ZZ}    : θ = 2 J dt
    rxlayer!(layer, L)
    thetas = vcat(fill(h * dt, L), fill(2J * dt, length(topo)), fill(h * dt, L))
    @assert length(thetas) == countparameters(layer)

    times  = collect(0:nsteps) .* dt
    Zvals  = zeros(Float64, length(sites), nsteps + 1)
    nterms = zeros(Int, length(sites), nsteps + 1)
    walltimes = zeros(Float64, length(sites))

    t_start = time()
    for (si, site) in enumerate(sites)
        t0 = time()
        psum = PauliSum(PauliString(L, :Z, site))
        Zvals[si, 1]  = overlapwithzero(psum)
        nterms[si, 1] = length(psum)
        for k in 1:nsteps
            psum = propagate!(layer, psum, thetas; max_weight=max_weight, min_abs_coeff=min_abs_coeff)
            Zvals[si, k+1]  = overlapwithzero(psum)
            nterms[si, k+1] = length(psum)
            if k % 10 == 0 || k == nsteps
                @printf("  site %3d  step %4d/%d  t=%.3f  <Z>=% .6f  nterms=%d  elapsed=%.1fs\n",
                        site, k, nsteps, times[k+1], Zvals[si, k+1], nterms[si, k+1], time() - t0)
                flush(stdout)
            end
        end
        walltimes[si] = time() - t0
    end
    total_wall = time() - t_start

    result = Dict(
        "params" => Dict(
            "L" => L, "h" => h, "J" => J, "dt" => dt, "nsteps" => nsteps,
            "max_weight" => isfinite(max_weight) ? Int(max_weight) : nothing,
            "min_abs_coeff" => min_abs_coeff, "periodic" => periodic,
            "sites_spec" => sites_spec, "trotter_order" => 2,
            "initial_state" => "all zeros", "observable" => "Z_i",
        ),
        "meta" => Dict(
            "julia" => string(VERSION),
            "pauli_propagation" => string(pkgversion(PauliPropagation)),
            "nthreads" => Threads.nthreads(),
            "hostname" => gethostname(),
            "slurm_job_id" => get(ENV, "SLURM_JOB_ID", nothing),
            "slurm_array_task_id" => get(ENV, "SLURM_ARRAY_TASK_ID", nothing),
            "date" => string(now()),
            "walltime_total_s" => total_wall,
            "walltime_per_site_s" => walltimes,
        ),
        "times"  => times,
        "sites"  => sites,
        "Z"      => [Zvals[si, :] for si in eachindex(sites)],      # Z[site_index][time_index]
        "nterms" => [nterms[si, :] for si in eachindex(sites)],
    )

    open(outfile, "w") do io
        JSON.print(io, result, 2)
    end
    @printf("done in %.1fs, wrote %s\n", total_wall, outfile)
    return outfile
end

main(ARGS)
