import Foundation
#if canImport(MachO)
import MachO
#endif

/// `CKContainer(identifier:)` raises an Objective-C exception when the
/// process lacks the CloudKit entitlement (ad-hoc macOS Debug, unsigned tvOS
/// Simulator). Read our own signature first and never touch CloudKit
/// without it.
enum CloudSyncEntitlement {
    static func processHasCloudKit(container: String) -> Bool {
        #if canImport(MachO)
        guard let header = _dyld_get_image_header(0) else { return false }
        let slide = _dyld_get_image_vmaddr_slide(0)
        let needles = [Array("CloudKit".utf8), Array(container.utf8)]
        for region in entitlementRegions(header: header, slide: slide)
            where needles.allSatisfy({ contains(region, $0) })
        {
            return true
        }
        #endif
        return false
    }

    #if canImport(MachO)
    private static func entitlementRegions(
        header: UnsafePointer<mach_header>, slide: Int
    ) -> [UnsafeRawBufferPointer] {
        let raw = UnsafeRawPointer(header)
        let is64 = header.pointee.magic == MH_MAGIC_64
        var cursor = raw + (is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size)
        var linkedit: (vmaddr: UInt64, fileoff: UInt64)?
        var signature: (offset: UInt32, size: UInt32)?
        var regions: [UnsafeRawBufferPointer] = []

        for _ in 0..<header.pointee.ncmds {
            let lc = cursor.load(as: load_command.self)
            switch lc.cmd {
            case UInt32(LC_SEGMENT_64):
                let seg = cursor.load(as: segment_command_64.self)
                let name = segmentName(seg.segname)
                if name == "__LINKEDIT" {
                    linkedit = (seg.vmaddr, seg.fileoff)
                } else if name == "__TEXT" {
                    regions += sections(after: cursor + MemoryLayout<segment_command_64>.size,
                                        count: seg.nsects, slide: slide, is64: true)
                }
            case UInt32(LC_SEGMENT):
                let seg = cursor.load(as: segment_command.self)
                let name = segmentName(seg.segname)
                if name == "__LINKEDIT" {
                    linkedit = (UInt64(seg.vmaddr), UInt64(seg.fileoff))
                } else if name == "__TEXT" {
                    regions += sections(after: cursor + MemoryLayout<segment_command>.size,
                                        count: seg.nsects, slide: slide, is64: false)
                }
            case UInt32(LC_CODE_SIGNATURE):
                let cs = cursor.load(as: linkedit_data_command.self)
                signature = (cs.dataoff, cs.datasize)
            default:
                break
            }
            cursor += Int(lc.cmdsize)
        }

        if let linkedit, let signature, UInt64(signature.offset) >= linkedit.fileoff {
            let address = Int(linkedit.vmaddr) + slide + Int(UInt64(signature.offset) - linkedit.fileoff)
            if let base = UnsafeRawPointer(bitPattern: address) {
                regions.append(UnsafeRawBufferPointer(start: base, count: Int(signature.size)))
            }
        }
        return regions
    }

    /// Simulator builds carry entitlements in `__TEXT,__entitlements`.
    private static func sections(
        after start: UnsafeRawPointer, count: UInt32, slide: Int, is64: Bool
    ) -> [UnsafeRawBufferPointer] {
        var out: [UnsafeRawBufferPointer] = []
        var cursor = start
        for _ in 0..<count {
            let name: String
            let addr: Int
            let size: Int
            if is64 {
                let sect = cursor.load(as: section_64.self)
                name = segmentName(sect.sectname)
                addr = Int(sect.addr)
                size = Int(sect.size)
                cursor += MemoryLayout<section_64>.size
            } else {
                let sect = cursor.load(as: section.self)
                name = segmentName(sect.sectname)
                addr = Int(sect.addr)
                size = Int(sect.size)
                cursor += MemoryLayout<section>.size
            }
            if name == "__entitlements", let base = UnsafeRawPointer(bitPattern: addr + slide) {
                out.append(UnsafeRawBufferPointer(start: base, count: size))
            }
        }
        return out
    }

    private static func segmentName<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
    #endif

    private static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let first = needle[0]
        var i = 0
        let last = haystack.count - needle.count
        while i <= last {
            if haystack[i] == first {
                var j = 1
                while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
                if j == needle.count { return true }
            }
            i += 1
        }
        return false
    }
}
