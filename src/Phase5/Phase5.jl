"""
Phase5 - Wind Turbine Wake Model Discovery using LLM + Evolutionary Search

メインモジュール：全サブモジュールを統合し、LLMが生成した構造式を評価する機能を提供
"""
module Phase5

using CSV, DataFrames
using BlackBoxOptim
using Statistics
using Printf

# サブモジュールを正しい順序でinclude
include("load_data.jl")
include("evaluator.jl")
include("optimize_de.jl")

# サブモジュールを使用可能にする
using .LoadData
using .Evaluator
using .OptimizeDE

# 公開する関数をexport
export evaluate_formula, load_wake_data

# グローバルデータ（一度だけ読み込む）
const DATA_LOADED = Ref(false)
const WAKE_DATA = Ref{DataFrame}()

"""
    load_wake_data(csv_path::String)

CFDの後流データを読み込む。
一度読み込んだデータはキャッシュされる。
"""
function load_wake_data(csv_path::String)
    if !DATA_LOADED[]
        @info "Loading wake data from: $csv_path"
        WAKE_DATA[] = LoadData.load_wake_csv(csv_path)
        DATA_LOADED[] = true
        @info "Data loaded: $(size(WAKE_DATA[])) rows"
    end
    return WAKE_DATA[]
end


"""
    evaluate_formula(model_str::String; num_coeffs=4, with_penalty=false, csv_path="data/result_I0p3000_C22p0000.csv")

LLM が生成した構造式 model_str を評価する。

# Arguments
- `model_str::String`: Julia形式の構造式（例: "a * exp(-b*x) * (1 + c*r^2)^(-d)"）
- `num_coeffs::Int`: 係数の数（デフォルト: 4）
- `with_penalty::Bool`: 物理性ペナルティを含めるか（デフォルト: false）
- `csv_path::String`: データファイルのパス

# Returns
- `(score, θ_opt)`: スコア（MSEまたはMSE+Penalty）と最適係数のタプル

# Example
```julia
model = "a * exp(-b*x) * (1 + c*r^2)^(-d)"
score, θ = evaluate_formula(model; num_coeffs=4)
println("Score: ", score)
println("Coefficients: ", θ)
```
"""
function evaluate_formula(model_str::String;
                          num_coeffs::Int=4,
                          with_penalty::Bool=false,
                          csv_path::String="data/result_I0p3000_C22p0000.csv")
    
    # データを読み込む（初回のみ）
    df = load_wake_data(csv_path)
    
    # 評価用データを抽出
    x = df.x
    r = df.r
    k = df.k
    omega = df.omega
    nut = df.nut
    deltaU = df.deltaU
    
    # 構造式をパース
    ex = Evaluator.parse_model_expression(model_str)
    
    if ex === nothing
        @error "Failed to parse model expression: $model_str"
        return (Inf, nothing)
    end
    
    # DE による係数最適化
    try
        θ_opt, score = OptimizeDE.optimize_coefficients(
            ex,
            x, r, k, omega, nut, deltaU;
            num_coeffs=num_coeffs,
            with_penalty=with_penalty,
            mse_eval=Evaluator.mse_eval,
            physical_penalty=Evaluator.physical_penalty,
            search_range=(-100.0, 100.0)
        )
        
        # 複雑性ペナルティ f3 の計算
        n0 = Evaluator.calculate_complexity(ex)
        if n0 <= 80
            f3 = sqrt(n0 + 1000) / sqrt(1001)
        else
            f3 = sqrt(n0^2 + 910) / sqrt(1001)
        end
        
        # 最終スコア = (MSE + Penalty) * f3
        # score には既に MSE (+ Penalty) が含まれている
        final_score = score * f3
        
        return (final_score, θ_opt)
    catch e
        @error "Optimization failed" exception=(e, catch_backtrace())
        return (Inf, nothing)
    end
end

end # module Phase5
