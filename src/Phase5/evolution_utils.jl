"""
Evolution Utilities for Semi-Automated LLM-driven Model Discovery

進化計算の補助機能：
- JSON形式でのデータ保存・読み込み
- LLMへのフィードバック生成
- 履歴管理（JSONL形式）
- 多様性指標の計算
"""
module EvolutionUtils

using JSON3
using Statistics
using Dates

export save_feedback, load_models, append_history, calculate_diversity,
       generate_initial_feedback, format_model_for_display, select_diverse_elites

"""
    save_feedback(generation::Int, evaluated::Vector, filepath::String)

評価結果をJSON形式で保存（LLMに渡す用）

# Arguments
- `generation`: 現在の世代番号
- `evaluated`: 評価済みモデルのVector（各要素は (model, score, coeffs, reason) のNamedTuple）
- `filepath`: 保存先ファイルパス
"""
function save_feedback(generation::Int, evaluated::Vector, filepath::String; template_content::String="")
    # スコアでソート
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
        "diverse_elites" => [
            Dict(
                "id" => m.id,
                "formula" => m.model,
                "score" => m.score,
                "coefficients" => m.coeffs
            )
            for m in select_diverse_elites(evaluated, 3; similarity_threshold=0.8)
        ],
        "statistics" => Dict(
            "best_score" => sorted[1].score,
            "worst_score" => sorted[end].score,
            "mean_score" => mean([m.score for m in sorted]),
            "median_score" => median([m.score for m in sorted]),
            "population_size" => length(sorted)
        )
    )

    # JSON保存
    open(filepath, "w") do io
        JSON3.write(io, feedback)
    end

    @info "Feedback saved to: $filepath"

    # プロンプトファイルの生成 (オプション)
    if !isempty(template_content)
        try
            # 次世代番号
            next_gen = generation + 1

            # テンプレートセクションの選択と構築
            # 1. システムプロンプト
            system_prompt = extract_section(template_content, "## システムプロンプト")

            # 2. 世代別指示
            gen_instruction = extract_section(template_content, "### 世代2以降")

            # 3. 追加セクション（エラー、フォーマット、参考知識、進化戦略）
            strategy_section = extract_section(template_content, "## 2. 進化戦略（厳守）")
            common_errors = extract_section(template_content, "## ⚠️ よくあるエラーと修正")
            output_format = extract_section(template_content, "## 📝 出力フォーマットの厳守")
            ref_knowledge = extract_section(template_content, "## 7. 参考知識")

            # プロンプトの組み立て
            # 順番: System -> Gen Instruction -> Strategy -> Special(if any) -> Common Errors -> Output Format -> Ref Knowledge
            prompt_parts = [system_prompt, gen_instruction]

            if !isempty(strategy_section)
                push!(prompt_parts, "---", strategy_section)
            end

            if next_gen >= 16
                special_instruction = extract_section(template_content, "### 後期世代")
                push!(prompt_parts, "---", special_instruction)
            end

            # 共通セクションの追加
            push!(prompt_parts, "---", common_errors, "---", output_format, "---", ref_knowledge)

            prompt_text = join(prompt_parts, "\n\n")

            # 変数置換
            prompt_text = replace(prompt_text, "{N}" => generation)
            prompt_text = replace(prompt_text, "{N+1}" => next_gen)

            # ベストモデル情報の埋め込み
            if sorted[1].score < Inf
                best_formula = sorted[1].model
                best_score = sorted[1].score
                prompt_text = replace(prompt_text, "{best_formula}" => best_formula)
                prompt_text = replace(prompt_text, "{best_score}" => best_score)
            end

            # JSON埋め込み
            json_str = JSON3.write(feedback)
            placeholder_regex = r"【feedback_gen.*?\.json の内容を提示】"
            if occursin(placeholder_regex, prompt_text)
                prompt_text = replace(prompt_text, placeholder_regex => "\n```json\n" * json_str * "\n```\n")
            elseif !isempty(gen_instruction)
                 prompt_text = replace(prompt_text, gen_instruction => gen_instruction * "\n\n```json\n" * json_str * "\n```\n")
            else
                 # Fallback: append
                 prompt_text = prompt_text * "\n\n```json\n" * json_str * "\n```\n"
            end

            # プロンプトファイル保存
            dir_path = dirname(filepath)
            prompt_path = joinpath(dir_path, "prompt_gen$(next_gen).txt")
            write(prompt_path, prompt_text)

            @info "Next generation prompt saved to: $prompt_path"

        catch e
            @warn "Failed to generate prompt file: $e"
        end
    end

    return feedback
end


"""
    load_models(filepath::String)

LLMが生成したモデルをJSONファイルから読み込む

# Returns
Vector of NamedTuple with fields: model, num_coeffs, reason, ep_type
"""
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


"""
    append_history(generation::Int, evaluated::Vector, filepath::String)

評価結果を履歴ログに追記（JSONL形式：1行1世代）

各行は完全なJSON objectで、後から解析可能
"""
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
                "coefficients" => m.coeffs,
                "reason" => get(m, :reason, ""),
                "ep_type" => get(m, :ep_type, ""),
                "parent_generation" => get(m, :parent_generation, nothing),
                "parent_id" => get(m, :parent_id, nothing)
            )
            for m in sorted
        ]
    )

    # JSONL形式で追記
    open(filepath, "a") do io
        JSON3.write(io, history_entry)
        write(io, "\n")
    end

    @info "History updated: Generation $generation"
end


"""
    levenshtein(s1, s2)

2つの文字列間のレーベンシュタイン距離を計算する。
"""
function levenshtein(s1::AbstractString, s2::AbstractString)
    a, b = s1, s2
    if length(a) < length(b)
        a, b = b, a
    end
    if length(b) == 0
        return length(a)
    end

    previous_row = collect(0:length(b))
    current_row = similar(previous_row)

    for (i, c1) in enumerate(a)
        current_row[1] = i
        for (j, c2) in enumerate(b)
            insertions = previous_row[j+1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row[j+1] = min(insertions, deletions, substitutions)
        end
        previous_row .= current_row
    end

    return previous_row[end]
end

"""
    select_diverse_elites(models::Vector, n::Int; similarity_threshold=0.2)

多様性を考慮して上位 n 個のエリートモデルを選抜する。
1. スコア順にソート。
2. 最良モデルは必ず選抜。
3. 次の候補モデルが、既に選抜されたモデルと「似すぎていない」場合のみ選抜。
   類似度 = 1 - (距離 / 長い方の長さ) > threshold なら似ていると判定。
"""
function select_diverse_elites(models::Vector, n::Int; similarity_threshold=0.8)
    sorted = sort(models, by=x->x.score)
    elites = []

    if isempty(sorted)
        return elites
    end

    # 1位は無条件採用
    push!(elites, sorted[1])

    current_idx = 2
    while length(elites) < n && current_idx <= length(sorted)
        candidate = sorted[current_idx]
        is_diverse = true

        for elite in elites
            s1 = replace(elite.model, " " => "") # 空白除去して比較
            s2 = replace(candidate.model, " " => "")
            dist = levenshtein(s1, s2)
            max_len = max(length(s1), length(s2))
            similarity = 1.0 - (dist / max_len)

            if similarity > similarity_threshold
                is_diverse = false
                break
            end
        end

        if is_diverse
            push!(elites, candidate)
        end
        current_idx += 1
    end

    # もし多様なモデルが足りなければ、スコア順で埋める
    if length(elites) < n
        remaining_needed = n - length(elites)
        # 既に選ばれたIDを除外
        selected_ids = Set([m.id for m in elites])

        for m in sorted
            if !(m.id in selected_ids)
                push!(elites, m)
                if length(elites) >= n
                    break
                end
            end
        end
    end

    return elites
end

"""
    calculate_diversity(models::Vector)

集団の多様性を計算（式の文字列の編集距離ベース）

簡易実装：ユニークな式のパターン数 / 総数
"""
function calculate_diversity(models::Vector)
    formulas = [m.model for m in models]
    unique_count = length(unique(formulas))
    total_count = length(formulas)

    return unique_count / total_count
end


"""
    parse_template(content::String, section_header::String)

指定されたヘッダー（例: "### 世代1"）から次のヘッダーまでのセクションを抽出する。
システムプロンプト（"## システムプロンプト"）は常に追加する。
"""
function parse_template(content::String, section_header::String)
    # システムプロンプトの抽出
    system_prompt = extract_section(content, "## システムプロンプト")

    # セクションの抽出
    section_content = extract_section(content, section_header)

    return strip(system_prompt * "\n\n" * strip(section_content))
end

"""
    extract_section(content::String, section_header::String)

指定されたヘッダーから次の同レベル（またはそれ以上）のヘッダーまでのセクションを抽出する。
"""
function extract_section(content::String, section_header::String)
    # ヘッダーを探す
    r = findfirst(section_header, content)
    if r === nothing
        return ""
    end

    # セクション内容の開始位置（ヘッダーの直後）
    header_end = last(r)
    if header_end >= ncodeunits(content)
        return ""
    end
    content_start = nextind(content, header_end)

    # 次のヘッダーを探すためのパターン作成
    m = match(r"^(#+)", section_header)
    level_hashes = m === nothing ? "##" : m.captures[1]
    # 次のヘッダーは "\n" + hashes + " "
    pat = Regex("\n" * level_hashes * " ")

    # content_start 以降で次のヘッダーを探す
    next_node = findnext(pat, content, content_start)

    if next_node !== nothing
        # 次のヘッダーの直前まで抽出
        # next_node[1] は "\n" の位置なので、その前まで
        content_end = prevind(content, first(next_node))
        return strip(content[content_start:content_end])
    else
        return strip(content[content_start:end])
    end
end

"""
    generate_initial_feedback(size::Int, filepath::String; seeds::Vector{Dict}=Dict[], template_content::String="")

初期集団（世代0）用のフィードバックを生成
テンプレートが提供された場合はそれを使用し、なければデフォルト（ハードコード）を使用。
"""
function generate_initial_feedback(size::Int, filepath::String; seeds::Vector=Dict[], template_content::String="")

    seed_text = ""
    if !isempty(seeds)
        seed_text = """

        【過去の成功モデル（シード）】
        以下のモデルは過去の実験で高い性能を示しました。これらを初期集団の一部として含めるか、これらを改良したモデルを生成してください。

        """
        for (i, seed) in enumerate(seeds)
            seed_formula = get(seed, :formula, get(seed, "formula", ""))
            seed_score = get(seed, :score, get(seed, "score", 0.0))
            seed_text *= "- Seed $i: $(seed_formula) (Score: $(seed_score))\n"
        end
    end

    instructions = ""
    if !isempty(template_content)
        # テンプレートから "世代1" 用のプロンプトを構築
        # プレースホルダー {{SEEDS}} があれば置換、なければ末尾に追加
        # 注: テンプレートファイルの構造に依存

        try
            # セクション抽出
            system_prompt = extract_section(template_content, "## システムプロンプト")
            gen1_instruction = extract_section(template_content, "### 世代1")
            common_errors = extract_section(template_content, "## ⚠️ よくあるエラーと修正")
            output_format = extract_section(template_content, "## 📝 出力フォーマットの厳守")
            ref_knowledge = extract_section(template_content, "## 7. 参考知識")

            # プロンプト組み立て
            prompt_parts = [system_prompt, gen1_instruction, "---", common_errors, "---", output_format, "---", ref_knowledge]
            instructions = join(prompt_parts, "\n\n")

            # 変数置換 (簡易テンプティング)
            instructions = replace(instructions, "{size}" => size) # もしあれば

            # シードの注入
            if occursin("{{SEEDS}}", instructions)
                instructions = replace(instructions, "{{SEEDS}}" => seed_text)
            else
                # プレースホルダーがない場合は、世代1指示の中に追加
                instructions = replace(instructions, gen1_instruction => gen1_instruction * "\n" * seed_text)
            end

            @info "Using provided template for instructions."
        catch e
            @warn "Failed to parse template: $e. Falling back to default."
            instructions = ""
        end
    end

    # フォールバック（テンプレートがない、または失敗した場合は従来のハードコード）
    if isempty(instructions)
        instructions = """
        風車後流の速度欠損 ΔU(x, r) を記述する代数式を $(size)個生成してください。

        【利用可能な変数】
        - x: 下流距離（正規化済み）
        - r: 半径方向距離（正規化済み）
        - k: 乱流運動エネルギー
        - omega: 比散逸率
        - nut: 渦粘性係数

        【係数表記ルール】
        - 係数は a, b, c, d, e, f, g, ... を使用（順番通り）
        - 数値は入れず、記号のみで表現
        - Julia構文で記述（例: exp(-b*x), r^2, sqrt(k)）

        【物理的制約】
        - x が大きくなると ΔU は減衰すること（例: exp(-b*x)）
        - r 方向は対称であること（例: r^2, abs(r)）
        - 負の速度欠損は非物理的

        【多様性】
        以下のような異なるアプローチを含めてください：
        - Gaussian型: exp(-b*x) * exp(-c*r^2)
        - べき乗型: x^(-b) * (1 + c*r^2)^(-d)
        - 乱流項含む: ... * (1 + e*k) または ... * (1 + e*nut)
        - 複合型: 複数の効果を組み合わせ
        $(seed_text)

        【出力形式】
        以下のJSON形式で出力してください：
        {
          "generation": 1,
          "models": [
            {
              "id": 1,
              "formula": "a * exp(-b*x) * exp(-c*r^2)",
              "num_coeffs": 3,
              "reason": "Classic Gaussian profile",
              "ep_type": "EP1"
            },
            ...
          ]
        }
        """
    end

    feedback = Dict(
        "generation" => 0,
        "timestamp" => string(now()),
        "request" => "initial_population",
        "population_size" => size,
        "instructions" => instructions
    )

    open(filepath, "w") do io
        JSON3.write(io, feedback)
    end

    @info "Initial feedback generated: $filepath"
    println("\n" * "="^60)
    println("📝 初期集団生成の準備完了")
    println("="^60)
    println("\n次のステップ：")
    println("1. $filepath をGeminiに提示")
    println("2. 生成された式を results/models_gen1.json に保存")
    println("3. julia --project=. semi_auto_evolution.jl --evaluate 1 --input results/models_gen1.json")
    println()
end


"""
    format_model_for_display(model::NamedTuple)

モデルを読みやすい形式で表示
"""
function format_model_for_display(model::NamedTuple)
    println("Formula: $(model.model)")
    println("Score: $(round(model.score, digits=6))")
    println("Coefficients: $(round.(model.coeffs, digits=4))")
    if haskey(model, :reason) && !isempty(model.reason)
        println("Reason: $(model.reason)")
    end
    if haskey(model, :ep_type) && !isempty(model.ep_type)
        println("EP Type: $(model.ep_type)")
    end
end

"""
    load_seeds(filepath::String)

シードモデルをJSONファイルから読み込む。
ファイルが存在しない場合は空の配列を返す。
"""
function load_seeds(filepath::String)
    if !isfile(filepath)
        @warn "Seeds file not found: $filepath. Starting with empty seeds."
        return Dict[]
    end

    try
        data = JSON3.read(read(filepath, String))
        # JSON3.Array -> Vector{Dict} 変換
        return [Dict(pairs(item)) for item in data]
    catch e
        @error "Failed to load seeds from $filepath" e
        return Dict[]
    end
end

"""
    update_seeds(filepath::String, new_model::Dict)

新しい高性能モデルをシードファイルに追加・更新する。
同じ式が既に存在する場合はスコアが良い方を保持する。
"""
function update_seeds(filepath::String, new_model::Dict)
    seeds = load_seeds(filepath)

    # 既存の式と比較
    existing_idx = findfirst(s -> replace(s["formula"], " " => "") == replace(new_model["formula"], " " => ""), seeds)

    updated = false
    if existing_idx !== nothing
        # 既存の方がスコアが悪い（大きい）場合のみ更新
        if new_model["score"] < seeds[existing_idx]["score"]
            seeds[existing_idx] = new_model
            updated = true
            @info "Updated existing seed with better score."
        end
    else
        # 新規追加
        push!(seeds, new_model)
        updated = true
        @info "Added new seed model."
    end

    if updated
        # スコア順にソートして保存
        sort!(seeds, by=x->x["score"])

        # 上位10個程度に絞る（オプション）
        if length(seeds) > 10
            seeds = seeds[1:10]
        end

        open(filepath, "w") do io
            JSON3.write(io, seeds)
        end
        @info "Seeds file updated: $filepath"
    end
end

end # module EvolutionUtils
