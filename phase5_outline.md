# Phase 5: Semi-Automated Evolution Workflow Summary

## 概要

Phase 5は、Gemini LLM（構造生成）とJulia（係数最適化・評価）を連携させ、風車後流モデル（Wake Model）を半自動的に進化・探索するフェーズです。
ユーザーが仲介役となり、Juliaが生成したフィードバックJSONをLLMに渡し、LLMが生成したモデルJSONをJuliaに戻すというサイクルを繰り返します。

## 実行フロー

### 1. 初期化 (Generation 0)

- **目的**: 最初のプロンプトとコンテキストを作成する。
- **コマンド**:
  ```bash
  julia --project=. semi_auto_evolution.jl --generate-initial --size 20
  ```
- **出力**: `results/{exp_name}/feedback_gen0.json`

### 2. モデル生成 (LLM Turn)

- **役割**: ユーザー -> Gemini
- **手順**:
  1. `feedback_genN.json` (最初はgen0) の内容を確認。
  2. `templates/phase5_prompt.md` のテンプレートに基づき、自動生成されたプロンプトファイル（`results/{exp_name}/prompt_gen{N+1}.txt`）を使用します。
     - **自動化**: 「参考知識」「進化戦略」「よくあるエラー」などは自動的に含まれます。
  3. Geminiが生成したJSONを `results/{exp_name}/models_gen{N+1}.json` として保存。

### 3. 評価 (Julia Turn)

- **目的**: 提案された構造式の係数をDE（Differential Evolution）で最適化し、スコア（MSE + Penalty）を算出。
- **コマンド**:
  ```bash
  julia --project=. semi_auto_evolution.jl --evaluate 1 --input results/{exp_name}/models_gen1.json
  ```
- **出力**:
  - `results/{exp_name}/feedback_gen{N}.json` (次世代へのインプット)
  - `results/{exp_name}/history.jsonl` (履歴ログ)

### 4. 繰り返し (Evolution Loop)

- 上記の 2 -> 3 を目標世代（例: 20世代）まで繰り返す。
- 世代が進むにつれて、探索（Exploration）から活用（Exploitation）へと戦略をシフトさせる（EP1 -> EP2/EP4など）。

## 主要ファイル・ツール

- **`semi_auto_evolution.jl`**: メイン実行スクリプト。初期化と評価の両方を担当。
- **`templates/phase5_prompt.md`**: Geminiへの指示書（プロンプトテンプレート）。各世代での戦略（EP1-EP4）やJSONフォーマットが定義されている。
- **`src/Phase5/Phase5.jl`**: 評価ロジックのコアモジュール。`evaluate_formula`関数で構造式のパースとDEを用いた係数最適化を行う。
- **`src/Phase5/evolution_utils.jl`**: JSONの読み書き、履歴管理、多様性計算などを担当するユーティリティ。
  - **Update**: プロンプト自動生成機能を追加。`templates/phase5_prompt.md` から「参考知識」「進化戦略」「よくあるエラー」などの重要セクションを自動的に抽出し、次世代のプロンプトに組み込みます。これにより、手動でのコピペ作業が不要になりました。

## 注意点

- **Legacy Phase**: Phase 5は `WORKFLOW_PHASE6.md` で説明される最新のワークフロー（自動化が進んだTrial 8以降）の前段階であり、手動介入が必要です。
- **データフロー**: `Julia (Feedback)` -> `User (Prompting)` -> `Gemini (Models)` -> `User (Saving JSON)` -> `Julia (Evaluation)` のサイクル。
- **物理性制約**: 非物理的な式（発散、負の速度欠損など）はペナルティ評価され、スコアが悪化します。EP3（物理性改善）などで修正を図ります。
