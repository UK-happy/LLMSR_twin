# 半自動進化計算ワークフロー (Phase 5: Legacy)

> [!NOTE]
> これは **Phase 5 (Trial 1-7)** までのワークフローです。
> 最新の **Phase 6 (Trial 8以降)** については、[WORKFLOW_PHASE6.md](WORKFLOW_PHASE6.md) を参照してください。

このガイドでは、Gemini LLMとJuliaを使った半自動進化計算の実行手順を説明します。

## 🎯 概要

**役割分担**:
- **Julia**: モデルの評価、係数最適化、結果の保存
- **Gemini LLM**: 構造式の生成、進化戦略の適用
- **ユーザー**: 両者の橋渡し（JSONファイルの受け渡し）

**データフロー**:
```
Julia → feedback_genN.json → ユーザー → Gemini
Gemini → models_genN+1.json → ユーザー → Julia
```

---

## 📋 実行手順

### ステップ0: 準備

```bash
# プロジェクトディレクトリに移動
cd /Users/Daily/Development/WindTurbineWake/LLMSR

# 依存パッケージの確認
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# 動作確認（オプション）
julia --project=. main.jl
```

---

### ステップ1: 初期集団の生成（世代0）

1.  **初期集団の生成**:
    ```bash
    julia --project=. semi_auto_evolution.jl --generate-initial --size 20 [--exp-name experiment_name]
    ```
    - `results/{exp_name}/feedback_gen0.json` が生成されます。
    - このファイルには、Geminiへの指示が含まれています（`templates/phase5_prompt.md` を使用）。
    - `seeds.json` が存在する場合、そこからシードモデルが自動的にロードされ、LLMに過去の成功モデルが提供されます。
    - 別のシードファイルを使用するには: `--seeds-file path/to/seeds.json` を指定します。
    - **シードを使用しない場合**: `--seeds-file NO_SEEDS` のように存在しないファイル名を指定してください。

**内容確認**:
```bash
cat results/{exp_name}/feedback_gen0.json | jq
```

---

### ステップ2: Geminiに初期集団を生成させる

1. **feedback_gen0.json の内容をGeminiに提示**

チャットで以下のように依頼：

```
results/{exp_name}/feedback_gen0.json を見て、
風車後流モデルの構造式を20個生成してください。

指示に従って、多様性のある式を生成してください。
出力は以下のJSON形式でお願いします：

{
  "generation": 1,
  "models": [
    {
      "id": 1,
      "formula": "a * exp(-b*x) * exp(-c*r^2)",
      "num_coeffs": 3,
      "reason": "...",
      "ep_type": "EP1"
    },
    ...
  ]
}
```

2. **Geminiの応答をファイルに保存**

Geminiが生成したJSONを `results/{exp_name}/models_gen1.json` に保存

---

### ステップ3: 世代1の評価

```bash
julia --project=. semi_auto_evolution.jl --evaluate 1 [--exp-name experiment_name]
```

**処理内容**:
- 20個のモデルをそれぞれ評価（DEで係数最適化）
- スコア（MSE）を計算
- 結果を `results/{exp_name}/feedback_gen1.json` に保存
- 履歴を `results/{exp_name}/history.jsonl` に追記

**出力例**:
```
🔬 Evaluating Generation 1
====================================================================

📂 Loading models from: results/{exp_name}/models_gen1.json
   ✓ Loaded 20 models

⚙️  Evaluating models...
- **Stagnation**: If scores plateau, increase mutation rate or force EP1 (New Structures).
- **Overfitting**: If validation score worsens, increase physical penalty weight or force EP4 (Simplification).
   [ 1/20] a * exp(-b*x) * exp(-c*r^2)...              ✓ Score: 0.001234
   [ 2/20] a * x^(-b) * (1 + c*r^2)^(-d)...            ✓ Score: 0.002145
   ...

📊 Generation 1 Statistics
====================================================================
   Population size: 20
   Best score:      0.001234
   Median score:    0.003456
   Mean score:      0.004123
   Worst score:     0.012345

🏆 Top 3 Models:
----------------------------------------------------------------------
[1] Score: 0.001234
    Formula: a * exp(-b*x) * exp(-c*r^2)
    Coeffs: [0.92, 0.028, 1.35]
    Reason: Classic Gaussian profile
...

### 進化のフェーズ戦略

Trial 3の教訓から、以下のフェーズ分けを推奨します：

1.  **探索フェーズ (Gen 1-15)**:
    - **目標**: 最適な主構造（減衰項、半径方向プロファイル）の発見
    - **戦略**: EP1（多様性）、EP2（局所改善）、EP3（物理性）
    - **注意**: **オフセット項（+ c）の追加は避ける**（ローカルミニマムへの早期収束を防ぐため）

2.  **ファインチューニングフェーズ (Gen 16-20)**:
    - **目標**: 微小なズレの補正とスコアの極限追求
    - **戦略**: **EP5（オフセット調整）** を解禁
    - **方法**: 既存の良モデルに定数項や微小な補正項を追加する

---

### ステップ4: 世代2以降の繰り返し

**4-1. feedback_gen1.json を Geminiに提示**

```
results/{exp_name}/feedback_gen1.json を見て、次世代（世代2）の
構造式を20個生成してください。

前世代の結果を参考に、以下の戦略で生成してください：
- EP1（多様性）: 4個 - 全く新しい構造
- EP2（局所改善）: 10個 - ベストモデルの改良
- EP3（物理性改善）: 4個 - 物理的制約を満たすよう修正
- EP4（簡素化）: 2個 - 複雑なモデルを簡素化

【重要な観察】
- ベストモデル: a * exp(-b*x) * exp(-c*r^2) (Score: 0.001234)
- このモデルは古典的なGaussianプロファイルです
- 乱流項（k, omega, nut）を含むモデルは試されていません
- べき乗型のモデルはGaussian型より精度が低い傾向

出力は同じJSON形式でお願いします。
```

**4-2. Geminiの応答を保存**

`results/{exp_name}/models_gen2.json` に保存

**4-3. 評価実行**

```bash
julia --project=. semi_auto_evolution.jl --evaluate 2 [--exp-name experiment_name]
```

**4-4. これを世代20まで繰り返す**

---

### ステップ5: 進化の可視化

任意の時点で、これまでの進化の様子を確認できます：

```bash
julia --project=. src/analysis/visualize_evolution.jl [--exp-name experiment_name]
```

**出力**:
**出力**:
- `results/{exp_name}/plots/evolution_curve.png` - 世代ごとのスコア推移
- `results/{exp_name}/plots/score_distribution.png` - スコア分布の箱ひげ図
- `results/{exp_name}/plots/evolution_summary.txt` - テキストサマリー

**サマリーの表示**:
```bash
cat results/{exp_name}/plots/evolution_summary.txt
```

---

## 💡 効率的な実行のコツ

### 1. フィードバックの読み方

`feedback_genN.json` の重要なポイント：

```json
{
  "best_model": {
    "formula": "...",  // ← これまでで最良の式
    "score": 0.001234  // ← 達成スコア
  },
  "evaluated_models": [
    {
      "formula": "...",
      "score": ...,
      "reason": "...",   // ← なぜこの式を生成したか
      "ep_type": "EP2"   // ← どの戦略で生成したか
    }
  ]
}
```

### 2. Geminiへの効果的なプロンプト

**初期世代（1-5）**: 多様性重視
```
EP1とEP2を中心に、様々なアプローチを試してください。
乱流項、べき乗型、Gaussian型、複合型など。
```

**中期世代（6-15）**: 局所改善 + 物理性
```
ベストモデルを基に改良してください（EP2）。
物理的制約（x減衰、r対称性）を確認してください（EP3）。
```

**後期世代（16-20）**: 精緻化 + 簡素化
```
微調整で精度を詰めてください（EP2）。
過剰に複雑なモデルは簡素化してください（EP4）。
```

### 3. 中断と再開

途中で中断しても問題ありません：

- `results/{exp_name}/history.jsonl` に全履歴が保存されている
- 次回は直前の世代のfeedbackからGeminiに依頼
- 世代番号を合わせて評価を再開

### 4. パラメータ調整

集団サイズを変更したい場合：

```bash
# 初期集団を10個に変更
julia --project=. semi_auto_evolution.jl --generate-initial --size 10
```

### 5. 複数の実験を管理する（推奨）

異なるLLMや設定で試行を行う場合、`--exp-name` オプションを使用して結果の保存先を分けることができます。

```bash
# 実験名 "gpt4_trial" で初期化
julia --project=. semi_auto_evolution.jl --generate-initial --exp-name gpt4_trial

# 評価時も実験名を指定（--inputは省略可）
julia --project=. semi_auto_evolution.jl --evaluate 1 --exp-name gpt4_trial

# 可視化
julia --project=. src/analysis/visualize_evolution.jl --exp-name gpt4_trial

# 最終評価とレポート生成
# `finalize_trial.jl` は以下のスクリプトを順次実行します：
# 0.  `calibrate_baselines.jl`: ベースラインのキャリブレーション（初回のみ実行）
# 1.  `visualize_evolution.jl`: スコア推移の可視化
# 2.  `analyze_physics_validity.jl`: 物理的妥当性の推移
# 3.  `trace_evolution_lineage.jl`: 進化系統樹の作成
# 4.  `analyze_reason_correlation.jl`: ReasonスコアとMSEの相関
# 5.  `benchmark_models.jl`: ベストモデルのベンチマーク
# 6.  `evaluate_reason_api.jl` (Option): APIによる詳細評価
# 7.  `prepare_report.jl`: レポート用コンテキストの生成
# julia --project=. src/analysis/finalize_trial.jl --exp-name gpt4_trial
#
# 可視化
julia --project=. src/a`finalize_trial.jl` は以下のスクリプトを順次実行します：
0.  `calibrate_baselines.jl`: ベースラインのキャリブレーション（初回のみ実行）
1.  `visualize_evolution.jl`: スコア推移の可視化
2.  `analyze_physics_validity.jl`: 物理的妥当性の推移
3.  `trace_evolution_lineage.jl`: 進化系統樹の作成
4.  `analyze_reason_correlation.jl`: ReasonスコアとMSEの相関
5.  `benchmark_models.jl`: ベストモデルのベンチマーク
6.  `evaluate_reason_api.jl` (Option): APIによる詳細評価
7.  `prepare_report.jl`: レポート用コンテキストの生成`results/gpt4_trial/` ディレクトリに保存されます。デフォルトは `results/default/` です。

---

## 📊 進化の評価指標

### スコア改善率

世代1と世代Nのベストスコアを比較：

```julia
improvement = (score_gen1 - score_genN) / score_gen1 * 100
```

目標: **50%以上の改善**（例: 0.01 → 0.005）

### 多様性

各世代でユニークな式のパターン数をチェック。
多様性が低下しすぎたら、EP1を増やす。

### 物理性

非物理的なモデル（xで発散、負のΔUなど）が生成されている場合は、
EP3で修正を依頼。

---

## 🐛 トラブルシューティング

### エラー: "Model file not found"

→ `results/{exp_name}/models_genN.json` のファイル名が正しいか確認

### エラー: "All models failed evaluation"

→ 生成された式に構文エラーがある可能性
→ JSON形式が正しいか確認（`jq` で検証）

### スコアが改善しない

→ Geminiへのフィードバックを詳しくする
→ EP2（局所改善）の比率を上げる
→ 物理的ヒントを追加（「乱流項を入れてみてください」など）

### 式が複雑すぎる

→ EP4（簡素化）を依頼
→ 係数数の上限を設定（例: 5個まで）

---

## ✅ チェックリスト（20世代完走）

- [ ] 世代0: 初期フィードバック生成
- [ ] 世代1-5: 多様性探索
- [ ] 世代6-10: 有望な方向性の改善
- [ ] 世代11-15: 物理性とバランスの調整
- [ ] 世代16-20: 精緻化と簡素化
- [ ] 可視化実行
- [ ] 最良モデルの検証（ベンチマーク）
- [ ] レポート作成（`src/analysis/prepare_report.jl` 実行）

---

## 📁 ファイル構成

実行後のディレクトリ構造：

```
LLMSR/
├── results/
│   ├── default/                # デフォルトの実験結果
│   └── {exp_name}/             # 指定した実験名のディレクトリ
│       ├── feedback_gen0.json
│       ├── models_gen1.json
│       ├── feedback_gen1.json
│       ├── ...
│       ├── history.jsonl
│       ├── plots/
│       │   ├── evolution_curve.png
│       │   └── ...
│       └── report.md           # 実験レポート（推奨）
```

---

## 🎓 次のステップ

20世代完了後：

1. **最良モデルの詳細検証**
   - 予測値 vs 実測値のプロット
   - 物理的解釈の検討

2. **既存モデルとの比較**
   - Jensen, Bastankhah, Gaussian モデルとのベンチマーク

3. **論文執筆**
   - 進化の過程を可視化
   - LLMが生成したReasonの分析
   - 物理的洞察の抽出

4. **他のLLMとの比較**
   - GPT-4o, Claude でも同じ実験
   - 結果の比較分析

## 8. 評価・分析ツール (Evaluation & Analysis Tools)

Phase 6 で導入された高度な分析ツールは、Phase 5 でもそのまま利用可能です。
これにより、実験間の公平な比較と詳細な検査が可能になります。

### 8.1 ベースラインのキャリブレーション (Calibration)

評価の一貫性を保つため、標準モデル（Jensen, Bastankhah）の最適係数を事前に厳密に計算し、固定します。

**使用方法**:
```bash
julia --project=. src/analysis/calibrate_baselines.jl
```
- 入力データ（`data/result_I0p3000_C22p0000.csv`）に対応する設定ファイル `params/standard_models_result_I0p3000_C22p0000.json` が生成されます。
- このファイルが存在する場合、以下のツールは自動的にこれを読み込みます。

### 8.2 モデルの詳細分析 (Inspection)

特定の世代の特定のモデルを個別に可視化し、CFDデータと比較します。

**使用方法**:
```bash
# 特定の世代の最良モデルを描画 (例: Gen 20)
julia --project=. src/analysis/inspect_model.jl --gen 20 --best --exp-name trial_7

# 特定の世代の特定IDのモデルを描画 (例: Gen 7, ID 3)
julia --project=. src/analysis/inspect_model.jl --gen 7 --id 3 --exp-name trial_7
```
- **特徴**: キャリブレーション済みの標準モデルと比較するため、常に同じ基準線で評価できます。

### 8.3 ベンチマークと最終評価 (Benchmarking)

発見された最良モデルを、標準的な後流モデルと厳密に比較します。

**使用方法**:
```bash
julia --project=. src/analysis/benchmark_models.jl --exp-name trial_7 --gen 20
```
- **特徴**: LLMモデルに対しては、負の値（オフセット項）も許容する**厳密な最適化**を行い、真の性能を引き出します。
- **出力**: `results/{exp_name}/plots/benchmark_summary.txt` に詳細な比較結果（改善率など）が出力されます。

---

## 8.5. 進化系統の追跡 (Lineage Tracing)

最良モデルがどのように進化してきたか、その系譜を可視化します。

### 使用方法

```bash
julia --project=. src/analysis/trace_evolution_lineage.jl [--exp-name experiment_name]
```

### 処理内容
1.  `history.jsonl` から全世代のモデルデータを読み込みます。
2.  親子関係（`parent_id`）を追跡し、Global BestモデルとFinal Bestモデルへの進化パスを特定します。
3.  Mermaid形式のグラフと、数式の変遷表を含むMarkdownレポートを生成します。

### 出力
- `results/{exp_name}/evolution_lineage.md`: **進化系統レポート**（VS CodeのMarkdownプレビューでグラフを確認可能）

---

## 9. レポート作成 (Reporting)

実験結果をまとめたレポートを作成するためのコンテキスト情報を生成します。

### 使用方法

```bash
julia --project=. src/analysis/prepare_report.jl [--exp-name experiment_name]
```

### 処理内容
1.  `history.jsonl` から進化の履歴を読み込みます。
2.  `benchmark_summary.txt` からベンチマーク結果を読み込みます。
3.  これらを統合し、LLMにレポート執筆を依頼するためのプロンプトファイル `report_context.md` を生成します。

### 次のステップ
生成された `results/{exp_name}/report_context.md` の内容をコピーし、Gemini（または他のLLM）に貼り付けてください。
「以下の情報を基に、実験レポートを作成してください」と依頼することで、詳細なレポートが得られます。

---

## 🐛 トラブルシューティング

### エラー: "Model file not found"
→ `results/{exp_name}/models_genN.json` のファイル名が正しいか確認

### エラー: "All models failed evaluation"
→ 生成された式に構文エラーがある可能性
→ JSON形式が正しいか確認（`jq` で検証）
→ **修正済み:** 以前は `exp(vector)` のような式でエラーが発生していましたが、`src/evaluator.jl` に**自動ベクトル化機能**を追加したため、現在は `a * exp(-b*x)` のような式も正常に計算されます。

### スコアが改善しない
→ Geminiへのフィードバックを詳しくする
→ EP2（局所改善）の比率を上げる
→ 物理的ヒントを追加（「乱流項を入れてみてください」など）
→ **後期世代なら**: EP5（オフセット調整）を試す

### 式が複雑すぎる
→ EP4（簡素化）を依頼
→ 係数数の上限を設定（例: 5個まで）

---

## 10. トライアル終了後のメンテナンス (Post-Trial Maintenance)

次回のトライアルをより良い状態で開始するために、以下の手順を実施してください。

### 1. seeds.json の更新
今回のトライアルで発見されたベストモデル（または特徴的なモデル）を `seeds.json` に追加します。これにより、次回のトライアルでその知見を活用できます。

```json
  {
    "id": "trial_N_best",
    "formula": "...",
    "score": 0.000xxx,
    "description": "Trial N Best: ..."
  }
```

### 2. 結果のアーカイブ
`results/{exp_name}` ディレクトリをそのまま保存し、必要に応じてバックアップを取ってください。
