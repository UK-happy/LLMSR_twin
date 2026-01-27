module EvolutionUtils

using JSON3
using Statistics
using Dates

export save_feedback, load_models, append_history, calculate_diversity, 
       generate_initial_feedback, format_model_for_display, select_diverse_elites, load_seeds, update_seeds, load_env

"""
    save_feedback(generation::Int, evaluated::Vector, filepath::String)

Saves evaluation results to JSON for LLM feedback.
Includes Phase 6 specific fields (penalties, reason_score).
"""
function save_feedback(generation::Int, evaluated::Vector, filepath::String)
    sorted = sort(evaluated, by=x->x.score)
    
    feedback = Dict(
        "generation" => generation,
        "timestamp" => string(now()),
        "evaluated_models" => [
            Dict(
                "id" => model.id,
                "formula" => model.model,
                "num_coeffs" => length(model.coeffs),
                "score" => model.score,
                "mse" => get(model, :mse, 0.0),
                "reason_score" => get(model, :reason_score, 0.0),
                "penalties" => get(model, :penalties, Dict()),
                "coefficients" => model.coeffs,
                "reason" => get(model, :reason, ""),
                "ep_type" => get(model, :ep_type, ""),
                "parent_generation" => get(model, :parent_generation, nothing),
                "parent_id" => get(model, :parent_id, nothing)
            )
            for (i, model) in enumerate(sorted)
        ],
        "best_model" => Dict(
            "formula" => sorted[1].model,
            "score" => sorted[1].score,
            "coefficients" => sorted[1].coeffs
        ),
        "statistics" => Dict(
            "best_score" => sorted[1].score,
            "mean_score" => mean([m.score for m in sorted]),
            "population_size" => length(sorted)
        )
    )
    
    open(filepath, "w") do io
        JSON3.pretty(io, feedback)
    end
    
    @info "Feedback saved to: $filepath"
    return feedback
end

function load_models(filepath::String)
    if !isfile(filepath)
        error("Model file not found: $filepath")
    end
    
    data = JSON3.read(read(filepath, String))
    
    models = []
    for m in data.models
        push!(models, (
            id = get(m, :id, 0),
            model = m.formula,
            num_coeffs = m.num_coeffs,
            reason = get(m, :reason, ""),
            ep_type = get(m, :ep_type, ""),
            parent_generation = get(m, :parent_generation, nothing),
            parent_id = get(m, :parent_id, nothing)
        ))
    end
    
    @info "Loaded $(length(models)) models from: $filepath"
    return models
end

function append_history(generation::Int, evaluated::Vector, filepath::String)
    sorted = sort(evaluated, by=x->x.score)
    
    history_entry = Dict(
        "generation" => generation,
        "timestamp" => string(now()),
        "best_score" => sorted[1].score,
        "mean_score" => mean([m.score for m in sorted]),
        "best_model" => Dict(
            "formula" => sorted[1].model,
            "coefficients" => sorted[1].coeffs,
            "reason" => get(sorted[1], :reason, "")
        ),
        "all_models" => [
            Dict(
                "id" => m.id,
                "formula" => m.model,
                "score" => m.score,
                "mse" => get(m, :mse, 0.0),
                "reason_score" => get(m, :reason_score, 0.0),
                "penalties" => get(m, :penalties, Dict()),
                "coefficients" => m.coeffs,
                "reason" => get(m, :reason, ""),
                "ep_type" => get(m, :ep_type, ""),
                "parent_generation" => get(m, :parent_generation, nothing),
                "parent_id" => get(m, :parent_id, nothing)
            )
            for m in sorted
        ]
    )
    
    open(filepath, "a") do io
        JSON3.write(io, history_entry)
        write(io, "\n")
    end
    
    @info "History updated: Generation $generation"
end

function generate_initial_feedback(size::Int, filepath::String; seeds::Vector=Dict[])
    seed_text = ""
    if !isempty(seeds)
        seed_text = "【Seeds from previous trials】\n"
        for (i, seed) in enumerate(seeds)
            seed_formula = get(seed, :formula, get(seed, "formula", ""))
            seed_score = get(seed, :score, get(seed, "score", 0.0))
            seed_text *= "- Seed $i: $(seed_formula) (Score: $(seed_score))\n"
        end
    end

    feedback = Dict(
        "generation" => 0,
        "timestamp" => string(now()),
        "request" => "initial_population",
        "population_size" => size,
        "instructions" => """
        Generate $(size) initial models for Wind Turbine Wake Deficit ΔU(x, r).
        
        Variables: x, r, k, omega, nut
        Format: Julia scalar expression (e.g., a * exp(-b*x) * (1 + c*r^2)^(-d))
        
        Constraints (Phase 6):
        - P1: Decay in x (monotonic)
        - P2: Symmetry in r
        - P3: Physical range (0 <= ΔU <= 1.2)
        - P4: Nut consistency
        
        $(seed_text)
        """
    )
    
    open(filepath, "w") do io
        JSON3.pretty(io, feedback)
    end
    
    @info "Initial feedback generated: $filepath"
end

function load_seeds(filepath::String)
    if !isfile(filepath)
        @warn "Seeds file not found: $filepath"
        return Dict[]
    end
    try
        data = JSON3.read(read(filepath, String))
        return [Dict(pairs(item)) for item in data]
    catch e
        @error "Failed to load seeds" e
        return Dict[]
    end
end

function load_env(filepath::String=".env")
    if !isfile(filepath)
        return
    end
    
    for line in eachline(filepath)
        line = strip(line)
        if isempty(line) || startswith(line, "#")
            continue
        end
        
        parts = split(line, "=", limit=2)
        if length(parts) == 2
            key = strip(parts[1])
            value = strip(parts[2])
            
            # Remove quotes if present
            if (startswith(value, "\"") && endswith(value, "\"")) || 
               (startswith(value, "'") && endswith(value, "'"))
                value = value[2:end-1]
            end
            
            if !haskey(ENV, key)
                ENV[key] = value
            end
        end
    end
end

end # module
