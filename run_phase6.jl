#!/usr/bin/env julia

"""
Phase 6 Execution Script
Run the LLM-driven evolution with Physical Penalties and Reason Scoring.
"""

using ArgParse
using Printf
using Statistics
using JSON3
using Dates

# Load Project Modules
push!(LOAD_PATH, joinpath(@__DIR__, "src"))
include("src/Phase6/Phase6.jl")
include("src/Phase6/EvolutionUtils.jl") # Phase 6 specific utils

using .Phase6
using .EvolutionUtils

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--generate-initial"
            help = "Generate initial population feedback"
            action = :store_true
        "--size"
            help = "Population size"
            arg_type = Int
            default = 20
        "--evaluate"
            help = "Evaluate generation N"
            arg_type = Int
            default = -1
        "--input"
            help = "Input JSON file"
            arg_type = String
            default = ""
        "--csv-path"
            help = "Path to CFD data"
            arg_type = String
            default = "data/result_I0p3000_C22p0000.csv"
        "--exp-name"
            help = "Experiment name"
            arg_type = String
            default = "phase6_trial"
        "--seeds-file"
            help = "Path to seeds JSON"
            arg_type = String
            default = "seeds.json"
    end
    return parse_args(s)
end

function generate_initial(size::Int, exp_name::String, seeds_file::String)
    println("\n" * "="^70)
    println("🌱 Phase 6: Generating Initial Population (Gen 0)")
    println("="^70)
    
    base_dir = joinpath("results", exp_name)
    mkpath(base_dir)
    mkpath(joinpath(base_dir, "plots"))
    
    seeds = EvolutionUtils.load_seeds(seeds_file)
    if !isempty(seeds)
        println("   ✓ Loaded $(length(seeds)) seeds.")
    end
    
    feedback_path = joinpath(base_dir, "feedback_gen0.json")
    EvolutionUtils.generate_initial_feedback(size, feedback_path; seeds=seeds)
    
    println("\n✅ Initial feedback generated: $feedback_path")
    println("📋 Next: Use templates/phase6_prompt.md with this feedback.")
end

function evaluate_generation(gen::Int, input_file::String, csv_path::String, exp_name::String)
    println("\n" * "="^70)
    println("🔬 Phase 6: Evaluating Generation $gen")
    println("="^70)
    
    models = EvolutionUtils.load_models(input_file)
    if isempty(models)
        error("No models found in $input_file")
    end
    
    println("\n⚙️  Evaluating $(length(models)) models with Physics + Reason Scoring...")
    
    evaluated = []
    
    for (i, m) in enumerate(models)
        @printf "   [%2d/%2d] " i length(models)
        print("$(m.model[1:min(30, length(m.model))])... ")
        
        try
            # Full Evaluation
            score, θ, penalties, mse, reason_score = Phase6.evaluate_model_full(
                m.model, m.reason;
                num_coeffs=m.num_coeffs,
                with_penalty=true,
                csv_path=csv_path
            )
            
            if θ !== nothing && !isinf(score) && !isnan(score)
                # Sanitize penalties (replace NaN with 0.0 or Inf)
                safe_penalties = Dict(
                    k => isnan(v) ? Inf : v 
                    for (k, v) in pairs(penalties)
                )

                # Create detailed record
                record = (
                    id = m.id,
                    model = m.model,
                    score = score,
                    mse = mse,
                    reason_score = reason_score,
                    penalties = safe_penalties, # Use Dict instead of NamedTuple
                    coeffs = θ,
                    reason = m.reason,
                    ep_type = m.ep_type,
                    parent_generation = m.parent_generation,
                    parent_id = m.parent_id
                )
                push!(evaluated, record)
                
                # Format penalty string
                p_str = "P1=$(round(safe_penalties[:P1], digits=2)) P2=$(round(safe_penalties[:P2], digits=2)) P3=$(round(safe_penalties[:P3], digits=2)) P4=$(round(safe_penalties[:P4], digits=2))"
                @printf "✓ Score: %.6f (MSE: %.6f, R-Score: %.2f) [%s]\n" score mse reason_score p_str
            else
                println("✗ Failed (Inf/NaN)")
            end
        catch e
            println("✗ Error: $e")
            # Base.showerror(stdout, e, catch_backtrace())
        end
    end
    
    if isempty(evaluated)
        error("All models failed!")
    end

    # --- Diversity Bonus (Phase 7) ---
    println("\n🌈 Calculating Diversity Bonus...")
    
    # 1. Collect predictions for all valid models
    valid_indices = [i for (i, m) in enumerate(evaluated)]
    if !isempty(valid_indices)
        # Re-evaluate to get predictions (y_pred)
        # Note: This is a bit expensive but necessary if we didn't store y_pred.
        # Ideally, evaluate_model_full should return y_pred, but for now we re-calc or just use coefficients.
        # Actually, let's use a simplified approach: Diversity in Coefficients is hard because structures differ.
        # Diversity in Prediction is best.
        
        # Load data once
        df = Phase6.load_wake_data(csv_path)
        x_data = df.x
        r_data = df.r
        k_data = df.k
        omega_data = df.omega
        nut_data = df.nut
        
        predictions = []
        for rec in evaluated
            # Re-evaluate using optimized coefficients
            ex = Phase6.Evaluator.parse_model_expression(rec.model)
            y_pred = Phase6.Evaluator.eval_model(ex, rec.coeffs, x_data, r_data, k_data, omega_data, nut_data)
            push!(predictions, y_pred)
        end
        
        # 2. Calculate Ensemble Mean
        y_ensemble = mean(predictions)
        
        # 3. Calculate Diversity Score and Update Final Score
        for (i, rec) in enumerate(evaluated)
            y_pred = predictions[i]
            # MSE from ensemble mean
            div_score = mean((y_pred .- y_ensemble).^2)
            
            # Bonus: Higher diversity -> Lower Score (Better)
            # New Score = Old Score / (1 + 5.0 * Diversity)
            # We use a factor of 5.0 to make it significant but not overwhelming.
            bonus_factor = 1.0 + 5.0 * div_score
            new_score = rec.score / bonus_factor
            
            # Update record (Need to reconstruct NamedTuple or use Mutable struct. NamedTuple is immutable)
            # We'll create a new list of records
            evaluated[i] = merge(rec, (score=new_score, diversity=div_score, original_score=rec.score))
            
            @printf "   Model %d: Div=%.6f, Bonus=%.2fx, Score: %.6f -> %.6f\n" rec.id div_score bonus_factor rec.score new_score
        end
    end
    
    # Sort by New Score (Lower is better)
    sort!(evaluated, by=x->x.score)
    
    # Statistics
    best_model = evaluated[1]
    println("\n" * "="^70)
    println("📊 Gen $gen Stats")
    println("   Best Score: $(best_model.score)")
    println("   Best MSE:   $(best_model.mse)")
    println("   Best Reason Score: $(best_model.reason_score)")
    println("   Best Penalties: $(best_model.penalties)")
    println("   Formula: $(best_model.model)")
    println("="^70)
    
    # Save Feedback
    base_dir = joinpath("results", exp_name)
    feedback_path = joinpath(base_dir, "feedback_gen$gen.json")
    
    # Custom feedback generation to include penalties
    feedback_data = Dict(
        "generation" => gen,
        "best_score" => best_model.score,
        "best_model" => best_model,
        "evaluated_models" => evaluated
    )
    
    open(feedback_path, "w") do io
        JSON3.write(io, feedback_data)
    end
    
    # Append History
    history_path = joinpath(base_dir, "history.jsonl")
    EvolutionUtils.append_history(gen, evaluated, history_path)
    
    println("\n✅ Evaluation Complete!")
    println("📋 Next: Generate Gen $(gen+1) using templates/phase6_prompt.md")
end

function main()
    args = parse_commandline()
    
    if args["generate-initial"]
        generate_initial(args["size"], args["exp-name"], args["seeds-file"])
    elseif args["evaluate"] > 0
        input_file = args["input"]
        if isempty(input_file)
            input_file = joinpath("results", args["exp-name"], "models_gen$(args["evaluate"]).json")
        end
        evaluate_generation(args["evaluate"], input_file, args["csv-path"], args["exp-name"])
    else
        println("Usage: julia run_phase6.jl --generate-initial OR --evaluate N")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
