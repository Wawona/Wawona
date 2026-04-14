import SwiftUI
import WawonaModel

struct WelcomeView: View {
    @ObservedObject var preferences: WawonaPreferences
    @State var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .blue.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GlassCard(cornerRadius: 28) {
                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .scaleEffect(pulse ? 1.12 : 1.0)
                    Text("Welcome to Wawona")
                        .font(.largeTitle.bold())
                    Text("One SwiftUI control surface for macOS, iOS, iPadOS, watchOS, and Android.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Add Your First Machine") {
                        preferences.hasCompletedWelcome = true
                        preferences.save()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .frame(maxWidth: 520)
            .padding()
        }
        .task {
            withAnimation(.easeInOut(duration: 1.2).repeatForever()) {
                pulse = true
            }
        }
    }
}
