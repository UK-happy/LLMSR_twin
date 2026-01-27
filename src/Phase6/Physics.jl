module Physics

using Statistics
using ..Evaluator # Need eval_model

export calculate_penalty, calculate_individual_penalties

"""
    calculate_individual_penalties(ex, coeffs, y_pred, x, r, k, omega, nut)

Calculates individual physical penalties (P1-P4) using both data and virtual point evaluation.
"""
function calculate_individual_penalties(ex, coeffs, y_pred, x, r, k, omega, nut)
    # Weights (Relaxed for Phase 7)
    λ1 = 0.5 # Decay (Reduced from 1.0)
    λ2 = 0.5 # Symmetry
    λ3 = 2.0 # Range
    λ4 = 0.1 # Nut consistency (Reduced from 0.2)

    # Mean values for virtual checks
    k_mean = mean(k)
    omega_mean = mean(omega)
    nut_mean = mean(nut)

    # --- P1: x-direction Decay (Wake recovery) ---
    # Check monotonic decrease at r=0 for x = [5, 10, 20, 50, 100]
    x_test = [5.0, 10.0, 20.0, 50.0, 100.0]
    r_test = zeros(length(x_test))
    y_p1 = Evaluator.eval_model(ex, coeffs, x_test, r_test, fill(k_mean, 5), fill(omega_mean, 5), fill(nut_mean, 5))
    
    # Check diffs (should be negative for decay, i.e., y decreases)
    # diff(y) = y[i+1] - y[i]. If > 0, it's increasing (bad).
    diffs = diff(y_p1)
    # Sum of positive increases (violations) with margin
    margin_p1 = 1e-4
    p1_decay = sum(max.(diffs .- margin_p1, 0.0)) * 10.0
    
    # Asymptotic check (x -> 1000, r -> 100)
    y_inf_x = Evaluator.eval_model(ex, coeffs, [1000.0], [0.0], [k_mean], [omega_mean], [nut_mean])
    y_inf_r = Evaluator.eval_model(ex, coeffs, [10.0], [100.0], [k_mean], [omega_mean], [nut_mean])
    
    p1_asymp = (max(abs(y_inf_x[1]) - 1e-3, 0.0) + max(abs(y_inf_r[1]) - 1e-3, 0.0)) * 5.0
    
    P1 = min(p1_decay + p1_asymp, 100.0) # Cap at 100.0

    # --- P2: r-direction Symmetry ---
    # Check y(r) == y(-r) at x=10
    r_sym = [0.5, -0.5, 1.0, -1.0]
    x_sym = fill(10.0, 4)
    y_p2 = Evaluator.eval_model(ex, coeffs, x_sym, r_sym, fill(k_mean, 4), fill(omega_mean, 4), fill(nut_mean, 4))
    
    # Compare pairs: |y(0.5) - y(-0.5)| + |y(1.0) - y(-1.0)|
    diff_sym1 = abs(y_p2[1] - y_p2[2])
    diff_sym2 = abs(y_p2[3] - y_p2[4])
    P2 = min((diff_sym1 + diff_sym2) * 10.0, 100.0) # Cap at 100.0

    # --- P3: Physical Range ---
    # Check data predictions: 0 <= y <= 1.2
    # Strong penalty for negatives
    neg_violation = sum(y_pred .< -0.01)
    large_violation = sum(y_pred .> 1.2)
    total_points = length(y_pred)
    P3 = min(((neg_violation * 5.0 + large_violation) / total_points) * 10.0, 100.0) # Cap at 100.0

    # --- P4: Turbulence Consistency (Nut) ---
    # Check if increasing nut enhances mixing (reduces peak deficit).
    # Compare y(r=0) at nut_mean vs nut_mean * 1.5
    x_nut = [10.0]
    r_nut = [0.0]
    y_base = Evaluator.eval_model(ex, coeffs, x_nut, r_nut, [k_mean], [omega_mean], [nut_mean])
    y_high = Evaluator.eval_model(ex, coeffs, x_nut, r_nut, [k_mean], [omega_mean], [nut_mean * 1.5])
    
    # Expect y_high < y_base (more mixing -> lower peak)
    # Penalty if y_high > y_base (with margin)
    margin_p4 = 1e-4
    P4 = min(max(y_high[1] - y_base[1] - margin_p4, 0.0) * 10.0, 100.0) # Cap at 100.0

    return (P1=P1*λ1, P2=P2*λ2, P3=P3*λ3, P4=P4*λ4)
end

"""
    calculate_penalty(ex, coeffs, y_pred, x, r, k, omega, nut)

Calculates the total weighted physical penalty.
"""
function calculate_penalty(ex, coeffs, y_pred, x, r, k, omega, nut)
    penalties = calculate_individual_penalties(ex, coeffs, y_pred, x, r, k, omega, nut)
    return penalties.P1 + penalties.P2 + penalties.P3 + penalties.P4
end

end # module
