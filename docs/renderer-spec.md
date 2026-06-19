# レンダラ仕様（スキーマ → SwiftUI）

> 対象: 設計書 §10.2「Renderer」。`ScoreForgeKit`（クロスプラットフォームなコア）は実装済み。
> 本書は **iOS 側（Mac/Xcode・iOS 26 SDK 必須）** で実装する固定レンダラの設計メモ。
> ここで参照する `GameRuntime` などの API は `Sources/ScoreForgeKit/` に存在する確定済みのもの。

## 0. レンダラの責務

`LayoutNode` ツリー（§7.5）を再帰的に SwiftUI ビューへ写像し、値の表示は `GameRuntime`
の算出値にバインドしてリアクティブに更新する。**WebView / JS は使わない。全てネイティブ部品。**
未知ノードは安全な代替（プレースホルダ）に縮退する。

## 1. ランタイムとの接続

レンダラはスキーマを直接解釈せず、対局状態は必ず `GameRuntime` 経由で読み書きする。

```swift
// 読み取り（表示・テーブルセル）
runtime.value(of: id, player: p, round: r) -> Value      // Value.displayText で文字列化
// 書き込み（入力部品）
runtime.setField(fieldId, player: p, round: r, value: Value)
runtime.applyAction(actionId, player: p, round: r, input: Value?)
runtime.addRound()
runtime.undo() / runtime.canUndo
// 結果（勝者ハイライト）
runtime.evaluateResult() -> GameResult                   // isFinished / winnerIndices / standings
```

`GameRuntime` は `final class`。SwiftUI では薄い `@Observable` ラッパ（`GameViewModel`）で包み、
各 mutation 後に `objectWillChange` 相当を発火して再描画する想定。コア自体は同期・決定的なので、
ビューモデル側で「操作 → ランタイム呼び出し → 再描画」を行えばよい。

### RenderContext（重要）

スコープ付きフィールド（`perPlayer` / `perPlayerPerRound` 等）の入力部品は「いまどのセルを
編集するか」を知る必要がある。レンダラに以下の選択状態を持たせる:

```swift
struct RenderContext {
    var activePlayer: Int      // 現在編集対象のプレイヤー
    var activeRound: Int       // 現在のラウンド（freeform は 0 固定）
}
```

部品が対象セルを解決する規則（フィールドの `scope` に従う。`Scope.hasPlayer/hasRound` を利用）:

| scope | player | round |
|---|---|---|
| `global` | nil | nil |
| `perPlayer` | activePlayer | nil |
| `perRound` | nil | activeRound |
| `perPlayerPerRound` | activePlayer | activeRound |

プレイヤー選択は `playerHeader`（タブ/セグメント）で切り替える。

## 2. ノード種別 → ビュー写像

`LayoutNode.kind`（`LayoutNode.Kind`）で分岐。`kind == nil`（未知 type）は §4 のフォールバックへ。

### コンテナ
| kind | SwiftUI | 備考 |
|---|---|---|
| `vstack` | `VStack(spacing:)` | `node.spacing` を反映 |
| `hstack` | `HStack(spacing:)` | |
| `grid` | `Grid` / `LazyVGrid` | 列数は子要素数から推定 or 既定2列 |
| `card` | 角丸 + 影の `VStack` | `themeColorHex` を淡く背景に |

### リーフ
| kind | SwiftUI | バインド先 | 操作 |
|---|---|---|---|
| `counter` | `Stepper` 風＋大きな ± ボタン | `node.field` | `setField`（現在値 ± `node.step`、既定1） |
| `stepper` | `Stepper` | `node.field` | 同上 |
| `numberInput` | `TextField`(decimalPad) | `node.field` | `setField(.number)` |
| `textInput` | `TextField` | `node.field` | `setField(.string)` |
| `toggle` | `Toggle` | `node.field`(bool) | `setField(.bool)` |
| `segmented` | `Picker(.segmented)` | `node.field`(select) | options から選択→`setField(.string(value))` |
| `label` | `Text` | `node.bind` | 表示のみ。`Value.displayText`（欠損は「—」） |
| `badge` | 角丸 `Text` | `node.bind` | 順位/状態の強調表示 |
| `scoreTable` | `Grid`（行=ラウンド, 列=プレイヤー） | `rowField`/`columnGroup`/`cellFields` | §3 |
| `playerHeader` | プレイヤー切替＋名前 | — | activePlayer を更新 |
| `actionBar` | ボタン列 | `node.actions` | 各 `applyAction(id, player:activePlayer, round:activeRound)` |
| `spacer` | `Spacer` | — | |
| `divider` | `Divider` | — | |

`input()` を使うアクション（`applyExpression` 内）は、押下前に**数値入力シート/小ダイアログ**で
入力値を集め、`applyAction(..., input: .number(x))` に渡す。アクションの効果に `input()` が含まれるかは、
式文字列に `input(` を含むかで判定してよい（簡易）。

## 3. scoreTable の描画

`rowField:"round"`, `columnGroup:"player"`, `cellFields:[...]` を前提に:

- 行: `runtime.state.roundIndices`（`0..<roundCount`）。
- 列: `runtime.state.players`（名前は `state.players[i]`）。
- セル: `cellFields` の各 id を縦に並べる。値は `runtime.value(of: id, player: col, round: row).displayText`。
- 編集可否: `cellFields` に含まれる **field** はタップで該当セルを `activePlayer/activeRound` に設定し、
  下部の入力部品で編集（あるいはセル内インライン編集）。**formula** は読み取り専用。
  id が field か formula かは `schema.fields` / `schema.formulas` の id 集合で判定。
- 末尾に「ラウンド追加」行（`schema.rounds?.fixed != true` のとき `addRound()`）。

## 4. 未知ノード・不正バインドのフォールバック（§7.5）

- `node.kind == nil`: 小さな警告ラベル（例: 「未対応の部品: \(node.type)」）を表示して継続。**クラッシュさせない。**
- `label.bind` / `field` が存在しない id: 「—」を表示し、デバッグ時のみ警告。
- そもそもレイアウト全体が壊れている場合は描画前に `DefaultLayoutBuilder.build(for:)` で作り直す
  選択肢がある（インポート/生成経路では `SchemaRepair` が既にこれを保証している）。

## 5. スタイルのクランプ（§10.2「安全な範囲に丸める」）

`LayoutNode.Style` を以下の範囲に丸めてから適用する:

```swift
let fontScale = min(max(style.fontScale ?? 1.0, 0.8), 2.0)   // 極端な倍率を防ぐ
let emphasis  = style.emphasis ?? false                      // → .fontWeight(.bold)
let color     = Color(hex: style.colorHex) ?? .primary       // 解析失敗は既定色
// alignment は "leading"/"center"/"trailing" のみ許可、未知は .center
```

## 6. アクセシビリティ（FR-18）

- すべての入力部品に `accessibilityLabel`（`field.label` / `action.label`）。
- Dynamic Type 対応（固定 px を避け `fontScale` は相対指定）。
- 最小タップ領域 44pt（counter の ± ボタン）。
- VoiceOver 読み上げ順は「プレイヤー → 合計 → 操作」。

## 7. 最小実装ステップ（提案）

1. `GameViewModel`（`@Observable`、`GameRuntime` を保持）。
2. `LayoutRenderer`（`LayoutNode` → `AnyView` の再帰関数）＋ `RenderContext`。
3. リーフ部品を上表の順で実装（まず `playerHeader` / `counter` / `label` / `actionBar` / `scoreTable`）。
4. 結果画面: `evaluateResult()` の `winnerIndices` をハイライト、`standings` を順位表示。
5. プリセット（`Presets.all`）で全部品を実機確認 → AI生成・インポート経路へ。
