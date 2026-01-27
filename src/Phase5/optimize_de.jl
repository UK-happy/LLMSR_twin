module OptimizeDE

using BlackBoxOptim

export optimize_coefficients

"""
    log_uniform_init(lower, upper, num_coeffs, NP)

log-uniform 初期化を行う。
"""
function log_uniform_init(lower, upper, num_coeffs, NP)
    return [exp(rand() * (log(upper) - log(lower)) + log(lower))
            for _ in 1:NP, _ in 1:num_coeffs]
end


"""
    signed_log_uniform_init(lower, upper, num_coeffs, NP)

正負の領域にまたがる場合、対数一様分布に従って絶対値を生成し、符号をランダムに割り当てる。
"""
function signed_log_uniform_init(lower, upper, num_coeffs, NP)
    # 絶対値の最小・最大を設定（0付近の探索のため最小値を小さく）
    abs_min = 1e-4
    abs_max = max(abs(lower), abs(upper))
    
    pop = zeros(NP, num_coeffs)
    for i in 1:NP
        for j in 1:num_coeffs
            # 対数一様分布で絶対値を生成
            val = exp(rand() * (log(abs_max) - log(abs_min)) + log(abs_min))
            
            # 符号を決定（範囲内に収まるように）
            # lower < 0 < upper の場合、ランダムに符号反転
            if lower < 0 && upper > 0
                if rand() < 0.5
                    val = -val
                end
            elseif upper < 0
                val = -val
            end
            
            # 範囲外なら範囲内にクリップ（念のため）
            val = clamp(val, lower, upper)
            pop[i, j] = val
        end
    end
    return pop
end


"""
    optimize_coefficients(ex, x, r, k, omega, nut, deltaU;
                          num_coeffs=4, with_penalty=false,
                          mse_eval=nothing, physical_penalty=nothing,
                          search_range=(1e-4, 1e2))

DE により係数 θ を最適化する。
評価関数は引数として受け取る。
"""
function optimize_coefficients(ex,
                               x, r, k, omega, nut, deltaU;
                               num_coeffs=4,
                               with_penalty=false,
                               mse_eval=nothing,
                               physical_penalty=nothing,
                               search_range=(1e-4, 1e2))

    # 最適化対象の目的関数
    f(θ) = begin
        mse = mse_eval(ex, θ, x, r, k, omega, nut, deltaU)
        if with_penalty
            mse += physical_penalty(ex, θ, x, r, k, omega, nut, deltaU)
        end
        return mse
    end

    # 初期集団
    NP = 30
    lower, upper = search_range
    
    # 範囲に応じて初期化戦略を選択
    if lower < 0 && upper > 0
        # ゼロを跨ぐ場合：Signed Log-Uniform
        init_pop = signed_log_uniform_init(lower, upper, num_coeffs, NP)
    elseif lower < 0
        # 全て負の場合：負のLog-Uniform (signed_log_uniform_initで処理可能)
        init_pop = signed_log_uniform_init(lower, upper, num_coeffs, NP)
    else
        # 全て正の場合：通常のLog-Uniform
        safe_lower = max(lower, 1e-6)
        init_pop = log_uniform_init(safe_lower, upper, num_coeffs, NP)
    end

    # DE 最適化
    res = bboptimize(
        f;
        SearchRange=search_range,
        NumDimensions=num_coeffs,
        InitPopulation=init_pop,
        PopulationSize=NP,
        MaxSteps=200,
        Method=:de_rand_1_bin,
        F=0.7,
        CR=0.9,
        TraceMode=:silent
    )

    return best_candidate(res), best_fitness(res)
end

end # module

