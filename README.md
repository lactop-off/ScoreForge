# ScoreForge

> 「スコアを記録するアプリ」ではなく「スコア画面を生み出すビルダー」。
> ゲームの数え方を言葉で説明するだけで、そのゲーム専用の採点画面が手に入る——
> 完全オフライン・完全無料・オンデバイスAIを志向した iOS スコア盤ビルダー。

設計の全体像は [`docs/design.md`](docs/design.md)（要件定義〜詳細設計書 v1.0）を参照してください。

---

## 現在の状態：MVP コアエンジン（v0.1 の基盤）

本リポジトリには、設計書 §14 の **MVP（v0.1「動く最小」）の中核**である
クロスプラットフォームなコアエンジン **`ScoreForgeKit`** を実装しています。
UI（SwiftUI レンダラ）や AI 生成（Foundation Models）に依存しない純粋ロジックなので、
Linux／macOS 上で `swift test` により検証できます（iOS 実機・Xcode 不要）。

### 実装済み（このコミット時点）

| 設計書 | モジュール | 内容 |
|---|---|---|
| §7 | `Schema/` | 宣言的スキーマ型（Field / Action / Formula / Layout / WinCondition）と JSON 入出力 |
| §8 | `Expression/` | サンドボックス式エンジン（字句解析→構文解析→評価。ホワイトリスト関数・評価上限・決定性） |
| §7.4 / §8.4 | `Runtime/DependencyGraph` | フォーミュラ依存の DAG 構築・トポロジカル順・循環検出 |
| §10.1 / §7.6 | `Runtime/GameRuntime` | 状態管理・効果適用・再計算・勝敗判定・Undo・ラウンド追加 |
| §9.5 | `Validation/` | スキーマ検証（参照整合・型・循環・勝利条件・レイアウト縮退） |
| FR-15 / §14 | `Presets/` | 同梱プリセット 3 種（トリックテイキング／得点レース／最少点） |

37 件のユニットテストが通過します（式の四則・優先順位・三項・短絡評価・0除算の安全縮退・
集計／順位・per-player-per-round 集計・クランプ・Undo・各勝利条件・プリセットの往復変換 等）。

### まだ無いもの（次のマイルストーン）

- **SwiftUI レンダラ / 各画面**（§10.2–10.4）— iOS 26 SDK 必須のため別ターゲットで実装予定
- **AI 生成パイプライン**（§9）— `FoundationModels` 連携（v0.5）
- **SwiftData 永続化**（§11）— 端末ローカル保存（iOS 側）
- テンプレ JSON エクスポート/インポートの UI 導線（§3.1, FR-14）

---

## ビルドと実行

```bash
swift build            # ライブラリと CLI をビルド
swift test             # 37 件のユニットテスト
swift run scoreforge-cli points-race    # プリセットを検証＆数手プレイして表示
#   引数: points-race | trick-taking | low-score
```

> Linux で Swift ツールチェーンを使う場合は [swift.org](https://www.swift.org/install/) を参照。
> 開発・検証は Swift 6.1（Swift 5 言語モード）で実施。

---

## パッケージ構成

```
Sources/ScoreForgeKit/
  Schema/       宣言的スキーマ型（§7）
  Expression/   式 DSL：Lexer / Parser / AST / Evaluator（§8）
  Runtime/      GameRuntime / GameState / DependencyGraph / WinEvaluator（§10）
  Validation/   SchemaValidator（§9.5）
  Presets/      同梱テンプレ（JSON）とローダ
Tools/scoreforge-cli/   エンジン動作確認用 CLI
Tests/ScoreForgeKitTests/
docs/design.md          要件定義・詳細設計書
```

コアは UI から分離した Swift Package です（設計書 §6.3「コアの部品化」）。将来的に独立
リポジトリ化し、Android/Web への移植土台とすることを想定しています。

## ライセンス

**未確定**（設計書 §12.2・付録A-1 の要決定事項）。コアエンジンを再利用しやすい部品として
広めるなら MIT または Apache-2.0 が候補です。確定後に `LICENSE` を追加します。
