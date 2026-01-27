using GoogleGenAI
using JSON3
using ArgParse
using Printf
using Dates

# Load helper modules
push!(LOAD_PATH, joinpath(@__DIR__, "../"))
include("../Phase6/EvolutionUtils.jl")
using .EvolutionUtils

const API_KEY = get(ENV, "GOOGLE_API_KEY", "")

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--gen"
            help = "Generation number to evaluate"
            arg_type = Int
            required = true
        "--exp-name"
            help = "Experiment name"
            arg_type = String
            default = "default"
        "--model"
            help = "Model to use (gemini-1.5-pro-latest, gemini-1.5-flash, etc.)"
            arg_type = String
            default = "gemini-1.5-pro-latest"
    end
    return parse_args(s)
end

function load_template(path::String)
    if !isfile(path)
        error("Template not found: $path")
    end
    return read(path, String)
end

function fill_template(template::String, model_data::Dict)
    text = template
    for (key, value) in model_data
        text = replace(text, "{{" * key * "}}" => string(value))
    end
    return text
end

# --- Parser System ---

abstract type ModelParser end
struct DefaultParser <: ModelParser end
struct GeminiParser <: ModelParser end
struct GPTParser <: ModelParser end

function get_parser(model_name::String)
    lower_name = lowercase(model_name)
    if occursin("gemini", lower_name)
        return GeminiParser()
    elseif occursin("gpt", lower_name)
        return GPTParser()
    else
        return DefaultParser()
    end
end

# Default Parser (Robust fallback)
function parse_score(::ModelParser, text::String)
    # Generic robust regex
    m = match(r"(?i)(?:Step|STEP)\s*5.*?(\d+(?:\.\d+)?)", text)
    if m !== nothing
        return clamp(parse(Float64, m.captures[1]) / 5.0, 0.0, 1.0)
    end
    return -1.0 # Error code
end

# Gemini Parser (Handles Markdown, Newlines, "Score:" label)
function parse_score(::GeminiParser, text::String)
    # Pattern 1: Explicit "Score: X" anywhere after "Step 5" (multiline)
    m1 = match(r"(?i)(?:Step|STEP)\s*5[\s\S]*?Score\s*[:=]\s*(\d+(?:\.\d+)?)", text)
    
    # Pattern 2: Just "Step 5: X" (number immediately follows)
    m2 = match(r"(?i)(?:Step|STEP)\s*5\s*[:\-]?\s*(\d+(?:\.\d+)?)", text)
    
    # Pattern 3: Fallback - look for "Score: X" anywhere (if Step 5 label is missing or far)
    m3 = match(r"(?i)Score\s*[:=]\s*(\d+(?:\.\d+)?)", text)
    
    m = m1 !== nothing ? m1 : (m2 !== nothing ? m2 : m3)
    
    if m !== nothing
        return clamp(parse(Float64, m.captures[1]) / 5.0, 0.0, 1.0)
    end
    return -1.0
end

# GPT Parser (Usually strict "Step 5: X")
function parse_score(::GPTParser, text::String)
    m = match(r"(?i)Step\s*5\s*:\s*(\d+(?:\.\d+)?)", text)
    if m !== nothing
        return clamp(parse(Float64, m.captures[1]) / 5.0, 0.0, 1.0)
    end
    # Fallback to robust if strict fails
    return parse_score(DefaultParser(), text)
end

function parse_evaluation_response(response_text::String, model_name::String)
    parser = get_parser(model_name)
    score = parse_score(parser, response_text)
    
    if score < 0
        # Show a snippet of the response for debugging
        snippet = length(response_text) > 200 ? first(response_text, 200) * "..." : response_text
        @warn "Parser ($(typeof(parser))) failed to find score.\nRaw response snippet:\n$snippet"
        return 0.0
    end
    return score
end

function evaluate_model_api_chained(system_prompt::String, templates::Dict, model_info::NamedTuple, model_name::String)
    # Common Data
    base_data = Dict(
        "model_name" => "Model ID $(model_info.id): $(model_info.model)",
        "reason" => model_info.reason,
        "claim" => "This model improves wake prediction accuracy by incorporating physical constraints.",
        "data" => "CFD Data: result_I0p3000_C22p0000.csv (High turbulence case)"
    )
    
    # --- Step 1: Logic Extraction ---
    user_content_1 = fill_template(templates["step1"], base_data)
    full_prompt_1 = "$(system_prompt)\n\n---\n\n$(user_content_1)"
    
    resp_1 = ""
    try
        r1 = GoogleGenAI.generate_content(API_KEY, model_name, full_prompt_1)
        resp_1 = r1.text
    catch e
        return (score=0.0, text="API Error Step 1: $e")
    end
    
    # --- Step 2: Physics Validation ---
    data_2 = copy(base_data)
    data_2["step1_result"] = resp_1
    user_content_2 = fill_template(templates["step2"], data_2)
    full_prompt_2 = "$(system_prompt)\n\n---\n\n$(user_content_2)"
    
    resp_2 = ""
    try
        r2 = GoogleGenAI.generate_content(API_KEY, model_name, full_prompt_2)
        resp_2 = r2.text
    catch e
        return (score=0.0, text="API Error Step 2: $e")
    end
    
    # --- Step 3: Scoring ---
    data_3 = Dict(
        "step1_result" => resp_1,
        "step2_result" => resp_2
    )
    user_content_3 = fill_template(templates["step3"], data_3)
    full_prompt_3 = "$(system_prompt)\n\n---\n\n$(user_content_3)"
    
    resp_3 = ""
    score = 0.0
    try
        r3 = GoogleGenAI.generate_content(API_KEY, model_name, full_prompt_3)
        resp_3 = r3.text
        score = parse_evaluation_response(resp_3, model_name)
    catch e
        return (score=0.0, text="API Error Step 3: $e")
    end
    
    # Combine outputs
    full_report = """
    --- Step 1: Logic ---
    $resp_1
    
    --- Step 2: Physics ---
    $resp_2
    
    --- Step 3: Score & Improvements ---
    $resp_3
    """
    
    return (score=score, text=full_report)
end

function main()
    args = parse_commandline()
    
    if isempty(API_KEY)
        println("Error: GOOGLE_API_KEY environment variable is not set.")
        exit(1)
    end
    
    gen = args["gen"]
    exp_name = args["exp-name"]
    model_name = args["model"]
    
    # Paths
    base_dir = joinpath("results", exp_name)
    feedback_path = joinpath(base_dir, "feedback_gen$gen.json")
    output_path = joinpath(base_dir, "evaluation_api_gen$gen.json")
    
    system_prompt_path = "templates/system_prompt.md"
    
    # Load Templates
    templates = Dict(
        "step1" => load_template("templates/task_step1.txt"),
        "step2" => load_template("templates/task_step2.txt"),
        "step3" => load_template("templates/task_step3.txt")
    )
    
    # Load inputs
    println("📂 Loading data...")
    if !isfile(feedback_path)
        error("Feedback file not found: $feedback_path")
    end
    
    json_data = JSON3.read(read(feedback_path, String))
    evaluated_models = json_data.evaluated_models
    
    system_prompt = load_template(system_prompt_path)
    
    println("🚀 Starting 3-Step Gemini API Evaluation for Generation $gen ($(length(evaluated_models)) models)")
    println("   Model: $model_name")
    println("   System Prompt: $system_prompt_path")
    println("-"^60)
    
    results = []
    
    for (i, m) in enumerate(evaluated_models)
        @printf "[%2d/%2d] Evaluating Model ID %d... " i length(evaluated_models) m.id
        
        # Handle key mismatch (some files use 'model', others 'formula')
        formula_str = haskey(m, :formula) ? m.formula : get(m, :model, "")
        
        m_nt = (id=m.id, model=formula_str, reason=m.reason)
        
        # Use Chained Evaluation
        eval_result = evaluate_model_api_chained(system_prompt, templates, m_nt, model_name)
        
        push!(results, Dict(
            "id" => m.id,
            "formula" => formula_str,
            "original_reason" => m.reason,
            "api_score" => eval_result.score,
            "api_evaluation" => eval_result.text
        ))
        
        @printf "Score: %.2f\n" eval_result.score
        
        sleep(2.0) # Increased delay for 3 calls per model
    end
    
    open(output_path, "w") do io
        JSON3.pretty(io, Dict("generation" => gen, "evaluations" => results))
    end
    
    println("-"^60)
    println("✅ Evaluation complete!")
    println("📄 Results saved to: $output_path")
end

main()
