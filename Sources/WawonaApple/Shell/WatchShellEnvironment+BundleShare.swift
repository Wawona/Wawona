#if os(watchOS)
import Foundation

extension WWNWatchShellEnvironment {
    static func applyBundleShareEnv() {
        WWNBundleShareEnvironment.apply()
    }
}

#endif
