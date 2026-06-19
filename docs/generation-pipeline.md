# AI生成パイプライン仕様

> 対象: 設計書 §9。**iOS 側（Apple `FoundationModels`・iOS 26+・Apple Intelligence 対応端末）**
> で実装する。生成の「検証・修復・フォールバック」は `ScoreForgeKit` に実装済みなので、
> iOS 側は「モデル呼び出し」と「段階出力 → Schema 組み立て」に集中すればよい。

## 0. 設計原則（再掲）

- モデルには**実行コードではなく宣言的スキーマ**だけを作らせる（§6.3, App Store 2.5.2 適合）。
- 約3B のオンデバイスモデルは一括生成が不安定なので、**多段に分解**し各段で Guided Generation
  （`@Generable`）を使う（§9.2）。
- 生成結果は**必ず検証 → 自動修復 → フォールバック**を通し、「動かない状態」を作らない。
  この保証は `SchemaValidator` + `SchemaRepair` + `DefaultLayoutBuilder` で実装済み。

## 1. 可用性チェック（FR-16）

```swift
import FoundationModels
switch SystemLanguageModel.default.availability {
case .available:            // 生成UIを表示
case .unavailable(let why): // 生成UIを抑止し、プリセット/インポート/手動作成へ誘導
}
```

非対応端末でも `Presets`・`TemplateTransfer.importTemplate`・手動作成・対局は全て動く
（コアは生成に依存しない）。

## 2. 多段フロー（§9.1）

```
自然言語の説明
  └▶ [1] 構造分類   structure / players / 採点方向(higherIsBetter)
  └▶ [2] フィールド  fields[]（型・scope・値域）
  └▶ [3] ロジック    actions[] / formulas[] / winCondition
  └▶ [4] レイアウト  layout（失敗時は DefaultLayoutBuilder へ）
  └▶ [5] 検証 SchemaValidator → 不正なら [6] へ
  └▶ [6] 修復: エラー要約をモデルへ戻して再生成（最大2回）→ なお不正なら SchemaRepair
  └▶ [7] プレビュー（サンプルデータ）→ 手動編集 → 保存
```

各段の出力は**部分情報**。id 採番・式の整合・正規化は**アプリ側**で行う（§9.3）。

## 3. Guided Generation 型（§9.3, 概念コード）

各段に対応する `@Generable` 構造体を定義し、`session.respond(to:generating:)` で構造化出力を得る。

```swift
@Generable struct GenStructure {
    @Guide(description: "rounds か freeform") var structure: String
    @Guide(.range(1...12)) var defaultPlayers: Int
    @Guide(.range(1...12)) var minPlayers: Int
    @Guide(.range(1...16)) var maxPlayers: Int
    @Guide(description: "高い合計が勝ちなら true") var higherIsBetter: Bool
    @Guide(description: "ラウンド数が固定なら true") var roundsFixed: Bool
}

@Generable struct GenField {
    @Guide(description: "短い日本語名（例: 得点, 失点, 予想）") var label: String
    @Guide(description: "integer|number|text|bool|select のいずれか") var type: String
    @Guide(description: "global|perPlayer|perPlayerPerRound|perRound") var scope: String
    @Guide(.range(-999...999)) var defaultValue: Int
}

@Generable struct GenFormula {
    @Guide(description: "短い日本語名（例: 合計, 順位）") var label: String
    @Guide(description: "perPlayer|perPlayerPerRound|perRound|global") var scope: String
    @Guide(description: "DSL式。許可関数のみ使用") var expression: String
}
// winCondition も同様に @Generable で type / target / rounds を取得。
```

> `@Guide` の列挙制約で type/scope の語彙を縛る。それでも外れ値は来うるので §5 の正規化が必須。

## 4. 段階出力 → Schema 組み立て（アプリ側の正規化）

1. **id 採番**: label を slug 化＋一意化（`uniqueId` 相当）。重複は連番付与。
2. **型・scope の正規化**: 既知 enum にマップ。未知は安全側（type→`integer`, scope→`perPlayer`）。
3. **式の整合**: 関数名・参照 id をホワイトリスト/既知 id に照合。未知参照を含む式は破棄候補。
4. **winCondition**: `higherIsBetter` から `type`（highestTotal/lowestTotal 等）と `lowerWins` を決定。
   `firstToReach` のとき target を設定。`scoreFormula` は合計系 formula の id。
5. これらで `Schema` を構築し、次節の検証へ。

`Schema.fields/formulas/actions/winCondition` は確定済みの Codable 型。組み立て後は
`SchemaNormalizer.normalize(_:)` を通すと既定値・プレイヤー範囲・ラウンド設定が整う。

## 5. 検証 → 修復 → フォールバック（実装済み API）

```swift
let report = SchemaValidator.validate(candidate)
if report.isValid {
    use(candidate)
} else if retries < 2 {
    // エラー要約をプロンプトに戻して該当段だけ再生成（§9.5）
    let summary = report.errors.map(\.message).joined(separator: "\n")
    candidate = try await regenerate(stage, feedback: summary)
} else {
    // モデルで直らない場合も「必ず動く」状態を機械生成
    let (repaired, notes) = SchemaRepair.repair(candidate)
    use(repaired)   // notes はプレビューで「自動調整しました」と提示
}
```

`SchemaRepair.repair` は **検証通過を保証**（未知関数・参照切れ・循環・不正アクション・
不正勝利条件・未知レイアウトを機械修復し、最終フォールバックまで担保）。レイアウト生成（[4]）が
失敗/破綻した場合も `DefaultLayoutBuilder.build(for:)` が `fields/formulas/actions` から
必ず妥当なレイアウトを作る。

## 6. プロンプト設計の要点（§9.4）

- **役割固定**: 「あなたはスコア採点盤の設計者。出力は指定スキーマのみ。」
- **少数事例（Few-shot）**: 同梱 6 プリセット（`Presets.all`）の「説明 → スキーマ」対応を提示。
  累積失点系 / トリックテイキング系 / 一致ボーナス系 / 最少点勝ち系 / カテゴリ加点系 を網羅済み。
- **語彙の固定**: 関数名（`field`,`sumRounds`,`rankDesc`,`clamp`,`if` …）・type 名・scope 名を列挙し、
  それ以外を禁止（許可一覧は §8.3 / `BuiltinFunctions.known` と一致）。
- **分解質問**: 説明が曖昧なら生成前に**最大1〜2問だけ**選択式で補足（人数？高い方が勝ち？ラウンド制？）。

## 7. プレビュー用サンプルデータ（FR-04, 推奨追加）

生成直後の実挙動確認のため、`GameRuntime` にサンプル値を流し込む小さなヘルパー
（例: `PreviewSeeder.seed(_ runtime:)`）をコアに追加すると良い。各 field を型/値域に応じた
プレースホルダ値（integer は中央値、bool はランダム、select は先頭以外）で満たし、`recompute()`
後に合計/順位が動く様子を見せる。**この1点だけが未実装**で、他は配線するだけで動く。

## 8. まとめ: iOS 側の実装範囲

| やること（iOS/Mac） | 既に用意済み（ScoreForgeKit） |
|---|---|
| `FoundationModels` 呼び出し・`@Generable` 定義 | スキーマ確定型・Codable |
| 段階出力 → `Schema` 正規化 | `SchemaNormalizer` |
| 検証・修復・フォールバック | `SchemaValidator` / `SchemaRepair` / `DefaultLayoutBuilder` |
| プレビュー描画 | `GameRuntime`（要 renderer-spec.md） |
| Few-shot 事例 | `Presets`（6種） |
