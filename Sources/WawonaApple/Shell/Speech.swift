import Foundation
import AVFoundation

/// Host speech for in-process `say`. Framework only.
public enum Speech {
    private static let synth = AVSpeechSynthesizer()

    public static func speak(_ text: String, voice: String?, rate: Float) -> Bool {
        let utterance = AVSpeechUtterance(string: text)
        if let voice, let matched = AVSpeechSynthesisVoice(identifier: voice)
            ?? AVSpeechSynthesisVoice(language: voice)
        {
            utterance.voice = matched
        }
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                             min(AVSpeechUtteranceMaximumSpeechRate, rate))
        synth.speak(utterance)
        return true
    }

    public static func listVoices() -> [String] {
        AVSpeechSynthesisVoice.speechVoices().map(\.identifier)
    }
}
