#!/usr/bin/env julia

"""
Benchmark Models Script

LLMが発見した最良モデルを、標準的な後流モデル（Jensen, Bastankhah）と比較評価するスクリプト。
物理ペナルティを考慮した厳密な選定と、オフセット項を含む再最適化を行う。

使用方法:
    julia --project=. benchmark_models.jl [--exp-name experiment_name] [--gen generation]
"""

using CSV
using DataFrames
using Statistics
using BlackBoxOptim
using Plots
using JSON3
using Dates
using ArgParse

# Include necessary modules
include("../Phase5/Phase5.jl")
using .Phase5

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--exp-name"
            help = "Experiment name"
            arg_type = String
            default = "default"
        "--gen"
            help = "Generation number to benchmark (default: -1 for auto-detect global best)"
            arg_type = Int
            default = -1
    end
    return parse_args(s)
end



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
function bastankhah_wake(x, r, Ct, D, k_star)
    x_D = x / D
    r_D = r / D
    sigma_D = k_star * x_D + 0.2 * sqrt(0.5 * (1 - sqrt(1 - Ct)) / (1 - sqrt(1 - Ct))) # Approximation
    # Standard Bastankhah: sigma/D = k*x/D + epsilon
    # We will optimize k and epsilon directly
    return 0.0 # Placeholder, actual logic in optimization wrapper
end

# --- Optimization Wrapper ---

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
    res = bboptimize(loss; SearchRange = [(0.0, 2.0), (0.0, 0.5)], NumDimensions = 2, MaxTime = 10.0, TraceMode=:silent)
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
    res = bboptimize(loss; SearchRange = [(0.0, 1.0), (0.0, 0.2), (0.0, 0.5)], NumDimensions = 3, MaxTime = 10.0, TraceMode=:silent)
    return best_candidate(res), best_fitness(res)
end

# --- Main Benchmarking Function ---

function benchmark()
    args = parse_commandline()
    exp_name = args["exp-name"]
    gen_arg = args["gen"]
    
    # Determine generation and model
    best_valid_model = nothing
    best_valid_mse = Inf
    
    best_raw_model = nothing
    best_raw_mse = Inf
    
    if gen_arg == -1
        println("🔍 Auto-detecting global best model from history (Re-optimizing top candidates)...")
        
        # 1. Load Data for optimization
        println("   Loading data for candidate screening...")
        phase5_df_screen = Phase5.load_wake_data("data/result_I0p3000_C22p0000.csv")
        bench_df_screen = DataFrame()
        bench_df_screen.x_D = phase5_df_screen.x
        bench_df_screen.r_D = phase5_df_screen.r
        bench_df_screen.u_def = phase5_df_screen.deltaU
        bench_df_screen.nut = phase5_df_screen.nut
        bench_df_screen.k = phase5_df_screen.k
        bench_df_screen.omega = phase5_df_screen.omega

        # 2. Scan history for candidates (Top 5 from each generation)
        history_path = joinpath("results", exp_name, "history.jsonl")
        if !isfile(history_path)
            error("History file not found: $history_path")
        end
        
        candidates = []
        for line in eachline(history_path)
            data = JSON3.read(line)
            if haskey(data, :all_models)
                # For Gen 1, take ALL models (to ensure seeds are checked)
                # For other gens, take Top 5
                models = sort(data.all_models, by = m -> get(m, :score, Inf))
                
                if data.generation == 1
                    top_n = length(models)
                else
                    top_n = min(length(models), 5)
                end
                
                for i in 1:top_n
                    push!(candidates, (gen=data.generation, model=models[i]))
                end
            elseif haskey(data, :best_model)
                # Fallback if all_models not present
                push!(candidates, (gen=data.generation, model=data.best_model))
            end
        end
        
        println("   Found $(length(candidates)) candidates (Top 5 per gen). Optimizing...")
        
        # 3. Optimize each candidate
        for (i, cand) in enumerate(candidates)
            formula = cand.model.formula
            num_coeffs = length(cand.model.coefficients)
            expr = Phase5.Evaluator.parse_model_expression(formula)
            
            if expr !== nothing
                # Define optimization locally to avoid scope issues
                function optimize_candidate(df, expr, n_coeffs)
                    x_vec = df.x_D; r_vec = df.r_D; k_vec = df.k; omega_vec = df.omega; nut_vec = df.nut; target_vec = df.u_def
                    function loss(params)
                        return Phase5.Evaluator.mse_eval(expr, params, x_vec, r_vec, k_vec, omega_vec, nut_vec, target_vec)
                    end
                    range = [(-100.0, 100.0) for _ in 1:n_coeffs]
                    res = bboptimize(loss; SearchRange = range, NumDimensions = n_coeffs, MaxTime = 2.0, TraceMode=:silent) # Short time for screening
                    return best_candidate(res), best_fitness(res)
                end

                coeffs, mse = optimize_candidate(bench_df_screen, expr, num_coeffs)
                
                # Calculate Physical Penalty
                penalty = Phase5.Evaluator.physical_penalty(expr, coeffs, bench_df_screen.x_D, bench_df_screen.r_D, bench_df_screen.k, bench_df_screen.omega, bench_df_screen.nut, bench_df_screen.u_def)
                
                # Track Best Raw Model (MSE only)
                if mse < best_raw_mse
                    best_raw_mse = mse
                    best_raw_model = (gen=cand.gen, formula=formula, coeffs=coeffs, mse=mse, penalty=penalty, num_coeffs=num_coeffs, valid=(penalty < 1.0))
                    println("   ⚠️  New Best RAW Model: Gen $(cand.gen) | MSE: $mse | Penalty: $penalty")
                end

                # Track Best Valid Model (Penalty < Threshold)
                penalty_threshold = 1.0
                if penalty < penalty_threshold
                    if mse < best_valid_mse
                        best_valid_mse = mse
                        best_valid_model = (gen=cand.gen, formula=formula, coeffs=coeffs, mse=mse, penalty=penalty, num_coeffs=num_coeffs, valid=true)
                        println("   🌟 New Best VALID Model: Gen $(cand.gen) | MSE: $mse | Penalty: $penalty")
                    end
                end
            end
        end
        
        if best_valid_model !== nothing
            println("   🏆 True Global Best Found (VALID): Gen $(best_valid_model.gen) (MSE: $(best_valid_model.mse), Penalty: $(best_valid_model.penalty))")
            gen = best_valid_model.gen
        elseif best_raw_model !== nothing
            println("   ⚠️  No VALID model found. Falling back to Best RAW model.")
            println("   🏆 Best RAW Model: Gen $(best_raw_model.gen) (MSE: $(best_raw_model.mse), Penalty: $(best_raw_model.penalty))")
            gen = best_raw_model.gen
            best_valid_model = best_raw_model # Fallback
        else
            error("No candidates found.")
        end
    else
        gen = gen_arg
    end
    
    println("🚀 Starting Benchmark (Experiment: $exp_name, Gen: $gen)...")
    
    base_dir = joinpath("results", exp_name)
    plots_dir = joinpath(base_dir, "plots")
    mkpath(plots_dir)

    
    # 1. Load Data
    println("📂 Loading CFD Data (via Phase5)...")
    phase5_df = Phase5.load_wake_data("data/result_I0p3000_C22p0000.csv")
    
    # Convert to benchmark format
    bench_df = DataFrame()
    bench_df.x_D = phase5_df.x
    bench_df.r_D = phase5_df.r
    bench_df.u_def = phase5_df.deltaU
    bench_df.nut = phase5_df.nut
    bench_df.k = phase5_df.k
    bench_df.omega = phase5_df.omega # Added omega
    
    println("✅ Data Loaded: $(nrow(bench_df)) points")
    
    # 2. Optimize Standard Models
    
    # Check for calibration file
    data_basename = splitext(basename("data/result_I0p3000_C22p0000.csv"))[1]
    calibration_file = joinpath("params", "standard_models_$(data_basename).json")
    
    jensen_params = nothing
    jensen_mse = Inf
    bast_params = nothing
    bast_mse = Inf
    
    if isfile(calibration_file)
        println("🔹 Found calibration file: $calibration_file")
        calib_data = JSON3.read(read(calibration_file, String))
        
        jensen_params = calib_data.jensen.params
        jensen_mse = calib_data.jensen.mse
        println("   ✅ Loaded Jensen (MSE: $jensen_mse)")
        
        bast_params = calib_data.bastankhah.params
        bast_mse = calib_data.bastankhah.mse
        println("   ✅ Loaded Bastankhah (MSE: $bast_mse)")
    else
        println("⚙️  Optimizing Jensen Model...")
        jensen_params, jensen_mse = optimize_jensen(bench_df)
        println("   Jensen MSE: $jensen_mse")
        
        println("⚙️  Optimizing Bastankhah Model...")
        bast_params, bast_mse = optimize_bastankhah(bench_df)
        println("   Bastankhah MSE: $bast_mse")
    end
    
    # 3. Load and Optimize LLM Best Model
    feedback_file = joinpath(base_dir, "feedback_gen$gen.json")
    if !isfile(feedback_file)
        error("Feedback file not found: $feedback_file")
    end
    
    println("📂 Loading LLM Model from: $feedback_file")
    feedback_data = JSON3.read(read(feedback_file, String))
    
    # Get best model formula
    best_model_data = feedback_data.best_model
    llm_formula_str = get(best_model_data, :formula, get(best_model_data, :model, ""))
    if isempty(llm_formula_str)
        error("Could not find formula or model field in best_model data")
    end
    
    # Handle coefficients vs coeffs
    coeffs_data = get(best_model_data, :coefficients, get(best_model_data, :coeffs, []))
    num_coeffs = length(coeffs_data)
    
    println("   Formula: $llm_formula_str")
    println("   Num Coeffs: $num_coeffs")
    
    # Parse expression
    llm_expr = Phase5.Evaluator.parse_model_expression(llm_formula_str)
    if llm_expr === nothing
        error("Failed to parse LLM model expression")
    end

    println("⚙️  Optimizing LLM Best Model...")
    
    # Optimization function using Phase5.Evaluator
    function optimize_llm(df, expr, n_coeffs)
        # Pre-extract vectors for speed
        x_vec = df.x_D
        r_vec = df.r_D
        k_vec = df.k
        omega_vec = df.omega
        nut_vec = df.nut
        target_vec = df.u_def
        
        function loss(params)
            try
                # Use Phase5.Evaluator.mse_eval which handles vectorization
                return Phase5.Evaluator.mse_eval(expr, params, x_vec, r_vec, k_vec, omega_vec, nut_vec, target_vec)
            catch e
                if isa(e, DomainError)
                    return 1e9 # High penalty for invalid domain
                else
                    rethrow(e)
                end
            end
        end
        
        # Dynamic search range: -100.0 to 100.0 for all coeffs to allow offsets
        range = [(-100.0, 100.0) for _ in 1:n_coeffs]
        
        res = bboptimize(loss; SearchRange = range, NumDimensions = n_coeffs, MaxTime = 120.0, TraceMode=:silent)
        return best_candidate(res), best_fitness(res)
    end

    llm_coeffs, llm_mse = optimize_llm(bench_df, llm_expr, num_coeffs)
    llm_penalty = Phase5.Evaluator.physical_penalty(llm_expr, llm_coeffs, bench_df.x_D, bench_df.r_D, bench_df.k, bench_df.omega, bench_df.nut, bench_df.u_def)
    
    println("   LLM Model MSE (Re-optimized): $llm_mse")
    println("   Penalty: $llm_penalty")
    println("   Coeffs: $llm_coeffs")
    
    # 4. Generate Plots
    println("📊 Generating Velocity Profiles...")
    
    locs = [5.0, 10.0]
    
    for x_loc in locs
        tol = 0.1
        slice_df = filter(row -> abs(row.x_D - x_loc) < tol, bench_df)
        
        if nrow(slice_df) == 0
            continue
        end
        
        sort!(slice_df, :r_D)
        
        r_vals = slice_df.r_D
        u_cfd = slice_df.u_def
        
        # Jensen
        A_j, k_j = jensen_params
        Rw_j = 0.5 + k_j * x_loc
        u_jensen = [abs(r) <= Rw_j ? A_j * (0.5/Rw_j)^2 : 0.0 for r in r_vals]
        
        # Bastankhah
        A_b, k_b, eps_b = bast_params
        sigma_b = k_b * x_loc + eps_b
        u_bast = [(A_b / sigma_b^2) * exp(-0.5 * (r / sigma_b)^2) for r in r_vals]
        
        # LLM (Dynamic Eval)
        # Note: eval_model returns a vector, so we pass vectors
        u_llm = Phase5.Evaluator.eval_model(
            llm_expr, 
            llm_coeffs, 
            fill(x_loc, nrow(slice_df)), 
            slice_df.r_D, 
            slice_df.k, 
            slice_df.omega, 
            slice_df.nut
        )
        
        p = plot(r_vals, u_cfd, seriestype=:scatter, label="CFD (LES)", xlabel="r/D", ylabel="Δu/U", title="x/D = $x_loc", legend=:topright, size=(1200, 800), markercolor=:white, guidefontsize=14, tickfontsize=12, margin=15Plots.mm)
        plot!(p, r_vals, u_jensen, label="Jensen", linestyle=:dash, linewidth=2)
        plot!(p, r_vals, u_bast, label="Bastankhah", linestyle=:dashdot, linewidth=2)
        plot!(p, r_vals, u_llm, label="LLM (Gen $gen)", linewidth=3)
        
        savefig(p, joinpath(plots_dir, "benchmark_profiles_x$(Int(x_loc)).png"))
    end
    
    # 5. Save Summary
    open(joinpath(plots_dir, "benchmark_summary.txt"), "w") do io
        println(io, "Benchmark Results Summary")
        println(io, "=========================")
        println(io, "Experiment: $exp_name")
        println(io, "Generation: $gen")
        println(io, "Date: $(Dates.now())")
        println(io, "")
        
        println(io, "[Jensen Model]")
        println(io, "MSE: $jensen_mse")
        println(io, "")
        
        println(io, "[Bastankhah Model]")
        println(io, "MSE: $bast_mse")
        println(io, "")
        
        println(io, "[LLM Best Model]")
        println(io, "Formula: $llm_formula_str")
        println(io, "MSE: $llm_mse")
        println(io, "Penalty: $llm_penalty")
        println(io, "Coeffs: $llm_coeffs")
        println(io, "")
        
        println(io, "Improvement over Jensen:     $(round((jensen_mse - llm_mse)/jensen_mse * 100, digits=2))%")
        println(io, "Improvement over Bastankhah: $(round((bast_mse - llm_mse)/bast_mse * 100, digits=2))%")
        println(io, "")

        if best_raw_model !== nothing
            println(io, "[Reference: Best Raw MSE Model (No Penalty)]")
            println(io, "Gen: $(best_raw_model.gen)")
            println(io, "Formula: $(best_raw_model.formula)")
            println(io, "MSE: $(best_raw_model.mse)")
            println(io, "Penalty: $(best_raw_model.penalty)")
            println(io, "Coeffs: $(best_raw_model.coeffs)")
        end
    end
    
    println("✅ Benchmark Complete! Results saved to $plots_dir")
end

benchmark()
