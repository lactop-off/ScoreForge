#if canImport(SwiftUI)
import SwiftUI
import ScoreForgeKit

/// Recursively maps a `LayoutNode` tree to native SwiftUI, binding values to the
/// runtime via `GameViewModel`. Unknown node types degrade to a small warning
/// placeholder rather than failing (docs/design.md §7.5, docs/renderer-spec.md §2).
public struct LayoutRenderer: View {
    let vm: GameViewModel
    let node: LayoutNode

    public init(vm: GameViewModel, node: LayoutNode) {
        self.vm = vm
        self.node = node
    }

    public var body: some View {
        // Touch `revision` so the whole subtree refreshes after any mutation.
        let _ = vm.revision
        make(node)
    }

    // MARK: - Dispatch

    private func make(_ node: LayoutNode) -> AnyView {
        switch node.kind {
        case .vstack:
            return AnyView(VStack(alignment: .leading, spacing: spacing(node)) { childList(node) })
        case .hstack:
            return AnyView(HStack(spacing: spacing(node)) { childList(node) })
        case .grid:
            return AnyView(LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: spacing(node)) { childList(node) })
        case .card:
            return AnyView(VStack(alignment: .leading, spacing: spacing(node)) { childList(node) }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14)))
        case .playerHeader:
            return AnyView(PlayerHeader(vm: vm))
        case .scoreTable:
            return AnyView(ScoreTable(vm: vm, node: node))
        case .actionBar:
            return AnyView(ActionBar(vm: vm, ids: node.actions ?? []))
        case .counter:
            return AnyView(CounterView(vm: vm, node: node))
        case .stepper:
            return AnyView(StepperView(vm: vm, node: node))
        case .numberInput:
            return AnyView(NumberInputView(vm: vm, node: node))
        case .textInput:
            return AnyView(TextInputView(vm: vm, node: node))
        case .toggle:
            return AnyView(ToggleView(vm: vm, node: node))
        case .segmented:
            return AnyView(SegmentedView(vm: vm, node: node))
        case .label:
            return AnyView(LabelView(vm: vm, node: node))
        case .badge:
            return AnyView(BadgeView(vm: vm, node: node))
        case .spacer:
            return AnyView(Spacer())
        case .divider:
            return AnyView(Divider())
        case .none:
            return AnyView(UnknownNode(type: node.type))
        }
    }

    @ViewBuilder
    private func childList(_ node: LayoutNode) -> some View {
        ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
            LayoutRenderer(vm: vm, node: child)
        }
    }

    private func spacing(_ node: LayoutNode) -> CGFloat? { node.spacing.map(CGFloat.init) }
}

// MARK: - Leaf views

private struct UnknownNode: View {
    let type: String
    var body: some View {
        Label("未対応の部品: \(type)", systemImage: "questionmark.square.dashed")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct PlayerHeader: View {
    let vm: GameViewModel
    var body: some View {
        Picker("プレイヤー", selection: Binding(get: { vm.activePlayer }, set: { vm.activePlayer = $0 })) {
            ForEach(Array(vm.players.enumerated()), id: \.offset) { index, name in
                Text(name.isEmpty ? "P\(index + 1)" : name).tag(index)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct CounterView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.field ?? ""
        let step = node.step ?? 1
        HStack {
            Text(node.label ?? vm.field(id)?.label ?? id)
            Spacer()
            Button { vm.step(id, by: -step) } label: { Image(systemName: "minus.circle.fill") }
                .frame(minWidth: 44, minHeight: 44)
            Text(vm.cellValue(id).displayText).monospacedDigit().frame(minWidth: 40)
            Button { vm.step(id, by: step) } label: { Image(systemName: "plus.circle.fill") }
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct StepperView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.field ?? ""
        let step = node.step ?? 1
        Stepper(
            "\(node.label ?? vm.field(id)?.label ?? id): \(vm.cellValue(id).displayText)",
            onIncrement: { vm.step(id, by: step) },
            onDecrement: { vm.step(id, by: -step) }
        )
    }
}

private struct NumberInputView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.field ?? ""
        let text = Binding<String>(
            get: { vm.cellValue(id).displayText },
            set: { vm.setField(id, .number(Double($0) ?? 0)) }
        )
        HStack {
            Text(node.label ?? vm.field(id)?.label ?? id)
            Spacer()
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }
}

private struct TextInputView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.field ?? ""
        let text = Binding<String>(
            get: { if case .string(let s) = vm.cellValue(id) { return s } else { return "" } },
            set: { vm.setField(id, .string($0)) }
        )
        TextField(node.label ?? vm.field(id)?.label ?? id, text: text)
    }
}

private struct ToggleView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.field ?? ""
        let isOn = Binding<Bool>(
            get: { vm.cellValue(id).asBool },
            set: { vm.setField(id, .bool($0)) }
        )
        Toggle(node.label ?? vm.field(id)?.label ?? id, isOn: isOn)
    }
}

private struct SegmentedView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.field ?? ""
        let options = vm.field(id)?.options ?? []
        let selection = Binding<String>(
            get: { if case .string(let s) = vm.cellValue(id) { return s } else { return options.first?.value ?? "" } },
            set: { vm.setField(id, .string($0)) }
        )
        VStack(alignment: .leading) {
            Text(node.label ?? vm.field(id)?.label ?? id).font(.caption).foregroundStyle(.secondary)
            Picker(node.label ?? id, selection: selection) {
                ForEach(options, id: \.value) { option in Text(option.label).tag(option.value) }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct LabelView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.bind ?? ""
        let value = id.isEmpty ? Value.missing : vm.value(id, player: vm.activePlayer)
        let scale = min(max(node.style?.fontScale ?? 1.0, 0.8), 2.0)
        HStack {
            Text(vm.schema.formulas.first { $0.id == id }?.label ?? id)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.displayText)
                .font(.system(size: 17 * scale))
                .fontWeight((node.style?.emphasis ?? false) ? .bold : .regular)
        }
    }
}

private struct BadgeView: View {
    let vm: GameViewModel
    let node: LayoutNode
    var body: some View {
        let id = node.bind ?? ""
        Text(vm.value(id, player: vm.activePlayer).displayText)
            .font(.caption).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.tint.opacity(0.15), in: Capsule())
    }
}

private struct ActionBar: View {
    let vm: GameViewModel
    let ids: [String]
    @State private var inputText = ""
    @State private var pendingAction: String?

    var body: some View {
        HStack {
            ForEach(ids, id: \.self) { id in
                Button(vm.action(id)?.label ?? id) {
                    if vm.actionNeedsInput(id) { pendingAction = id } else { vm.tap(action: id) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .alert("値を入力", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
            TextField("数値", text: $inputText)
            Button("適用") {
                if let id = pendingAction { vm.tap(action: id, input: .number(Double(inputText) ?? 0)) }
                inputText = ""; pendingAction = nil
            }
            Button("キャンセル", role: .cancel) { inputText = ""; pendingAction = nil }
        }
    }
}

private struct ScoreTable: View {
    let vm: GameViewModel
    let node: LayoutNode

    var body: some View {
        let cells = node.cellFields ?? []
        ScrollView(.horizontal) {
            Grid(alignment: .leading) {
                GridRow {
                    Text("R").bold()
                    ForEach(Array(vm.players.enumerated()), id: \.offset) { _, name in
                        Text(name).bold()
                    }
                }
                Divider()
                ForEach(vm.roundIndices, id: \.self) { round in
                    GridRow {
                        Text("\(round + 1)").foregroundStyle(.secondary)
                        ForEach(vm.players.indices, id: \.self) { player in
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(cells, id: \.self) { fieldId in
                                    Text(vm.value(fieldId, player: player, round: round).displayText)
                                        .monospacedDigit()
                                        .onTapGesture {
                                            if vm.isField(fieldId) {
                                                vm.activePlayer = player
                                                vm.activeRound = round
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
