#!/usr/bin/env julia

"""
Physics Validity Analysis

Analyzes the proportion of models that satisfy all physical constraints (Total Penalty = 0)
across generations.

Usage:
    julia --project=. analyze_physics_validity.jl [--exp-name trial_8]
"""

using JSON3
using DataFrames
using Statistics
using Plots
using Printf
using ArgParse

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--exp-name"
            help = "Experiment name"
            default = "trial_8"
    end
    return parse_args(s)
end

function main()
    args = parse_commandline()
    exp_name = args["exp-name"]
    history_file = joinpath("results", exp_name, "history.jsonl")
    plots_dir = joinpath("results", exp_name, "plots")
    mkpath(plots_dir)

    println("📊 Analyzing Physics Validity for: $exp_name")
    println("📂 Loading history: $history_file")

    if !isfile(history_file)
        error("History file not found: $history_file")
    end

    # Load Data
    gen_stats = []
    
    open(history_file, "r") do io
        for line in eachline(io)
            gen_data = JSON3.read(line)
            generation = gen_data.generation
            models = gen_data.all_models
            
            total_count = length(models)
            valid_count = 0
            
            for model in models
                # Check penalties
                penalties = get(model, :penalties, Dict())
                total_penalty = sum(values(penalties))
                
                # Consider valid if total penalty is effectively zero
                if total_penalty < 1e-6
                    valid_count += 1
                end
            end
            
            valid_ratio = total_count > 0 ? (valid_count / total_count) * 100.0 : 0.0
            
            push!(gen_stats, (gen = generation, total = total_count, valid = valid_count, ratio = valid_ratio))
        end
    end

    df = DataFrame(gen_stats)
    sort!(df, :gen)
    
    println("\n📊 Validity Statistics per Generation:")
    println(df)

    # Plot Trend
    p = plot(df.gen, df.ratio,
        xlabel="Generation",
        ylabel="Physically Valid Models (%)",
        title="Evolution of Physical Validity",
        label="Valid Ratio",
        marker=:circle,
        linewidth=2,
        color=:green,
        ylims=(0, 105),
        legend=:bottomright,
        size=(800, 500)
    )
    
    # Add a trend line or smooth curve if needed, but raw data is usually fine for this.
    
    output_path = joinpath(plots_dir, "physics_validity_trend.png")
    savefig(p, output_path)
    println("\n💾 Saved trend plot: $output_path")
    
    # Check for improvement
    first_ratio = df.ratio[1]
    last_ratio = df.ratio[end]
    improvement = last_ratio - first_ratio
    
    println("\n📈 Trend Analysis:")
    println("   Start (Gen $(df.gen[1])): $(round(first_ratio, digits=1))%")
    println("   End (Gen $(df.gen[end])): $(round(last_ratio, digits=1))%")
    println("   Change: $(round(improvement, digits=1)) points")
    
    if improvement > 10.0
        println("   👉 Significant improvement in physical validity!")
    elseif improvement < -10.0
        println("   👉 Validity degraded over time.")
    else
        println("   👉 Validity remained relatively stable.")
    end
end

main()
