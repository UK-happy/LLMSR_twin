#!/usr/bin/env julia

"""
Reason vs MSE Correlation Analysis

Analyzes the relationship between the quality of the LLM's reasoning (Reason Score)
and the performance of the generated models (MSE).

Usage:
    julia --project=. analyze_reason_correlation.jl [--exp-name trial_8]
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

    println("📊 Analyzing Reason vs MSE for: $exp_name")
    println("📂 Loading history: $history_file")

    if !isfile(history_file)
        error("History file not found: $history_file")
    end

    # Load Data
    data = []
    open(history_file, "r") do io
        for line in eachline(io)
            gen_data = JSON3.read(line)
            for model in gen_data.all_models
                # Filter out failed runs or invalid scores
                if haskey(model, :mse) && haskey(model, :reason_score) && 
                   model.mse < 1.0 && model.mse > 0.0
                    push!(data, (mse = model.mse, reason = model.reason_score, gen = gen_data.generation))
                end
            end
        end
    end

    df = DataFrame(data)
    println("✅ Loaded $(nrow(df)) valid models.")

    # 1. Correlation Analysis
    # We use log(MSE) because MSE varies by orders of magnitude
    log_mse = log10.(df.mse)
    correlation = cor(df.reason, log_mse)
    
    println("\n📈 Correlation Analysis:")
    println("   Pearson Correlation (Reason vs log10(MSE)): $(round(correlation, digits=4))")
    
    if correlation < -0.3
        println("   👉 Significant NEGATIVE correlation: Better reasons -> Lower MSE (Good!)")
    elseif correlation > 0.3
        println("   👉 Significant POSITIVE correlation: Better reasons -> Higher MSE (Unexpected)")
    else
        println("   👉 Weak or No correlation.")
    end

    # 2. Scatter Plot
    p1 = scatter(df.reason, df.mse, 
        yscale=:log10, 
        xlabel="Reason Score", 
        ylabel="MSE (log scale)",
        title="Reason Quality vs Model Performance",
        label="Models",
        alpha=0.6,
        markercolor=:blue,
        legend=:topright
    )
    
    # Add trend line
    X = [ones(length(df.reason)) df.reason]
    y = log10.(df.mse)
    coeffs = X \ y
    x_trend = 0.0:0.1:1.0
    y_trend = 10 .^ (coeffs[1] .+ coeffs[2] .* x_trend)
    plot!(p1, x_trend, y_trend, label="Trend", linewidth=2, color=:red)

    savefig(p1, joinpath(plots_dir, "reason_vs_mse_scatter.png"))
    println("   💾 Saved scatter plot: $(joinpath(plots_dir, "reason_vs_mse_scatter.png"))")

    # 3. Box Plot Replacement (Scatter with Mean)
    # Since StatsPlots might not be available, we use a manual approach
    
    # Calculate stats per group
    df.reason_group = round.(df.reason, digits=1)
    gdf = groupby(df, :reason_group)
    stats = combine(gdf, :mse => mean => :mean_mse, :mse => std => :std_mse, :mse => length => :count)
    sort!(stats, :reason_group)
    
    p2 = scatter(df.reason_group, df.mse,
        yscale=:log10,
        xlabel="Reason Score",
        ylabel="MSE (log scale)",
        title="MSE Distribution by Reason Score",
        label="Models",
        alpha=0.3,
        markercolor=:gray
    )
    
    # Plot Mean points
    # Calculate asymmetric error bars for log scale
    # Ensure lower bound doesn't go below min(mse) or 0
    min_mse = minimum(df.mse)
    lower_bound = max.(stats.mean_mse .- stats.std_mse, min_mse)
    lower_error = stats.mean_mse .- lower_bound
    upper_error = stats.std_mse
    
    plot!(p2, stats.reason_group, stats.mean_mse,
        seriestype=:scatter,
        yerror=(lower_error, upper_error),
        label="Mean ± Std",
        markercolor=:red,
        markersize=6,
        linewidth=2
    )
    
    savefig(p2, joinpath(plots_dir, "reason_vs_mse_dist.png"))
    println("   💾 Saved distribution plot: $(joinpath(plots_dir, "reason_vs_mse_dist.png"))")

    # 4. Summary Statistics by Group
    println("\n📊 Summary by Reason Score:")
    println(stats)
end

main()
