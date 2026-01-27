using JSON3
using Plots
using Statistics
using Printf
using DataFrames
using CSV

# Helper to load JSON
function load_json(path)
    return JSON3.read(read(path, String))
end

function main()
    # Hardcoded for Trial 8 Gen 20 verification, but can be argued
    exp_name = "trial_8"
    gen = 20
    
    base_dir = joinpath("results", exp_name)
    feedback_path = joinpath(base_dir, "feedback_gen$gen.json")
    api_eval_path = joinpath(base_dir, "evaluation_api_gen$gen.json")
    output_dir = joinpath(base_dir, "plots")
    mkpath(output_dir)
    
    println("📊 Comparing Reason Scores for $exp_name Gen $gen")
    println("-"^60)
    
    # 1. Load Data
    if !isfile(feedback_path)
        error("Feedback file not found: $feedback_path")
    end
    if !isfile(api_eval_path)
        error("API Evaluation file not found: $api_eval_path. Please run evaluate_reason_api.jl first.")
    end
    
    feedback_data = load_json(feedback_path)
    api_data = load_json(api_eval_path)
    
    # Map API scores by ID
    api_scores = Dict()
    for item in api_data.evaluations
        api_scores[item.id] = item.api_score
    end
    
    # Collect combined data
    ids = []
    mses = []
    old_scores = []
    new_scores = []
    
    for m in feedback_data.evaluated_models
        if haskey(api_scores, m.id)
            push!(ids, m.id)
            push!(mses, m.mse)
            push!(old_scores, m.reason_score)
            push!(new_scores, api_scores[m.id])
        end
    end
    
    n = length(ids)
    println("   Loaded $n models with both scores.")
    
    # 2. Correlation Analysis
    # Log10 MSE is better for correlation as MSE varies by orders of magnitude
    log_mses = log10.(mses)
    
    corr_old = cor(old_scores, log_mses)
    corr_new = cor(new_scores, log_mses)
    
    println("\n1. Correlation Analysis (Score vs log10(MSE))")
    println("   Target: Negative correlation (Higher Score -> Lower MSE)")
    println("-"^40)
    @printf "   Old (Programmatic): %.4f\n" corr_old
    @printf "   New (API-based):    %.4f\n" corr_new
    
    improvement = abs(corr_new) - abs(corr_old)
    if corr_new < corr_old && corr_new < 0
        println("   ✅ Improvement: Correlation became more negative (stronger relationship).")
    else
        println("   ⚠️  No clear improvement in correlation strength.")
    end
    
    # 3. Distribution Analysis
    println("\n2. Distribution Analysis")
    println("-"^40)
    @printf "   Old Scores: Mean=%.2f, Std=%.2f, Range=[%.2f, %.2f]\n" mean(old_scores) std(old_scores) minimum(old_scores) maximum(old_scores)
    @printf "   New Scores: Mean=%.2f, Std=%.2f, Range=[%.2f, %.2f]\n" mean(new_scores) std(new_scores) minimum(new_scores) maximum(new_scores)
    
    # 4. Plotting
    println("\n3. Generating Plots...")
    
    # Scatter Plot Comparison
    p1 = scatter(old_scores, log_mses, label="Old (Rule-based)", color=:blue, alpha=0.6, markersize=6)
    scatter!(p1, new_scores, log_mses, label="New (API-based)", color=:red, alpha=0.6, markersize=6, shape=:star5)
    title!(p1, "Reason Score vs MSE (Gen $gen)")
    xlabel!(p1, "Reason Score")
    ylabel!(p1, "log10(MSE)")
    
    savefig(p1, joinpath(output_dir, "score_comparison_scatter.png"))
    println("   Saved: score_comparison_scatter.png")
    
    # Histogram Comparison
    p2 = histogram(old_scores, label="Old", color=:blue, alpha=0.5, bins=0:0.1:1.1, bar_width=0.04)
    histogram!(p2, new_scores, label="New", color=:red, alpha=0.5, bins=0:0.1:1.1, bar_width=0.04)
    title!(p2, "Score Distribution")
    xlabel!(p2, "Score")
    ylabel!(p2, "Count")
    
    savefig(p2, joinpath(output_dir, "score_comparison_dist.png"))
    println("   Saved: score_comparison_dist.png")
    
    println("\n✅ Verification Complete.")
end

main()
