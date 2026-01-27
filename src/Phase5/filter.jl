using CSV, DataFrames

println("=== Loading result_I0p3000_C22p0000.csv ===")

# プロジェクトルートからの相対パス
data_path = joinpath(@__DIR__, "..", "data", "result_I0p3000_C22p0000.csv")
df = CSV.read(data_path, DataFrame)

println("Loaded. Columns:")
@show names(df)

# ---- 必須列チェック ----
required_cols = [:x, :y, :u]

for c in required_cols
    if !hasproperty(df, c)
        error("ERROR: required column $c not found in input CSV")
    end
end

println("Required columns OK.")

# ---- divu 列があれば除去 ----
if hasproperty(df, :divu)
    println("[Info] Removing column :divu")
    select!(df, Not(:divu))
end

# r = y
df.r = df.y

# ΔU = 1 − u
df.deltaU = 1 .- df.u

# 評価領域 2 ≤ x ≤ 15, |r| < 6
df2 = df[(df.x .>= 2) .& (df.x .<= 15) .& (abs.(df.r) .< 6), :]

output_path = joinpath(@__DIR__, "..", "data", "filtered_data.csv")
CSV.write(output_path, df2)

println("filtered_data.csv written.")
println("Size = ", size(df2))
