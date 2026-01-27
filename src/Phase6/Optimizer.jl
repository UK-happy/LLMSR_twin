module Optimizer

using BlackBoxOptim
using ..Evaluator
using ..Physics

export optimize_coefficients

function optimize_coefficients(ex, df; num_coeffs=4, with_penalty=true)
    
    x = df.x
    r = df.r
    k = df.k
    omega = df.omega
    nut = df.nut
    deltaU = df.deltaU
    
    function loss(θ)
        # 1. MSE
        mse = Evaluator.mse_eval(ex, θ, x, r, k, omega, nut, deltaU)
        
        # 2. Physics Penalty (if enabled)
        penalty = 0.0
        if with_penalty
            y_pred = Evaluator.eval_model(ex, θ, x, r, k, omega, nut)
            # New signature: ex, coeffs, y_pred, x, r, k, omega, nut
            penalty = Physics.calculate_penalty(ex, θ, y_pred, x, r, k, omega, nut)
        end
        
        # Combined Objective for DE
        # Objective = MSE * (1 + Penalty)
        return mse * (1.0 + penalty)
    end
    
    # Search Range
    search_range = [(-100.0, 100.0) for _ in 1:num_coeffs]
    
    # Optimization
    res = bboptimize(loss; 
        SearchRange = search_range, 
        NumDimensions = num_coeffs, 
        MaxTime = 5.0, 
        TraceMode = :silent
    )
    
    best_θ = best_candidate(res)
    
    # Re-calculate for reporting
    final_mse = Evaluator.mse_eval(ex, best_θ, x, r, k, omega, nut, deltaU)
    
    final_penalty = 0.0
    penalty_breakdown = (P1=0.0, P2=0.0, P3=0.0, P4=0.0)
    
    if with_penalty
        y_pred = Evaluator.eval_model(ex, best_θ, x, r, k, omega, nut)
        final_penalty = Physics.calculate_penalty(ex, best_θ, y_pred, x, r, k, omega, nut)
        penalty_breakdown = Physics.calculate_individual_penalties(ex, best_θ, y_pred, x, r, k, omega, nut)
    end
    
    return best_θ, final_mse, final_penalty, penalty_breakdown
end

end # module
