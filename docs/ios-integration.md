# iOS 統合ガイド（アプリ本体の組み立て）

> 対象: 設計書 §6.1 Presentation 層・§10.3 画面遷移・§11 永続化。
> **Mac/Xcode・iOS 26 SDK 必須**。本書は `ScoreForgeKit`（実装・テスト済み）を消費して
> iOS アプリを組み上げる手順のメモ。コア（ロジック）は完成しているので、ここは「配線」が中心。

## 1. プロジェクト構成

```
ScoreForge.xcodeproj (or App SwiftPM target)
└─ App（iOS 26）
   ├─ depends on: ScoreForgeKit（本リポジトリの Swift Package）
   ├─ Rendering/   LayoutRenderer, leaf views（docs/renderer-spec.md）
   ├─ Generation/  FoundationModels 連携（docs/generation-pipeline.md）
   ├─ Persistence/ SwiftData モデル + 変換（本書 §3）
   └─ Screens/     一覧 / 生成 / プレビュー編集 / 対局 / 結果 / 履歴 / 設定
```

App ターゲットからは `import ScoreForgeKit` で全コア型を利用できる。コアは UI 非依存なので、
Package を Xcode プロジェクトのローカル依存に追加するだけでよい。

## 2. 画面遷移（§10.3）と FR 対応

```
[ホーム/テンプレ一覧] ← Presets.all + 保存済みテンプレ
   ├─(＋)→ [説明入力] →(生成: §generation)→ [プレビュー/編集] →(保存)→ 一覧へ   FR-01..06
   ├─ テンプレ選択 → [対局セットアップ(人数/名前)] → [対局画面] →(終了)→ [結果]    FR-07..10,12
   ├─ [履歴] → 対局詳細 → 再戦                                                  FR-13
   └─ [設定] テーマ/言語/インポート/エクスポート/AI可否表示                       FR-14,16,17
```

- 対局画面は `docs/renderer-spec.md` の `LayoutRenderer` + `GameRuntime`。
- 生成画面は可用性チェック（FR-16）で出し分け。非対応端末は説明入力を隠しプリセット導線へ。
- エクスポート/インポートは `TemplateTransfer`（実装済み）＋ `UIDocumentPicker` / 共有シート。

## 3. 永続化（SwiftData, §11）

コアは「スキーマ JSON」と「対局状態」を扱う。SwiftData では**スキーマは JSON 文字列で保持**し、
対局はエンティティに分解して保存する。設計書 §11 の表に対応:

```swift
import SwiftData
import ScoreForgeKit

@Model final class TemplateEntity {
    @Attribute(.unique) var id: String
    var name: String
    var schemaJSON: Data        // try schema.encoded()
    var origin: String          // Schema.Origin.rawValue
    var createdAt: Date
    var updatedAt: Date

    var schema: Schema? { try? Schema.decode(from: schemaJSON) }
}

@Model final class GameEntity {
    @Attribute(.unique) var id: String
    var templateId: String
    var status: String          // "active" | "finished"
    var createdAt: Date
    var finishedAt: Date?
    @Relationship(deleteRule: .cascade) var players: [PlayerEntity]
    @Relationship(deleteRule: .cascade) var entries: [EntryEntity]
}

@Model final class PlayerEntity { var id: String; var gameId: String; var name: String; var team: String?; var order: Int }
@Model final class EntryEntity  { var id: String; var gameId: String; var playerId: String?; var round: Int?; var fieldId: String; var valueJSON: Data }
@Model final class ResultEntity { var id: String; var gameId: String; var winnerPlayerIds: [Int]; var finalScoresJSON: Data }
```

### GameRuntime ↔ 永続化の橋渡し（要実装の薄い変換層）

`GameState` は `fields[id][CellKey] = Value` を保持する（`CellKey = (player?, round?)`）。
これを `EntryEntity` 群へ往復させるだけ。**field のみ保存すれば十分**（formula は再計算で復元）。

- **保存（自動保存・中断/再開 FR-12）**: 各 `setField`/`applyAction` 後に、変化した field セルを
  `EntryEntity`（playerId/round/fieldId/value）として upsert。`status="active"`。
- **復元**: `GameRuntime(schema:playerNames:)` を作り、保存済み `EntryEntity` を順に
  `runtime.setField(fieldId, player:, round:, value:)` で適用 → `recompute()` 済みの状態が戻る。
  `roundCount` が増えていた場合は復元前に `addRound()` を必要回数。
- **終了（FR-13）**: `runtime.evaluateResult()` の `winnerIndices` / `standings` を `ResultEntity` へ。
  `status="finished"`, `finishedAt` を設定。

> 注意: `Value` ⇄ JSON は小さなエンコーダを用意（number/bool/string/missing の4種）。
> `EntryEntity.valueJSON` に格納。missing は保存不要（未入力＝既定値）。

## 4. ビューモデル（推奨）

```swift
@Observable final class GameViewModel {
    let runtime: GameRuntime
    var context = RenderContext(activePlayer: 0, activeRound: 0)

    func tapAction(_ id: String, input: Value? = nil) {
        runtime.applyAction(id, player: context.activePlayer, round: context.activeRound, input: input)
        persistChangedCells()          // §3
    }
    func setField(_ id: String, _ v: Value) {
        runtime.setField(id, player: context.activePlayer, round: context.activeRound, value: v)
        persistChangedCells()
    }
    var result: GameResult { runtime.evaluateResult() }
}
```

コアは同期・決定的なので、`@Observable` は単純なラッパで足りる（async 不要）。

## 5. App Store / プライバシー（§12.1）

- データ収集なし（Nutrition Label = "Data Not Collected"）。通信を一切発生させない。
- AI は宣言的スキーマのみ生成・固定レンダラが解釈（2.5.2 適合）。`eval`/WebView-JS は不採用。

## 6. 残タスク・チェックリスト（MVP→v1 配線）

- [ ] App ターゲット作成・`ScoreForgeKit` 依存追加
- [ ] `LayoutRenderer` + リーフ部品（renderer-spec.md）
- [ ] `GameViewModel` と対局/結果画面
- [ ] SwiftData モデル + `GameRuntime` 往復変換（本書 §3）／自動保存・再開
- [ ] テンプレ一覧（`Presets.all` + 保存分）／セットアップ画面
- [ ] 履歴・再戦
- [ ] 生成画面 + `FoundationModels`（generation-pipeline.md）／可用性出し分け
- [ ] エクスポート/インポート UI（`TemplateTransfer` + 共有シート/Document Picker）
- [ ] ローカライズ（ja/en）・アクセシビリティ仕上げ
- [ ] `PreviewSeeder`（コアに小追加。generation-pipeline.md §7）

> コア側のロジックは 52 ユニットテストで担保済み。iOS 側は主に UI と OS 連携で、
> 上記の薄い変換層を除けば新規ロジックはほぼ不要。
