module Evaluator

using Statistics
using Printf

export parse_model_expression,
       eval_model,
       mse_eval,
       physical_penalty,
       calculate_complexity

"""
    parse_model_expression(model_str::String)

Julia構文のモデル式（構造式）を Expr に変換する。
"""
function parse_model_expression(model_str::String)
    try
        return Meta.parse(model_str)
    catch e
        @error "Expression parse error" e
        return nothing
    end
end


"""
    eval_model(ex, θ, x, r, k, omega, nut)

構造式 ex と係数 θ から ΔU_model を評価する。
θ = [a,b,c,d,e,...] に対応。
"""
function eval_model(ex::Expr, θ, x, r, k, omega, nut)

    # 係数辞書
    localvars = Dict{Symbol,Any}()
    coeff_names = [:a, :b, :c, :d, :e, :f, :g, :h, :i]

    for (i, nm) in enumerate(coeff_names)
        if i > length(θ)
            break
        end
        localvars[nm] = θ[i]
    end

    # 変数をセット
    localvars[:x] = x
    localvars[:r] = r
    localvars[:k] = k
    localvars[:omega] = omega
    localvars[:nut] = nut

    # 評価
    # ベクトル化対応: 数式内の演算子や関数をドット演算子に変換する
    # 例: a * exp(-b*x) -> a .* exp.(-b .* x)
    
    function vectorize_expr(ex)
        if isa(ex, Expr)
            if ex.head == :call
                # 関数呼び出し (e.g. *, exp, +, ^) を broadcast に変換
                func = ex.args[1]
                args = map(vectorize_expr, ex.args[2:end])
                
                # Expr(:call, :broadcast, func, args...) を生成
                # これにより f(x) -> broadcast(f, x) -> f.(x) と等価になる
                return Expr(:call, :broadcast, func, args...)
            else
                # その他の式構造 (block, let, etc.) は再帰的に処理
                return Expr(ex.head, map(vectorize_expr, ex.args)...)
            end
        else
            # シンボルやリテラルはそのまま
            return ex
        end
    end
    
    vectorized_ex = vectorize_expr(ex)
    
    try
        # Expr(:let, assignments_block, body)
        assignments = Expr(:block, [:( $(k) = $(v) ) for (k,v) in localvars]...)
        return eval(Expr(:let, assignments, vectorized_ex))
    catch e
        @error "eval_model failed" e
        return fill(1e9, length(x))  # 失敗したら巨大値
    end
end


"""
    mse_eval(ex, θ, x, r, k, omega, nut, deltaU)

ΔU_model と ΔU_data の MSE を評価。
"""
function mse_eval(ex, θ, x, r, k, omega, nut, deltaU)
    ŷ = eval_model(ex, θ, x, r, k, omega, nut)
    
    # 安全性チェック: NaNやInfが含まれる場合はペナルティ
    if any(isnan, ŷ) || any(isinf, ŷ)
        return 1e9
    end
    
    # 巨大な値もペナルティ（オーバーフロー対策）
    if any(abs.(ŷ) .> 1e6)
        return 1e9
    end

    return mean((ŷ .- deltaU).^2)
end


"""
    physical_penalty(ex, θ, ...)

P1〜P4 のペナルティを計算。
必要に応じて改良可能。
"""
function physical_penalty(ex, θ, x, r, k, omega, nut, deltaU)

    ŷ = eval_model(ex, θ, x, r, k, omega, nut)

    # P1: 中心軸上の単調回復 (Monotonic Recovery)
    # r=0 において、xが増加するにつれて ΔU が減少（回復）すべき
    # 簡易チェック: xの最小値と最大値での値を比較
    # x_min, x_max での値を計算するために eval_model を再利用するのはコストが高いので
    # データセット内の x の並びを利用して、差分が正（増えている）の割合をペナルティとする
    # ただし、データはソートされていない可能性があるため、簡易的に ŷ の平均勾配を見る
    # ここではより厳密に、仮想的な点での評価を行う
    
    # 仮想的な x 点列 (r=0)
    x_test = [5.0, 10.0, 20.0, 50.0]
    r_test = zeros(length(x_test))
    # k, omega, nut は平均値を使用
    k_mean = mean(k)
    omega_mean = mean(omega)
    nut_mean = mean(nut)
    
    y_recovery = eval_model(ex, θ, x_test, r_test, fill(k_mean, 4), fill(omega_mean, 4), fill(nut_mean, 4))
    
    # 差分をとる (y[i+1] - y[i])。これが正なら（下流で増えているなら）ペナルティ
    diffs = diff(y_recovery)
    P1 = sum(max.(diffs, 0.0)) * 10.0 # 増加量に比例したペナルティ

    # P3: ΔU の非物理範囲 (0 < ΔU < 1)
    P3 = mean((ŷ .< 0) .* abs.(ŷ) .+ (ŷ .> 1) .* abs.(ŷ .- 1))

    # P4: 無限遠でのゼロ収束 (Asymptotic Decay)
    # x -> ∞, r -> ∞ で 0 になるべき
    x_inf = [1000.0]
    r_inf = [100.0]
    y_inf_x = eval_model(ex, θ, x_inf, [0.0], [k_mean], [omega_mean], [nut_mean])
    y_inf_r = eval_model(ex, θ, [10.0], r_inf, [k_mean], [omega_mean], [nut_mean])
    
    # 閾値 1e-3 を超えた分をペナルティ
    P4 = max(abs(y_inf_x[1]) - 1e-3, 0.0) + max(abs(y_inf_r[1]) - 1e-3, 0.0)

    # P5: 振幅係数(a)の符号チェック
    P5 = (θ[1] < 0) ? 1.0 : 0.0

    # 重み
    λ1 = 5.0   # 単調回復
    λ3 = 10.0  # 範囲
    λ4 = 50.0  # ゼロ収束 (定数項排除のため強めに)
    λ5 = 100.0 # 負の振幅

    P = λ1*P1 + λ3*P3 + λ4*P4 + λ5*P5
    return P
end

"""
    calculate_complexity(ex)

数式 ex の複雑性（ノード数 n0）を計算する。
再帰的に式木を探索し、演算子、変数、定数の総数をカウントする。
"""
function calculate_complexity(ex)
    if isa(ex, Expr)
        # 関数呼び出しや演算子の場合、引数の複雑性の和 + 1 (自分自身)
        return 1 + sum(calculate_complexity(arg) for arg in ex.args)
    elseif isa(ex, Symbol)
        # 変数や係数シンボル
        return 1
    elseif isa(ex, Number)
        # 数値リテラル
        return 1
    else
        # その他
        return 1
    end
end

end # module

