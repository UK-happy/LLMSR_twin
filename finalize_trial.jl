#!/usr/bin/env julia

"""
Finalize Trial Script
Automates the standard post-processing and analysis steps for a completed trial.
"""

using ArgParse
using Printf
using Dates

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--exp-name"
            help = "Experiment name (e.g., trial_10)"
            required = true
        "--gen"
            help = "Target generation for benchmarking (default: auto-detect max)"
            arg_type = Int
            default = -1
        "--api-eval"
            help = "Run API-based Reason evaluation (costs API quota)"
            action = :store_true
    end
    return parse_args(s)
end

function get_max_generation(exp_name::String)
    results_dir = joinpath("results", exp_name)
    if !isdir(results_dir)
        error("Experiment directory not found: $results_dir")
    end
    
    files = readdir(results_dir)
    gen_nums = Int[]
    for f in files
        m = match(r"models_gen(\d+)\.json", f)
        if m !== nothing
            push!(gen_nums, parse(Int, m.captures[1]))
        end
    end
    
    if isempty(gen_nums)
        error("No generation files found in $results_dir")
    end
    
    return maximum(gen_nums)
end

function run_step(script_name::String, args::Vector{String})
    cmd = `julia --project=. $script_name $args`
    println("\n" * "="^60)
    println("🚀 Running: $script_name $(join(args, " "))")
    println("="^60)
    
    try
        run(cmd)
        println("✅ $script_name completed successfully.")
    catch e
        println("⚠️  $script_name failed: $e")
    end
end

function main()
    args = parse_commandline()
    exp_name = args["exp-name"]
    gen = args["gen"]
    
    if gen < 0
        gen = get_max_generation(exp_name)
        println("ℹ️  Auto-detected max generation: $gen")
    end
    
    println("\n🏁 Finalizing Trial: $exp_name (Gen $gen)")
    println("Started at: $(now())")
    
    # 0. Baseline Calibration (Skipped if exists)
    run_step("src/analysis/calibrate_baselines.jl", String[])

    # 1. Basic Visualization (Score/MSE Trends)
    run_step("src/analysis/visualize_evolution.jl", ["--exp-name", exp_name])
    
    # 2. Physics Validity Analysis
    run_step("src/analysis/analyze_physics_validity.jl", ["--exp-name", exp_name])
    
    # 3. Lineage Tracing
    run_step("src/analysis/trace_evolution_lineage.jl", ["--exp-name", exp_name])
    
    # 4. Reason Correlation
    run_step("src/analysis/analyze_reason_correlation.jl", ["--exp-name", exp_name])
    
    # 5. Benchmarking (Best Model)
    run_step("src/analysis/benchmark_models.jl", ["--exp-name", exp_name, "--gen", string(gen)])
    
    # 6. API Evaluation (Optional)
    if args["api-eval"]
        println("\n🤖 Running API Evaluation (Step 6)...")
        # Assuming gemini-1.5-pro-latest or similar default
        run_step("src/analysis/evaluate_reason_api.jl", ["--exp-name", exp_name, "--gen", string(gen), "--model", "gemini-2.5-pro"])
        
        # Compare scores if API eval was run
        run_step("src/analysis/compare_reason_scores.jl", ["--exp-name", exp_name])
    end
    
    # 7. Report Preparation
    run_step("src/analysis/prepare_report.jl", ["--exp-name", exp_name])
    
    println("\n" * "="^60)
    println("🎉 Trial Finalization Complete!")
    println("📂 Check results in: results/$exp_name/")
    println("="^60)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
