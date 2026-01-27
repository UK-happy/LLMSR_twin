using Pkg
Pkg.activate(".")

include("src/Phase5/Phase5.jl")
using .Phase5

println("Testing Phase 5 functionality...")

# Test Model: Simple Gaussian
model_str = "a * (1 + b*x)^(-2) * exp(-c*r^2)"
println("Evaluating model: $model_str")

score, coeffs = evaluate_formula(model_str; num_coeffs=3, with_penalty=true)

println("Score: $score")
println("Coefficients: $coeffs")

if score < 1.0 && coeffs !== nothing
    println("✅ Phase 5 verification successful.")
else
    println("❌ Phase 5 verification failed.")
end
