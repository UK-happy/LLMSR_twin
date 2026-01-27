module Evaluator

using Statistics

export parse_model_expression, eval_model, mse_eval, calculate_complexity

function parse_model_expression(model_str::String)
    try
        return Meta.parse(model_str)
    catch e
        @error "Expression parse error" e
        return nothing
    end
end

function eval_model(ex::Expr, θ, x, r, k, omega, nut)
    # Similar to Phase 5 implementation
    localvars = Dict{Symbol,Any}()
    coeff_names = [:a, :b, :c, :d, :e, :f, :g, :h, :i]

    for (i, nm) in enumerate(coeff_names)
        if i > length(θ)
            break
        end
        localvars[nm] = θ[i]
    end

    localvars[:x] = x
    localvars[:r] = r
    localvars[:k] = k
    localvars[:omega] = omega
    localvars[:nut] = nut

    function vectorize_expr(ex)
        if isa(ex, Expr)
            if ex.head == :call
                func = ex.args[1]
                args = map(vectorize_expr, ex.args[2:end])
                return Expr(:call, :broadcast, func, args...)
            else
                return Expr(ex.head, map(vectorize_expr, ex.args)...)
            end
        else
            return ex
        end
    end
    
    vectorized_ex = vectorize_expr(ex)
    
    try
        assignments = Expr(:block, [:( $(k) = $(v) ) for (k,v) in localvars]...)
        return eval(Expr(:let, assignments, vectorized_ex))
    catch e
        return fill(1e9, length(x))
    end
end

function mse_eval(ex, θ, x, r, k, omega, nut, deltaU)
    ŷ = eval_model(ex, θ, x, r, k, omega, nut)
    
    if any(isnan, ŷ) || any(isinf, ŷ) || any(abs.(ŷ) .> 1e6)
        return 1e9
    end

    return mean((ŷ .- deltaU).^2)
end

function calculate_complexity(ex)
    if isa(ex, Expr)
        return 1 + sum(calculate_complexity(arg) for arg in ex.args)
    else
        return 1
    end
end

end # module
