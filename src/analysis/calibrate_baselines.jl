#!/usr/bin/env julia

"""
Baseline Calibration Script

Standardizes the parameters for Jensen and Bastankhah models by performing
a rigorous, high-budget optimization on the target dataset.
The results are saved to `params/standard_models.json` and used by
other tools (inspect_model.jl, benchmark_models.jl) to ensure consistency.

Usage:
    julia --project=. calibrate_baselines.jl
"""

using CSV
using DataFrames
using Statistics
using BlackBoxOptim
using JSON3
using Dates
using Random
using SHA

# Include necessary modules
include("../Phase5/Phase5.jl")
using .Phase5

# --- Configuration ---
# --- Configuration ---
const DATA_PATH = "data/result_I0p3000_C22p0000.csv"
const OUTPUT_DIR = "params"
# Generate output filename based on data filename
const DATA_BASENAME = splitext(basename(DATA_PATH))[1]
const OUTPUT_FILE = joinpath(OUTPUT_DIR, "standard_models_$(DATA_BASENAME).json")
const OPT_TIME = 60.0  # Seconds per model (High budget)
const SEED = 42        # Fixed seed for reproducibility

# --- Model Definitions ---

# 1. Jensen Model (Top-hat)
function jensen_wake(x, r, Ct, D, k)
    D0 = D * sqrt((1 + sqrt(1 - Ct)) / (2 * sqrt(1 - Ct)))
    Dw = D + 2 * k * x
    if r <= Dw / 2
        return (1 - sqrt(1 - Ct)) * (D / Dw)^2
    else
        return 0.0
    end
end

# 2. Bastankhah-Porté-Agel Model (Gaussian)
# Note: We optimize A, k, epsilon directly as in benchmark_models.jl
# sigma = k*x + epsilon
# pred = (A / sigma^2) * exp(-0.5 * (r / sigma)^2)

# --- Optimization Functions ---

function optimize_jensen(df)
    function loss(params)
        A, k = params
        mse = 0.0
        for row in eachrow(df)
            x = row.x_D
            r = row.r_D
            target = row.u_def
            Rw = 0.5 + k * x
            pred = 0.0
            if abs(r) <= Rw
                pred = A * (0.5 / Rw)^2
            end
            mse += (pred - target)^2
        end
        return mse / nrow(df)
    end
    
    # Search Range: A in [0, 2], k in [0, 0.5]
    res = bboptimize(loss; 
        SearchRange = [(0.0, 2.0), (0.0, 0.5)], 
        NumDimensions = 2, 
        MaxTime = OPT_TIME, 
        TraceMode = :verbose,
        RandomizeRngSeed = false
    )
    return best_candidate(res), best_fitness(res)
end

function optimize_bastankhah(df)
    function loss(params)
        A, k, epsilon = params
        mse = 0.0
        for row in eachrow(df)
            x = row.x_D
            r = row.r_D
            target = row.u_def
            sigma = k * x + epsilon
            pred = (A / sigma^2) * exp(-0.5 * (r / sigma)^2)
            mse += (pred - target)^2
        end
        return mse / nrow(df)
    end
    
    # Search Range: A in [0, 1], k in [0, 0.2], epsilon in [0, 0.5]
    res = bboptimize(loss; 
        SearchRange = [(0.0, 1.0), (0.0, 0.2), (0.0, 0.5)], 
        NumDimensions = 3, 
        MaxTime = OPT_TIME, 
        TraceMode = :verbose,
        RandomizeRngSeed = false
    )
    return best_candidate(res), best_fitness(res)
end

function calculate_file_hash(filepath)
    return open(filepath) do io
        bytes2hex(sha256(io))
    end
end

function main()
    println("="^60)
    println("🔧 Baseline Calibration Tool")
    println("="^60)
    println("Target Data: $DATA_PATH")
    println("Opt Time:    $(OPT_TIME)s per model")
    println("Random Seed: $SEED")
    println("-"^60)

    # Set seed
    Random.seed!(SEED)

    # 0. Check if output exists
    if isfile(OUTPUT_FILE)
        println("ℹ️  Calibration file already exists: $OUTPUT_FILE")
        println("   Skipping calibration. Delete this file to re-run.")
        return
    end

    # 1. Load Data
    println("📂 Loading Data...")
    if !isfile(DATA_PATH)
        error("Data file not found: $DATA_PATH")
    end
    
    # Calculate hash for versioning
    data_hash = calculate_file_hash(DATA_PATH)
    println("   Data Hash: $(data_hash[1:8])...")

    # Use Phase5 loader for consistency
    phase5_df = Phase5.load_wake_data(DATA_PATH)
    
    # Convert to benchmark format
    bench_df = DataFrame()
    bench_df.x_D = phase5_df.x
    bench_df.r_D = phase5_df.r
    bench_df.u_def = phase5_df.deltaU
    bench_df.nut = phase5_df.nut
    
    # Filter for valid range (x > 0.1) as in benchmark/inspect
    # Note: Phase5.load_wake_data already filters 2 <= x <= 15, so x > 0.1 is redundant but safe
    opt_df = filter(row -> row.x_D > 0.1, bench_df)
    println("✅ Data Loaded: $(nrow(opt_df)) points used for optimization")

    # 2. Optimize Jensen
    println("\n⚙️  Calibrating Jensen Model...")
    jensen_params, jensen_mse = optimize_jensen(opt_df)
    println("   ✅ Converged MSE: $jensen_mse")
    println("   ✅ Parameters:    $jensen_params (A, k)")

    # 3. Optimize Bastankhah
    println("\n⚙️  Calibrating Bastankhah Model...")
    bast_params, bast_mse = optimize_bastankhah(opt_df)
    println("   ✅ Converged MSE: $bast_mse")
    println("   ✅ Parameters:    $bast_params (A, k, epsilon)")

    # 4. Save Results
    println("\n💾 Saving Results...")
    mkpath(OUTPUT_DIR)
    
    output_data = Dict(
        "meta" => Dict(
            "timestamp" => string(now()),
            "data_path" => DATA_PATH,
            "data_hash" => data_hash,
            "optimization_time" => OPT_TIME,
            "seed" => SEED
        ),
        "jensen" => Dict(
            "mse" => jensen_mse,
            "params" => jensen_params,
            "param_names" => ["A", "k"]
        ),
        "bastankhah" => Dict(
            "mse" => bast_mse,
            "params" => bast_params,
            "param_names" => ["A", "k", "epsilon"]
        )
    )

    open(OUTPUT_FILE, "w") do io
        JSON3.pretty(io, output_data)
    end
    
    println("✅ Calibration saved to: $OUTPUT_FILE")
    println("="^60)
end

main()
