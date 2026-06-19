#if canImport(SwiftUI)
import SwiftUI
import ScoreForgeKit

/// A ready-to-use play screen: the schema's layout, an "add round" / undo bar,
/// and a live result strip. Drop this into a `NavigationStack` from the template
/// list (docs/ios-integration.md §2). A thin example, not the final design.
public struct GameScreen: View {
    @State private var vm: GameViewModel
    private let onFinish: ((GameResult) -> Void)?

    public init(runtime: GameRuntime, onFinish: ((GameResult) -> Void)? = nil) {
        _vm = State(initialValue: GameViewModel(runtime: runtime))
        self.onFinish = onFinish
    }

    public var body: some View {
        let result = vm.result
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LayoutRenderer(vm: vm, node: vm.schema.layout)

                if vm.schema.structure == .rounds, vm.schema.rounds?.fixed != true {
                    Button("ラウンドを追加", systemImage: "plus") { vm.addRound() }
                }

                ResultStrip(result: result, players: vm.players)
            }
            .padding()
        }
        .navigationTitle(vm.schema.name)
        .toolbar {
            Button("元に戻す", systemImage: "arrow.uturn.backward") { vm.undo() }
                .disabled(!vm.canUndo)
            if result.isFinished {
                Button("確定") { onFinish?(result) }
            }
        }
        .tint(Color(hex: vm.schema.themeColorHex) ?? .accentColor)
    }
}

/// Standings with the winner(s) highlighted (docs/design.md §10.4).
public struct ResultStrip: View {
    let result: GameResult
    let players: [String]

    public init(result: GameResult, players: [String]) {
        self.result = result
        self.players = players
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.isFinished ? "結果" : "現在の順位").font(.headline)
            ForEach(Array(result.standings.enumerated()), id: \.offset) { rank, standing in
                let isWinner = result.winnerIndices.contains(standing.player)
                HStack {
                    Text("\(rank + 1).")
                    Text(players.indices.contains(standing.player) ? players[standing.player] : "P\(standing.player + 1)")
                        .fontWeight(isWinner ? .bold : .regular)
                    Spacer()
                    Text(standing.score.displayText).monospacedDigit()
                    if isWinner { Image(systemName: "crown.fill").foregroundStyle(.yellow) }
                }
            }
        }
    }
}
#endif
