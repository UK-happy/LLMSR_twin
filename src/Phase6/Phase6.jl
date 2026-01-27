module Phase6

using CSV, DataFrames
using BlackBoxOptim
using Statistics
using Printf

# Submodules
include("DataLoader.jl")
include("ReasonScorer.jl")
include("Evaluator.jl")
include("Physics.jl")
include("Optimizer.jl")

using .DataLoader
using .Physics
using .ReasonScorer
using .Evaluator
using .Optimizer

export evaluate_formula, load_wake_data, evaluate_model_full

# Global Data Cache
const DATA_LOADED = Ref(false)
const WAKE_DATA = Ref{DataFrame}()

function load_wake_data(csv_path::String)
    if !DATA_LOADED[]
        @info "Loading wake data from: $csv_path"
        WAKE_DATA[] = DataLoader.load_wake_csv(csv_path)
        DATA_LOADED[] = true
        @info "Data loaded: $(size(WAKE_DATA[])) rows"
    end
    return WAKE_DATA[]
end

"""
    evaluate_formula(model_str; ...)

Evaluates numerical performance and physical penalties.
Returns (score, θ_opt, penalty_breakdown, mse).
"""
function evaluate_formula(model_str::String;
                          num_coeffs::Int=4,
                          with_penalty::Bool=true,
                          csv_path::String="data/result_I0p3000_C22p0000.csv")
    
    df = load_wake_data(csv_path)
    
    ex = Evaluator.parse_model_expression(model_str)
    if ex === nothing
        return (Inf, nothing, nothing, Inf)
    end
    
    # Optimize
    θ_opt, mse_score, physics_penalty, penalty_breakdown = Optimizer.optimize_coefficients(
        ex, df;
        num_coeffs=num_coeffs,
        with_penalty=with_penalty
    )
    
    # Base Score (MSE * (1 + Penalty))
    base_score = mse_score * (1.0 + physics_penalty)
    
    return (base_score, θ_opt, penalty_breakdown, mse_score)
end

"""
    evaluate_model_full(model_str, reason_str; ...)

Evaluates model including Reason quality.
Final Score = BaseScore * (1.0 - ReasonScore * 0.1)
(ReasonScore is 0.0 to 1.0, so max 10% bonus for good reasoning)
"""
function evaluate_model_full(model_str::String, reason_str::String;
                             num_coeffs::Int=4,
                             with_penalty::Bool=true,
                             csv_path::String="data/result_I0p3000_C22p0000.csv")
                             
    base_score, θ_opt, penalty_breakdown, mse = evaluate_formula(model_str; 
        num_coeffs=num_coeffs, with_penalty=with_penalty, csv_path=csv_path)
        
    if θ_opt === nothing
        return (Inf, nothing, nothing, Inf, 0.0)
    end
    
    # Calculate Reason Score
    # We need to pass the penalty breakdown to the scorer? 
    # Or just score the text quality?
    # ReasonScorer.score_reason(reason_text)
    reason_score = ReasonScorer.score_reason(reason_str)
    
    # Apply Reason Bonus (reduce score)
    # Max bonus: 20% reduction for perfect reason
    bonus_factor = 0.2
    final_score = base_score * (1.0 - reason_score * bonus_factor)
    
    return (final_score, θ_opt, penalty_breakdown, mse, reason_score)
end

end # module Phase6
