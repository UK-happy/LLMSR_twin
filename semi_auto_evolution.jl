#!/usr/bin/env julia

"""
Semi-Automated Evolution Script

LLMとの協働で進化計算を実行するメインスクリプト

使用方法:
    # 初期集団生成（世代0）
    julia --project=. semi_auto_evolution.jl --generate-initial --size 20
    
    # 世代Nの評価
    julia --project=. semi_auto_evolution.jl --evaluate N --input results/models_genN.json
"""

using ArgParse
using Printf

# プロジェクトのsrcディレクトリを読み込み
push!(LOAD_PATH, joinpath(@__DIR__, "src"))

include("src/Phase5/Phase5.jl")
include("src/evolution_utils.jl")

using .Phase5
using .EvolutionUtils
using Statistics

# コマンドライン引数のパース
function parse_commandline()
    s = ArgParseSettings(
        description = "Semi-Automated Evolution for Wake Model Discovery"
    )
    
    @add_arg_table! s begin
        "--generate-initial"
            help = "Generate initial population feedback"
            action = :store_true
        "--size"
            help = "Population size for initial generation"
            arg_type = Int
            default = 20
        "--evaluate"
            help = "Evaluate generation N"
            arg_type = Int
            default = -1
        "--input"
            help = "Input JSON file with LLM-generated models"
            arg_type = String
            default = ""
        "--csv-path"
            help = "Path to CFD data CSV"
            arg_type = String
            default = "data/result_I0p3000_C22p0000.csv"
        "--exp-name"
            help = "Experiment name (creates results/{exp_name}/)"
            arg_type = String
            default = "default"
        "--seeds-file"
            help = "Path to seeds JSON file"
            arg_type = String
            default = "seeds.json"
    end
    
    return parse_args(s)
end


"""
    generate_initial(size::Int, exp_name::String, seeds_file::String)

初期集団（世代0）のフィードバックを生成
"""
function generate_initial(size::Int, exp_name::String, seeds_file::String)
    println("\n" * "="^70)
    println("🌱 Generating Initial Population Feedback (Generation 0)")
    println("="^70)
    
    # resultsディレクトリ作成
    base_dir = joinpath("results", exp_name)
    mkpath(base_dir)
    mkpath(joinpath(base_dir, "plots"))

    # シードモデルの読み込み
    seeds = EvolutionUtils.load_seeds(seeds_file)
    if !isempty(seeds)
        println("   ✓ Loaded $(length(seeds)) seed models from $seeds_file")
        println("   ℹ️  Using these seeds to initialize the population.")
    else
        println("   ℹ️  No seeds loaded (starting fresh)")
    end
    
    # 初期フィードバック生成
    feedback_path = joinpath(base_dir, "feedback_gen0.json")
    EvolutionUtils.generate_initial_feedback(size, feedback_path; seeds=seeds)
    
    println("\n✅ Initial feedback generated!")
    println("\n📋 Next steps:")
    println("   1. View feedback: cat $feedback_path")
    println("   2. Give the feedback to Gemini LLM")
    println("   3. Save Gemini's response to: $(joinpath(base_dir, "models_gen1.json"))")
    println("   4. Run: julia --project=. semi_auto_evolution.jl --evaluate 1 --input $(joinpath(base_dir, "models_gen1.json")) --exp-name $exp_name")
    println()
end

"""
    evaluate_generation(gen::Int, input_file::String, csv_path::String, exp_name::String)

指定世代のモデルを評価
"""
function evaluate_generation(gen::Int, input_file::String, csv_path::String, exp_name::String)
    println("\n" * "="^70)
    println("🔬 Evaluating Generation $gen")
    println("="^70)
    
    # モデルの読み込み
    println("\n📂 Loading models from: $input_file")
    models = EvolutionUtils.load_models(input_file)
    
    if isempty(models)
        error("No models found in input file!")
    end
    
    # Load prompt template
    template_path = "templates/phase5_prompt.md"
    if !isfile(template_path)
        # Fallback for backward compatibility if renamed
        if isfile("templates/llm_prompt_template.md")
             template_path = "templates/llm_prompt_template.md"
        else
             error("Prompt template not found: $template_path")
        end
    end
    prompt_template = read(template_path, String)
    println("\n⚙️  Evaluating models...")
    evaluated = []
    
    for (i, m) in enumerate(models)
        @printf "   [%2d/%2d] " i length(models)
        print("$(m.model[1:min(40, length(m.model))])... ")
        
        try
            score, θ = Phase5.evaluate_formula(
                m.model;
                num_coeffs=m.num_coeffs,
                with_penalty=true,
                csv_path=csv_path
            )
            
            if θ !== nothing && !isinf(score) && !isnan(score)
                push!(evaluated, (
                    id = m.id,
                    model = m.model,
                    score = score,
                    coeffs = θ,
                    reason = m.reason,
                    ep_type = m.ep_type,
                    parent_generation = m.parent_generation,
                    parent_id = m.parent_id
                ))
                @printf "✓ Score: %.6f\n" score
            else
                println("✗ Failed")
            end
        catch e
            println("✗ Error: $(typeof(e))")
        end
    end
    
    if isempty(evaluated)
        error("All models failed evaluation!")
    end
    
    println("\n   ✓ Successfully evaluated: $(length(evaluated))/$(length(models)) models")
    
    # 結果をソート
    sort!(evaluated, by=x->x.score)
    
    # 統計表示
    println("\n" * "="^70)
    println("📊 Generation $gen Statistics")
    println("="^70)
    println("   Population size: $(length(evaluated))")
    @printf "   Best score:      %.6f\n" evaluated[1].score
    @printf "   Median score:    %.6f\n" median([m.score for m in evaluated])
    @printf "   Mean score:      %.6f\n" mean([m.score for m in evaluated])
    @printf "   Worst score:     %.6f\n" evaluated[end].score
    
    # トップ3モデルを表示
    println("\n🏆 Top 3 Models:")
    println("-"^70)
    for (i, m) in enumerate(evaluated[1:min(3, length(evaluated))])
        println("\n[$i] Score: $(round(m.score, digits=6))")
        println("    Formula: $(m.model)")
        println("    Coeffs: $(round.(m.coeffs, digits=4))")
        if !isempty(m.reason)
            println("    Reason: $(m.reason)")
        end
    end
    
    # フィードバックJSON保存
    base_dir = joinpath("results", exp_name)
    feedback_path = joinpath(base_dir, "feedback_gen$gen.json")
    EvolutionUtils.save_feedback(gen, evaluated, feedback_path)
    
    # 履歴ログに追記
    history_path = joinpath(base_dir, "history.jsonl")
    EvolutionUtils.append_history(gen, evaluated, history_path)
    
    # 次のステップを表示
    next_gen = gen + 1
    println("\n" * "="^70)
    println("✅ Evaluation Complete!")
    println("="^70)
    println("\n📋 Next steps:")
    println("   1. View feedback: cat $feedback_path")
    println("   2. Give the feedback to Gemini LLM")
    println("   3. Save Gemini's response to: $(joinpath(base_dir, "models_gen$next_gen.json"))")
    println("   4. Run: julia --project=. semi_auto_evolution.jl --evaluate $next_gen --input $(joinpath(base_dir, "models_gen$next_gen.json")) --exp-name $exp_name")
    println("\n💡 To visualize progress: julia --project=. visualize_evolution.jl --exp-name $exp_name")
    println()
end

# メイン処理
function main()
    args = parse_commandline()
    
    if args["generate-initial"]
        # 初期集団生成
        generate_initial(args["size"], args["exp-name"], args["seeds-file"])
        
    elseif args["evaluate"] > 0
        # 世代の評価
        input_file = args["input"]
        if isempty(input_file)
            # inputが指定されていない場合はデフォルトパスを生成
            # results/{exp_name}/models_gen{gen}.json
            input_file = joinpath("results", args["exp-name"], "models_gen$(args["evaluate"]).json")
            println("ℹ️  Input file not specified. Using default: $input_file")
        end
        
        evaluate_generation(
            args["evaluate"],
            input_file,
            args["csv-path"],
            args["exp-name"]
        )
        
    else
        println("Error: Either --generate-initial or --evaluate must be specified")
        println("Run with --help for usage information")
        exit(1)
    end
end

# 実行
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
