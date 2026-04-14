import SwiftUI
import WawonaModel

struct InputSettingsView: View {
    @ObservedObject var preferences: WawonaPreferences
    @State var keyRepeat = 30.0
    @State var inputProfile = "direct"

    var body: some View {
        Form {
            Section("Input") {
                TextField("Default Input Profile", text: $inputProfile)
                    .wawonaTextFieldNoAutocaps()
                    .autocorrectionDisabled()
                Slider(value: $keyRepeat, in: 1...60, step: 1) {
                    Text("Key Repeat")
                }
                Text("Repeat: \(Int(keyRepeat))")
            }
        }
        .onAppear {
            inputProfile = preferences.defaultInputProfile
        }
        .onDisappear {
            preferences.defaultInputProfile = inputProfile.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            preferences.save()
        }
    }
}
