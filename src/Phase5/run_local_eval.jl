using .LoadData
using .Evaluator
using .OptimizeDE

# CSV を読み込む
df = LoadData.load_wake_csv("data/result_I0p3000_C22p0000.csv")

# 評価用データ（ベクトル）
x = df.x
r = df.r
k = df.k
omega = df.omega
nut = df.nut
deltaU = df.deltaU

"""
    evaluate_formula(model_str; num_coeffs=4, with_penalty=false)

LLM が出力した構造式 model_str を
DE に渡して係数最適化 → MSE/Score を返す。
"""
function evaluate_formula(model_str::String;
                          num_coeffs=4,
                          with_penalty=false)

    ex = Evaluator.parse_model_expression(model_str)

    if ex === nothing
        return (Inf, nothing)
    end

    θ_opt, score = OptimizeDE.optimize_coefficients(
        ex,
        x, r, k, omega, nut, deltaU;
        num_coeffs=num_coeffs,
        with_penalty=with_penalty
    )

    return score, θ_opt
end


# 動作テスト用
if abspath(PROGRAM_FILE) == @__FILE__
    model = "a * exp(-b*x) * (1 + c*r^2)^(-d)"
    score, θ = evaluate_formula(model)
    @show score
    @show θ
end

