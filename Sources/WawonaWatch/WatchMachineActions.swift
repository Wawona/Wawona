#if os(watchOS)
import SwiftUI
import WawonaModel

/// Row action picked in the long-press menu. Runs after the menu sheet is
/// gone so Edit can present its own sheet and Start its cover.
enum WatchMachineAction {
    case start
    case focus
    case stop
    case edit
    case delete
}

/// Long-press menu for a machine row. Same items and order as the iOS /
/// macOS card context menu: Start (or Stop), Edit, Delete, Tags, Pin.
struct WatchMachineActionsView: View {
    let profile: MachineProfile
    let running: Bool
    var onAction: (WatchMachineAction) -> Void

    @ObservedObject private var tagStore = WWNMachineTagStore.shared
    @ObservedObject private var pinStore = WWNMachinePinStore.shared
    @Environment(\.dismiss) private var dismiss

    private var pinned: Bool { pinStore.isPinned(profile.id) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if running {
                        Button { finish(.focus) } label: {
                            Label("Focus", systemImage: "scope")
                        }
                        .accessibilityIdentifier("wwn.watch.menu.focus")
                        Button(role: .destructive) { finish(.stop) } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .accessibilityIdentifier("wwn.watch.menu.stop")
                    } else {
                        Button { finish(.start) } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .accessibilityIdentifier("wwn.watch.menu.start")
                    }
                    Button { finish(.edit) } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("wwn.watch.menu.edit")
                    Button(role: .destructive) { finish(.delete) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(running)
                    .accessibilityIdentifier("wwn.watch.menu.delete")
                }
                Section {
                    NavigationLink {
                        WatchMachineTagsView(machineId: profile.id)
                    } label: {
                        HStack {
                            Label("Tags", systemImage: "tag")
                            Spacer(minLength: 4)
                            WatchTagDots(tags: tagStore.tags(for: profile.id))
                        }
                    }
                    .accessibilityIdentifier("wwn.watch.menu.tags")
                }
                Section {
                    Button {
                        pinStore.toggle(profile.id)
                        dismiss()
                    } label: {
                        Label(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
                    }
                    .disabled(!pinned && pinStore.limitReached)
                    .accessibilityIdentifier("wwn.watch.menu.pin")
                }
            }
            .navigationTitle(profile.name.isEmpty ? "Machine" : profile.name)
        }
    }

    private func finish(_ action: WatchMachineAction) {
        onAction(action)
        dismiss()
    }
}

/// Tag assignment for one machine: tap toggles a checkmark. New Tag creates
/// and assigns in one step.
struct WatchMachineTagsView: View {
    let machineId: String
    @ObservedObject private var tagStore = WWNMachineTagStore.shared

    var body: some View {
        List {
            ForEach(tagStore.tags) { tag in
                let assigned = tagStore.isAssigned(tag.id, to: machineId)
                Button {
                    tagStore.setAssigned(!assigned, tag: tag, to: machineId)
                } label: {
                    HStack(spacing: 8) {
                        WatchTagDot(colorHex: tag.colorHex, size: 10)
                        Text(tag.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if assigned {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityAddTraits(assigned ? .isSelected : [])
            }
            NavigationLink {
                WatchTagEditorView { name, colorHex in
                    let tag = tagStore.createTag(name: name, colorHex: colorHex)
                    tagStore.setAssigned(true, tag: tag, to: machineId)
                }
            } label: {
                Label("New Tag", systemImage: "plus")
            }
            .accessibilityIdentifier("wwn.watch.tags.new")
        }
        .navigationTitle("Tags")
    }
}

/// Name plus Finder-style color palette, the wrist form of `WWNTagEditorSheet`.
struct WatchTagEditorView: View {
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = WWNMachineTag.paletteHex[6]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Tag name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("wwn.watch.tags.name")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                    spacing: 6
                ) {
                    ForEach(WWNMachineTag.paletteHex, id: \.self) { hex in
                        Button { colorHex = hex } label: {
                            WatchTagDot(colorHex: hex, size: 28)
                                .overlay {
                                    if colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(hex)")
                        .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                    }
                }
                Button("Save") {
                    onSave(trimmedName, colorHex)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("wwn.watch.tags.save")
            }
        }
        .navigationTitle("New Tag")
    }
}

struct WatchTagDot: View {
    let colorHex: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Self.color(fromHex: colorHex))
            .frame(width: size, height: size)
    }

    static func color(fromHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return .gray
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

/// Overlapping dots for a machine's tags, Finder style.
struct WatchTagDots: View {
    let tags: [WWNMachineTag]

    var body: some View {
        HStack(spacing: -3) {
            ForEach(tags.prefix(3)) { tag in
                WatchTagDot(colorHex: tag.colorHex, size: 8)
                    .overlay(Circle().stroke(.black, lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
