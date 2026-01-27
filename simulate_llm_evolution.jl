using JSON3
using Random
using Printf
using ArgParse
using GoogleGenAI

# Load Project Modules
push!(LOAD_PATH, joinpath(@__DIR__, "src"))
include("src/Phase6/EvolutionUtils.jl")
using .EvolutionUtils

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--start"
            help = "Start generation"
            arg_type = Int
            default = 1
        "--end"
            help = "End generation"
            arg_type = Int
            default = 5
        "--exp-name"
            help = "Experiment name"
            arg_type = String
            default = "trial_8"
        "--stage"
            help = "Evolution Stage (1: Diversity, 2: Hybrid, 3: Fitting)"
            arg_type = Int
            default = 3 # Default to standard fitting/evolution
    end
    return parse_args(s)
end

function generate_initial_candidates()
    return [
        Dict("id" => 1, "formula" => "a * exp(-b*x) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Standard Gaussian wake model with exponential decay in x and r.", "ep_type" => "Gaussian"),
        Dict("id" => 2, "formula" => "a * x^(-b) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Power law decay in x, Gaussian in r. Consistent with far wake theory.", "ep_type" => "PowerLaw"),
        Dict("id" => 3, "formula" => "a * (1 + b*x)^(-2) * (1 + c*r^2)^(-1)", "num_coeffs" => 3, "reason" => "Rational polynomial decay, similar to Jensen model but smooth.", "ep_type" => "Rational"),
        Dict("id" => 4, "formula" => "a * exp(-b*x) * exp(-c*r^2) * (1 + d*nut)", "num_coeffs" => 4, "reason" => "Added eddy viscosity term to account for turbulence mixing.", "ep_type" => "Physics"),
        Dict("id" => 5, "formula" => "a * (1 + b*x) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Linear growth in x to test recovery.", "ep_type" => "Experimental"),
        Dict("id" => 6, "formula" => "-a * exp(-b*x) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Negative deficit? Just guessing.", "ep_type" => "Random"),
        Dict("id" => 7, "formula" => "a * exp(-b*x) * exp(-c*r)", "num_coeffs" => 3, "reason" => "Exponential in r, not r^2. Might violate symmetry at r=0 cusp.", "ep_type" => "Asymmetric"),
        Dict("id" => 8, "formula" => "a * k * exp(-b*x) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Using TKE (k) to scale the deficit.", "ep_type" => "Physics"),
        Dict("id" => 9, "formula" => "a * exp(-b*x*omega) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Decay rate depends on omega.", "ep_type" => "Physics"),
        Dict("id" => 10, "formula" => "a * (1 + b*x)^(-1.5) * (1 + c*r^2)^(-2) + d*nut", "num_coeffs" => 4, "reason" => "Combination of power law and nut offset.", "ep_type" => "Hybrid"),
        Dict("id" => 11, "formula" => "a * exp(-b*x^2) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Gaussian in x and r.", "ep_type" => "Gaussian"),
        Dict("id" => 12, "formula" => "a * (x + 1)^(-b) * (r^2 + 1)^(-c)", "num_coeffs" => 3, "reason" => "Shifted power law.", "ep_type" => "PowerLaw"),
        Dict("id" => 13, "formula" => "a * exp(-b*x) * cos(c*r)", "num_coeffs" => 3, "reason" => "Cosine profile in r. P3 violation likely.", "ep_type" => "Trig"),
        Dict("id" => 14, "formula" => "a * tanh(b*x) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Tanh behavior.", "ep_type" => "Sigmoid"),
        Dict("id" => 15, "formula" => "a * exp(-b*x) / (1 + c*r^4)", "num_coeffs" => 3, "reason" => "Quartic denominator in r.", "ep_type" => "Rational"),
        Dict("id" => 16, "formula" => "a * exp(-b*x) * exp(-c*abs(r))", "num_coeffs" => 3, "reason" => "Absolute value for symmetry.", "ep_type" => "Abs"),
        Dict("id" => 17, "formula" => "a * (1 - exp(-b*x)) * exp(-c*r^2)", "num_coeffs" => 3, "reason" => "Recovery form 1-exp.", "ep_type" => "Recovery"),
        Dict("id" => 18, "formula" => "a * x^(-1/3) * exp(-b*r^2)", "num_coeffs" => 2, "reason" => "Fixed power law -1/3.", "ep_type" => "FixedPower"),
        Dict("id" => 19, "formula" => "a * x^(-2/3) * exp(-b*r^2)", "num_coeffs" => 2, "reason" => "Fixed power law -2/3.", "ep_type" => "FixedPower"),
        Dict("id" => 20, "formula" => "a * x^(-1) * exp(-b*r^2)", "num_coeffs" => 2, "reason" => "Fixed power law -1.", "ep_type" => "FixedPower")
    ]
end

function generate_diversity_population()
    println("   ✨ Generating diverse population using Gemini API (Stage 1)...")
    
    # Load Prompts
    system_prompt = read("templates/phase6_diversity_system.md", String)
    user_prompt = read("templates/phase6_diversity_user.md", String)
    
    # Append JSON instruction
    user_prompt *= "\n\nIMPORTANT: Output the result as a JSON list of strings, e.g., [\"formula1\", \"formula2\"]. Do not include markdown code blocks or explanations."
    
    # Call Gemini API
    secret_key = ENV["GOOGLE_API_KEY"]
    # model = GoogleGenAI.GeminiModel("gemini-1.5-pro-latest", api_key=secret_key) # Incorrect usage
    
    # Correct usage based on evaluate_reason_api.jl
    # Using gemini-2.5-pro as requested
    response = GoogleGenAI.generate_content(secret_key, "gemini-2.5-pro", "$system_prompt\n\n$user_prompt")
    text = response.text
    
    # Parse JSON
    try
        # Clean up markdown code blocks if present
        text = replace(text, r"```json" => "")
        text = replace(text, r"```" => "")
        text = strip(text)
        
        formulas = JSON3.read(text, Vector{String})
        
        models = []
        for (i, f) in enumerate(formulas)
            push!(models, Dict(
                "id" => i,
                "formula" => f,
                "num_coeffs" => 4, # Default assumption, optimizer will handle unused
                "reason" => "Stage 1 Diversity Generation: $f",
                "ep_type" => "Diversity"
            ))
        end
        return models
    catch e
        println("   ⚠️ Failed to parse LLM response: $e")
        println("   Response was: $text")
        return generate_initial_candidates() # Fallback
    end
end

function simulate_llm(gen_start, gen_end, exp_name, stage)
    for gen in gen_start:gen_end
        output_file = "results/$exp_name/models_gen$gen.json"
        println("\n🤖 Simulating LLM for Generation $gen (Stage $stage)...")

        new_models = []
        
        if gen == 1
            # Gen 1: Initial Population
            if stage == 1
                new_models = generate_diversity_population()
            else
                println("   Using standard hardcoded initial population (Stage $stage)...")
                new_models = generate_initial_candidates()
            end
        else
            # Gen 2+: Evolution from previous generation
            prev_gen = gen - 1
            feedback_file = "results/$exp_name/feedback_gen$prev_gen.json"
            
            # Load feedback
            if !isfile(feedback_file)
                error("Feedback file not found: $feedback_file")
            end
            feedback = JSON3.read(read(feedback_file, String), Dict)
            
            # Get best models (top 3)
            # feedback["evaluated_models"] is a vector of dicts
            evaluated = feedback["evaluated_models"]
            best_models = evaluated[1:min(5, length(evaluated))]
            
            model_id = 1
            
            # Strategy: Mutate best models
            for parent in best_models
                # Keep the parent (Elitism) - maybe slightly modified
                # Note: feedback uses "model", but we need to save as "formula" for load_models
                parent_formula = get(parent, "model", get(parent, "formula", ""))
                parent_num_coeffs = get(parent, "num_coeffs", length(get(parent, "coeffs", [])))
                
                push!(new_models, Dict(
                    "id" => model_id,
                    "formula" => parent_formula,
                    "num_coeffs" => parent_num_coeffs,
                    "reason" => "Retaining high performance model: " * parent["reason"],
                    "ep_type" => "Elitism",
                    "parent_generation" => prev_gen,
                    "parent_id" => parent["id"]
                ))
                model_id += 1
                
                # Mutation 1: Change powers (excluding r^... to avoid complex numbers on negative r)
                # Regex: Match ^number NOT preceded by r
                mutated_formula = replace(parent_formula, r"(?<!r)\^(-?\d+(\.\d+)?)" => (s) -> "^(" * string(round(parse(Float64, match(r"-?\d+(\.\d+)?", s).match) * (0.9 + 0.2*rand()), digits=2)) * ")")
                push!(new_models, Dict(
                    "id" => model_id,
                    "formula" => mutated_formula,
                    "num_coeffs" => parent_num_coeffs,
                    "reason" => "Adjusted exponents (x/terms) to fine-tune decay. P1/P3 optimization.",
                    "ep_type" => "Mutation",
                    "parent_generation" => prev_gen,
                    "parent_id" => parent["id"]
                ))
                model_id += 1
                
                # Mutation 2: Add small term (if simple)
                if length(parent_formula) < 50
                    push!(new_models, Dict(
                        "id" => model_id,
                        "formula" => parent_formula * " * (1 + d*nut)",
                        "num_coeffs" => parent_num_coeffs + 1,
                        "reason" => "Added nut term to improve turbulence consistency (P4).",
                        "ep_type" => "Expansion",
                        "parent_generation" => prev_gen,
                        "parent_id" => parent["id"]
                    ))
                    model_id += 1
                end
            end
            
            # Fill the rest with random variations or new ideas
            while length(new_models) < 20
                # Random new idea
                base_forms = [
                    "a * exp(-b*x) * exp(-c*r^2)",
                    "a * x^(-b) * (1 + c*r^2)^(-1)",
                    "a * (1 + b*x)^(-2) * exp(-c*r^2)",
                    "a * x^(-1/3) * exp(-b*r^2) * (1 + c*nut)"
                ]
                form = rand(base_forms)
                push!(new_models, Dict(
                    "id" => model_id,
                    "formula" => form,
                    "num_coeffs" => 3 + (occursin("nut", form) ? 1 : 0),
                    "reason" => "Exploring new structure to escape local optima. P1/P2 focus.",
                    "ep_type" => "Random",
                    "parent_generation" => prev_gen,
                    "parent_id" => nothing
                ))
                model_id += 1
            end
        end
        
        # Save models
        mkpath(dirname(output_file))
        json_data = Dict("generation" => gen, "models" => new_models)
        open(output_file, "w") do io
            JSON3.pretty(io, json_data)
        end
        println("   ✓ Generated $(length(new_models)) models in $output_file")
        
        # Run Evaluation
        cmd = `julia --project=. run_phase6.jl --evaluate $gen --exp-name $exp_name`
        println("   Running evaluation...")
        run(cmd)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    EvolutionUtils.load_env()
    args = parse_commandline()
    simulate_llm(args["start"], args["end"], args["exp-name"], args["stage"])
end
