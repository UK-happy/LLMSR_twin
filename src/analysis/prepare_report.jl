using JSON3
using Dates
using Statistics
using ArgParse
using Printf

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--exp-name"
            help = "Experiment name"
            arg_type = String
            default = "default"
    end
    return parse_args(s)
end

function load_history(filepath)
    history = []
    if isfile(filepath)
        for line in eachline(filepath)
            push!(history, JSON3.read(line))
        end
    end
    return history
end

function load_benchmark(filepath)
    if isfile(filepath)
        return read(filepath, String)
    end
    return "Benchmark not run yet."
end

function main()
    args = parse_commandline()
    exp_name = args["exp-name"]
    
    base_dir = joinpath("results", exp_name)
    history_path = joinpath(base_dir, "history.jsonl")
    benchmark_path = joinpath(base_dir, "plots", "benchmark_summary.txt")
    output_path = joinpath(base_dir, "report_context.md")
    
    println("📝 Preparing report context for experiment: $exp_name")
    
    # Load data
    history = load_history(history_path)
    benchmark_text = load_benchmark(benchmark_path)
    
    if isempty(history)
        println("❌ No history found at $history_path")
        return
    end
    
    # Analyze history
    best_initial = history[1].best_score
    best_final = history[end].best_score
    improvement = (best_initial - best_final) / best_initial * 100
    
    best_model_final = history[end].best_model
    
    # Generate Context Markdown
    open(output_path, "w") do io
        println(io, "# Experiment Report Context: $exp_name")
        println(io, "")
        println(io, "## 1. Overview")
        println(io, "- **Date**: $(Dates.now())")
        println(io, "- **Total Generations**: $(length(history))")
        println(io, "- **Initial Best Score**: $(@sprintf("%.6f", best_initial))")
        println(io, "- **Final Best Score**: $(@sprintf("%.6f", best_final))")
        println(io, "- **Improvement**: $(@sprintf("%.2f", improvement))%")
        println(io, "")
        
        println(io, "## 2. Best Model Discovered")
        println(io, "### Formula")
        println(io, "```julia")
        println(io, best_model_final.formula)
        println(io, "```")
        println(io, "")
        println(io, "### Coefficients")
        println(io, "```julia")
        println(io, best_model_final.coefficients)
        println(io, "```")
        println(io, "")
        println(io, "### Reason (LLM)")
        println(io, "> $(best_model_final.reason)")
        println(io, "")
        
        println(io, "## 3. Evolution History")
        println(io, "| Gen | Best Score | Mean Score | Best Formula (Truncated) |")
        println(io, "|---|---|---|---|")
        for h in history
            f_trunc = length(h.best_model.formula) > 40 ? h.best_model.formula[1:37] * "..." : h.best_model.formula
            println(io, "| $(h.generation) | $(@sprintf("%.6f", h.best_score)) | $(@sprintf("%.6f", h.mean_score)) | `$(f_trunc)` |")
        end
        println(io, "")
        
        println(io, "## 4. Benchmark Results")
        println(io, "```")
        println(io, benchmark_text)
        println(io, "```")
        println(io, "")
        
        println(io, "## 5. Instructions for Report Generation")
        println(io, "以下のデータを基に、包括的な技術レポートを**日本語で**作成してください。")
        println(io, "レポートには以下を含めてください：")
        println(io, "1. **エグゼクティブサマリー**: 主な発見と性能改善。")
        println(io, "2. **方法論**: 進化プロセスの簡単な説明。")
        println(io, "3. **結果分析**: 進化の傾向と最終モデルの構造についての議論。")
        println(io, "4. **物理的解釈**: ベストモデルの各項の物理的意味（TKEの影響、減衰率など）の説明。")
        println(io, "5. **比較**: ベンチマーク結果に基づく標準モデル（Jensen, Bastankhah）との比較。")
        println(io, "6. **結論**: 最終的な考察と今後の推奨事項。")
    end
    
    println("✅ Report context generated: $output_path")
    println("📋 Copy the content of this file and paste it to the LLM to generate the final report.")
end

main()
