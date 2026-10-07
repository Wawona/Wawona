#if canImport(Metal) && !os(watchOS)
import Foundation

struct IlandCubeClient {
    let id: String
    let logModule: String
}

enum IlandNestedGpuClients {
    static let clients: [IlandCubeClient] = [
        IlandCubeClient(id: "kmscube", logModule: "KMSCUBE"),
        IlandCubeClient(id: "gbm-es2-demo", logModule: "GBM_ES2_DEMO"),
    ]

    static func client(for id: String) -> IlandCubeClient? {
        clients.first { $0.id == id }
    }

    static func prepareVirtualDrmFd() -> Bool {
        #if os(macOS)
        if IlandDrmBindings.drmEventPipeWrite >= 0 { return true }
        var pipeFD: [Int32] = [0, 0]
        guard pipe(&pipeFD) == 0 else { return false }
        guard dup2(pipeFD[0], IlandDrmBindings.drmVirtualFD) >= 0 else {
            close(pipeFD[0])
            close(pipeFD[1])
            return false
        }
        close(pipeFD[0])
        IlandDrmBindings.drmEventPipeWrite = pipeFD[1]
        return true
        #else
        return IlandDrmBindings.prepareVirtualFd() == 0
        #endif
    }

    static func entry(for id: String) -> (
        (_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    )? {
        switch id {
        case "kmscube":
            return IlandDrmBindings.kmscubeMain
        case "gbm-es2-demo":
            return IlandDrmBindings.gbmEs2DemoMain
        default:
            return nil
        }
    }

    static func runClient(id: String, logModule: String) {
        guard prepareVirtualDrmFd() else {
            NSLog("[\(logModule)] virtual DRM fd not ready")
            return
        }
        guard let entry = entry(for: id) else { return }
        id.withCString { idPtr in
            var argv: [UnsafeMutablePointer<CChar>?] = [
                UnsafeMutablePointer(mutating: idPtr),
                nil,
            ]
            argv.withUnsafeMutableBufferPointer { buffer in
                _ = entry(Int32(buffer.count - 1), buffer.baseAddress)
            }
        }
        NSLog("[\(logModule)] \(id) exit")
    }
}
#endif
