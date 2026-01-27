module LoadData

using CSV, DataFrames

"""
    load_wake_csv(path::String)

CSV を読み込み、以下の処理を行う：
- 不要列 :divu を削除
- ΔU = 1 - u を計算
- r = y を作成
- 評価領域 (2 ≤ x ≤ 15, |r| < 6) でフィルタ
"""
function load_wake_csv(path::String)
    df = CSV.read(path, DataFrame)

    # divu を削除
    if :divu in names(df)
        select!(df, Not(:divu))
    end

    # ΔU と r を作成
    df.r = df.y
    df.deltaU = 1 .- df.u

    # 評価領域でフィルタ
    mask = (df.x .>= 2) .& (df.x .<= 15) .& (abs.(df.r) .< 6)
    df = df[mask, :]

    return df
end

end # module

