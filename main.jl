#!/usr/bin/env julia

"""
Phase5 メインエントリーポイント

Usage:
    julia main.jl

CFDデータを読み込み、サンプルの構造式を評価します。
LLMが生成した構造式を評価するためのテンプレートとして使用できます。
"""

# プロジェクトのsrcディレクトリを読み込み
push!(LOAD_PATH, joinpath(@__DIR__, "src"))

# Phase5モジュールを読み込み
include("src/Phase5/Phase5.jl")
using .Phase5

println("="^60)
println("Phase5: Wind Turbine Wake Model Discovery")
println("="^60)
println()

# データパス（プロジェクトルート基準）
data_path = joinpath(@__DIR__, "data", "result_I0p3000_C22p0000.csv")

println("📂 Data path: $data_path")
if !isfile(data_path)
    error("Data file not found: $data_path")
end

# サンプルモデル式
model_examples = [
    ("Gaussian-like model", "a * exp(-b*x) * (1 + c*r^2)^(-d)"),
    ("Power-law decay", "a * x^(-b) * exp(-c*r^2)"),
    ("With turbulence", "a * exp(-b*x) * (1 + c*r^2)^(-d) * (1 + e*k)"),
]

println()
println("🔬 Evaluating sample models...")
println()

for (name, model) in model_examples
    println("▶ Model: $name")
    println("  Formula: $model")
    
    # 構造式を評価
    score, θ = evaluate_formula(model; num_coeffs=4, csv_path=data_path)
    
    if θ !== nothing
        println("  ✓ Score (MSE): $score")
        println("  ✓ Coefficients: $θ")
    else
        println("  ✗ Evaluation failed")
    end
    println()
end

println("="^60)
println("✅ Evaluation complete!")
println("="^60)
println()
println("💡 LLM用インターフェース:")
println("   Phase5.evaluate_formula(model_str; num_coeffs=4, with_penalty=false)")
println()
