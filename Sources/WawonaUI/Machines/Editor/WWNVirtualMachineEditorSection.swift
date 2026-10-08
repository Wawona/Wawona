import SwiftUI
import WawonaModel
#if canImport(WawonaUI)
import WawonaUI
#endif

/// Native controls bridge the existing profile schema to Relay's Rust validation.
#if os(iOS)
@available(iOS 16.0, *)
#endif
struct WWNVirtualMachineEditorSection: View {
  @ObservedObject var draft: WWNMachineEditorDraft

  private func text(_ key: String, fallback: String = "") -> Binding<String> {
    Binding(
      get: { draft.vmSettings[key] as? String ?? fallback },
      set: { draft.vmSettings[key] = $0 }
    )
  }

  private func integer(_ key: String, fallback: Int) -> Binding<Int> {
    Binding(
      get: { (draft.vmSettings[key] as? NSNumber)?.intValue ?? fallback },
      set: { draft.vmSettings[key] = $0 }
    )
  }

  private func numberText(_ key: String, fallback: Int) -> Binding<String> {
    let value = integer(key, fallback: fallback)
    return Binding(
      get: { String(value.wrappedValue) },
      set: { if let number = Int($0) { value.wrappedValue = number } }
    )
  }

  var body: some View {
    WWNEditorCard(
      icon: "desktopcomputer.and.macbook",
      title: "Virtual Machine",
      tint: WWNTagPalette.indigo,
      info: "Wawona Relay runs the guest. Memory and storage changes apply after stopping and starting. Storage can grow but cannot shrink. Changing the VM Identifier selects a different disk."
    ) {
      WWNEditorFieldRow("Backend", icon: "cpu") {
        Text("Relay").foregroundColor(.secondary)
      }
      WWNEditorFieldRow("VM Identifier") {
        WawonaTextField("Automatic", text: text("vmIdentifier"))
          .autocorrectionDisabled()
          .accessibility(identifier: "wwn.vm.identifier")
      }
      WWNEditorFieldRow("NixOS guest") {
        Picker("NixOS guest", selection: text("guestVariant", fallback: "4k")) {
          Text("NixOS 4K pages").tag("4k")
          Text("NixOS 16K pages").tag("16k")
        }
        .wwnPlatformPickerStyle()
        .accessibility(identifier: "wwn.vm.guest")
      }
      NixGenerationPicker(
        machineId: draft.relayMachineId,
        vmIdentifier: (draft.vmSettings["vmIdentifier"] as? String) ?? "",
        generation: Binding(
          get: {
            let number = (draft.vmSettings["nixosGeneration"] as? NSNumber)?.intValue
              ?? (draft.vmSettings["nixosGeneration"] as? Int)
              ?? 0
            return number > 0 ? number : nil
          },
          set: { value in
            if let value, value > 0 {
              draft.vmSettings["nixosGeneration"] = value
            } else {
              draft.vmSettings.removeValue(forKey: "nixosGeneration")
            }
          }
        )
      )
      WWNEditorFieldRow("Memory (MiB)") {
        WWNEditorNumberField(
          text: numberText("memoryMB", fallback: 2048), range: 256...4096, step: 256
        )
        .accessibility(identifier: "wwn.vm.memory")
      }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Storage")
          Spacer()
          Text("\(integer("diskGiB", fallback: 8).wrappedValue) GiB")
            .foregroundColor(.secondary)
        }
        Slider(
          value: Binding(
            get: { Double(integer("diskGiB", fallback: 8).wrappedValue) },
            set: { integer("diskGiB", fallback: 8).wrappedValue = Int($0.rounded()) }
          ),
          in: Double(max(4, min(draft.initialVMDiskGiB, 64)))...64,
          step: 1
        )
        .accessibility(label: Text("Virtual machine storage"))
        .accessibility(identifier: "wwn.vm.storage")
        HStack {
          Text("\(max(4, min(draft.initialVMDiskGiB, 64))) GiB")
          Spacer()
          Text("64 GiB")
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }
      NixConfigurationEditor(files: Binding(
        get: { draft.vmSettings["nixFiles"] as? [String: String] ?? [:] },
        set: { draft.vmSettings["nixFiles"] = $0 }
      ))
      WWNEditorFieldRow("Notes") {
        WawonaTextField("Notes", text: text("notes"))
      }
    }
  }
}
