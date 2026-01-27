# LLMSR Workflow (Phase 6: Physics-Informed & Reason-Driven Evolution)

## 1. 概要
Phase 6 では、Phase 5 の進化フレームワークを拡張し、**「物理的妥当性」**と**「推論（Reason）の質」**を明示的に評価関数に組み込みます。
単にデータにフィットするだけでなく、物理的に意味のある構造と、それを裏付ける論理的な説明を持つモデルの発見を目指します。

### 主な変更点
- **評価関数**: $Score = MSE \times (1 + Penalty_{Physics}) \times (1 - 0.2 \times Score_{Reason})$
    - **Physics Penalty**: P1〜P4 の物理制約違反に基づくペナルティ。
    - **Reason Score**: LLMの生成した `reason` の質（0.0〜1.0）。
        - **デフォルト**: ルールベース評価 (`ReasonScorer.jl`)。
        - **拡張**: APIベースの3段階評価 (`evaluate_reason_api.jl`)。
- **モジュール構成**: `src/Phase6/` 下に機能を分割（Physics, ReasonScorer, Evaluator, Optimizer）。

---

## 2. 準備

### 環境設定
```bash
# Julia プロジェクトの有効化
julia --project=.
```

### 必要なファイル
- `run_phase6.jl`: メイン実行スクリプト
- `simulate_llm_evolution.jl`: 進化シミュレーションスクリプト
- `templates/phase6_prompt.md`: プロンプトテンプレート
- `seeds.json`: 初期シード（Trial 7までのベストモデルを含む）

---

## 3. 実行サイクル (Evolution Loop)

### Step 1: 初期集団の生成 (Stage 1: Diversity Generation)
多様性を最大化するため、LLMを使用して構造的に異なるモデルを生成します。

```bash
# Stage 1: Diversity Generation (Gen 1)
# Gemini APIを使用して、ガウス型以外の多様な構造（有理関数、合成関数など）を生成します。
export GOOGLE_API_KEY="AIza..."
julia --project=. simulate_llm_evolution.jl --start 1 --end 1 --exp-name trial_10 --stage 1
```

### Step 2: 進化と淘汰 (Stage 2 & 3)
生成された多様なモデルを親として、進化計算を行います。

```bash
# Stage 3: Fitting & Selection (Gen 2-20)
# 標準的な進化プロセス（変異・交差・淘汰）を実行します。
julia --project=. simulate_llm_evolution.jl --start 2 --end 20 --exp-name trial_10 --stage 3
```

**ステージ構成**:
- **Stage 1 (Diversity)**: ガウス型を禁止し、構造的多様性を最大化するプロンプトを使用。
- **Stage 2 (Hybrid)**: （将来拡張）異なる構造の融合を促進。
- **Stage 3 (Fitting)**: 物理的妥当性と精度を重視した最適化。


### Step 3: 分析と選定
各世代の終了時、またはトライアル終了時に分析を行います。

- **トレードオフ分析**: MSE vs Physics Penalty vs Reason Score の関係を確認。
- **ベストモデル選定**:
    - 優先順位: 物理ペナルティ $\approx 0$ > MSE が低い > Reason が良い。

---

## 4. 評価基準の詳細

### 4.1 物理ペナルティ (Physics Penalty)
以下の項目に違反した場合、重み付きペナルティを加算します。

- **P1: x方向減衰 ($\lambda_1=1.0$)**:
  - $x$ の増加に伴い $\Delta U$ が単調減少すること（再加速しない）。
  - 無限遠 ($x \to \infty, r \to \infty$) でゼロに収束すること。
- **P2: r方向対称性 ($\lambda_2=0.5$)**:
  - $r$ と $-r$ で値が一致すること。
- **P3: 物理的範囲 ($\lambda_3=2.0$)**:
  - $0 \le \Delta U \le 1.2$ の範囲に収まること（負値や過大な値を禁止）。
- **P4: 渦粘性整合 ($\lambda_4=0.2$)**:
  - $\nu_t$ が増加した際、ピーク欠損が減少し、後流が広がる傾向にあること。

### 4.2 Reason スコア (Reason Score)
LLMの `reason` フィールドをテキスト解析します。

- **加点**:
  - 物理キーワード（turbulence, viscosity, asymptotic, etc.）の使用。
  - **ペナルティ意識**: `P1`, `P2`, `penalty` などの単語を含み、改善意図が明確であること。
- **減点**: 曖昧な表現（adjusted, tweaked, random guess）。
- **スコア範囲**: 0.1 (Bad) 〜 1.0 (Good)。

---

## 5. 分析・評価 (Analysis & Evaluation)

トライアル終了後、以下のコマンドで一括分析を行います。

```bash
# 基本分析（可視化、物理妥当性、系統追跡、ベンチマーク、Reason相関）
julia --project=. finalize_trial.jl --exp-name trial_10

# API評価を含める場合（コストがかかります）
julia --project=. finalize_trial.jl --exp-name trial_10 --api-eval
```

`finalize_trial.jl` は以下のスクリプトを順次実行します：
0.  `calibrate_baselines.jl`: ベースラインのキャリブレーション（初回のみ実行）
1.  `visualize_evolution.jl`: スコア推移の可視化
2.  `analyze_physics_validity.jl`: 物理的妥当性の推移
3.  `trace_evolution_lineage.jl`: 進化系統樹の作成
4.  `analyze_reason_correlation.jl`: ReasonスコアとMSEの相関
5.  `benchmark_models.jl`: ベストモデルのベンチマーク
6.  `evaluate_reason_api.jl` (Option): APIによる詳細評価
7.  `prepare_report.jl`: レポート用コンテキストの生成

---

### 個別実行（詳細分析用）

必要に応じて、各ツールを個別に実行することも可能です。

### 5.1 モデルの詳細分析 (Inspection)
特定の世代の特定のモデルを個別に可視化し、CFDデータと比較します。
```bash
julia --project=. src/analysis/inspect_model.jl --gen 20 --best --exp-name trial_10
```

### 5.2 APIによるReasonの精密評価 (Advanced API Evaluation)
```bash
export GOOGLE_API_KEY="..."
julia --project=. src/analysis/evaluate_reason_api.jl --gen 20 --exp-name trial_10 --model gemini-2.5-pro
```

### 5.3 レポート作成 (Report Preparation)
実験結果をまとめたレポート作成用のコンテキストを生成します。
```bash
julia --project=. src/analysis/prepare_report.jl --exp-name trial_10
```

---

1.  **結果のアーカイブ**: `results/trial_X/`
2.  **Seeds更新**: 物理的に妥当なベストモデルを `seeds.json` に追加。
3.  **レポート作成**: 物理的妥当性の検証結果を含める。

---

## 6. 多様性と緩和 (Diversity & Relaxation)
Phase 6 の「物理制約」が厳しすぎて `x^(-1)` への早期収束を招いたため、Phase 6 の改善として以下の変更を行いました。

### 6.1 制約の緩和 (Relaxed Constraints)
- **ペナルティ重みの低減**:
    - Decay (P1): 1.0 -> 0.5
    - Nut (P4): 0.2 -> 0.1
- **マージンの導入**: 微小な違反（1e-4以下）は許容。
- **キャップ設定**: ペナルティ上限を 100.0 に設定し、即死（Inf）を防ぐ。

### 6.2 多様性ボーナス (Diversity Bonus)
集団の平均的な挙動から離れている（ユニークな）モデルを優遇します。

$$ Score_{new} = \frac{Score_{old}}{1 + 5.0 \times Diversity} $$

- **Diversity**: アンサンブル平均予測からの平均二乗偏差。
- **効果**: 性能が多少劣っても、ユニークな挙動をするモデルが生き残りやすくなる。

