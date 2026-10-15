#if os(macOS)
import AppKit
import Metal
import MetalKit

struct WwnTermCell {
    var cp: UInt32
    var fg: UInt32
    var bg: UInt32
    var attrs: UInt32
}

private struct GpuDim {
    var cols: UInt32
    var rows: UInt32
    var phase: UInt32
}

private struct GpuCell {
    var slot: UInt32
    var fg: UInt32
    var bg: UInt32
    var attr: UInt32
}

/// One instanced draw of the Rust viewport. Glyphs are stamped into an atlas
/// once. The frame does not rebuild an attributed string.
final class TermGpuView: MTKView, MTKViewDelegate {
    private var pipeline: MTLRenderPipelineState?
    private var queue: MTLCommandQueue?
    private var atlas: MTLTexture?
    private var cells = [GpuCell]()
    private var cols = 1
    private var rows = 1
    private var blinkOn = true
    private var cache: [UInt32: UInt32] = [:]
    private var nextSlot: UInt32 = 1
    private let atlasSide = 16
    private let glyph: Int = 16
    private var imagePipeline: MTLRenderPipelineState?
    private var pictures = [TermPicture]()
    private var cellW: Float = 8
    private var cellH: Float = 16

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        let device = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: device)
        delegate = self
        isPaused = true
        enableSetNeedsDisplay = true
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = true
        guard let device else { return }
        queue = device.makeCommandQueue()
        atlas = Self.makeAtlas(device)
        pipeline = Self.makePipeline(device, pixelFormat: colorPixelFormat)
        imagePipeline = Self.makeImagePipeline(device, pixelFormat: colorPixelFormat)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("unused") }

    func present(
        _ grid: [WwnTermCell], count: Int, cols: Int, rows: Int, blinkOn: Bool,
        pictures: [TermPicture], cellW: CGFloat, cellH: CGFloat
    ) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        self.blinkOn = blinkOn
        self.pictures = pictures
        self.cellW = Float(max(cellW, 1))
        self.cellH = Float(max(cellH, 1))
        let n = min(count, cols * rows)
        if cells.count != n { cells = Array(repeating: GpuCell(slot: 0, fg: 0, bg: 0, attr: 0), count: n) }
        for i in 0..<n {
            let cell = grid[i]
            cells[i] = GpuCell(slot: slot(cell.cp), fg: cell.fg, bg: cell.bg, attr: cell.attrs)
        }
        setNeedsDisplay(bounds)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !cells.isEmpty, let device, let drawable = currentDrawable,
            let pass = currentRenderPassDescriptor, let queue, let pipeline, let atlas
        else { return }
        let buffer = cells.withUnsafeBytes { raw -> MTLBuffer? in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
        guard let buffer, let cmd = queue.makeCommandBuffer(),
            let enc = cmd.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        var dim = GpuDim(cols: UInt32(cols), rows: UInt32(rows), phase: blinkOn ? 1 : 0)
        let behind = drawImages(enc, device, behind: true)
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&dim, length: MemoryLayout<GpuDim>.size, index: 1)
        enc.setFragmentTexture(atlas, index: 0)
        enc.setFragmentBytes(&dim, length: MemoryLayout<GpuDim>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: cells.count)
        let front = drawImages(enc, device, behind: false)
        enc.endEncoding()
        let kept = behind + front
        cmd.addCompletedHandler { _ in _ = kept.count }
        cmd.present(drawable)
        cmd.commit()
    }

    private func drawImages(_ enc: MTLRenderCommandEncoder, _ device: MTLDevice, behind: Bool) -> [MTLTexture] {
        guard let imagePipeline else { return [] }
        var held = [MTLTexture]()
        let gw = Float(max(cols, 1))
        let gh = Float(max(rows, 1))
        for pic in pictures where behind ? pic.z < 0 : pic.z >= 0 {
            guard pic.pxW > 0, pic.pxH > 0, pic.rgba.count >= pic.pxW * pic.pxH * 4 else { continue }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: pic.pxW, height: pic.pxH, mipmapped: false
            )
            desc.usage = [.shaderRead]
            guard let tex = device.makeTexture(descriptor: desc) else { continue }
            held.append(tex)
            pic.rgba.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                tex.replace(
                    region: MTLRegionMake2D(0, 0, pic.pxW, pic.pxH), mipmapLevel: 0,
                    withBytes: base, bytesPerRow: pic.pxW * 4
                )
            }
            let c0 = Float(pic.col) + Float(pic.xPx) / cellW
            let r0 = Float(pic.row) + Float(pic.yPx) / cellH
            let c1 = c0 + Float(max(pic.cols, 1))
            let r1 = r0 + Float(max(pic.rows, 1))
            func ndc(_ c: Float, _ r: Float) -> (Float, Float) {
                (-1 + (c / gw) * 2, 1 - (r / gh) * 2)
            }
            let p00 = ndc(c0, r0)
            let p10 = ndc(c1, r0)
            let p01 = ndc(c0, r1)
            let p11 = ndc(c1, r1)
            var quad: [Float] = [
                p00.0, p00.1, 0, 0, p10.0, p10.1, 1, 0, p01.0, p01.1, 0, 1,
                p10.0, p10.1, 1, 0, p11.0, p11.1, 1, 1, p01.0, p01.1, 0, 1,
            ]
            enc.setRenderPipelineState(imagePipeline)
            quad.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                enc.setVertexBytes(base, length: raw.count, index: 0)
            }
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        return held
    }

    private func slot(_ cp: UInt32) -> UInt32 {
        if cp < 33 { return 0 }
        if let hit = cache[cp] { return hit }
        if nextSlot >= UInt32(atlasSide * atlasSide) {
            cache.removeAll()
            nextSlot = 1
        }
        let slot = nextSlot
        nextSlot += 1
        cache[cp] = slot
        stamp(cp, slot: slot)
        return slot
    }

    private func stamp(_ cp: UInt32, slot: UInt32) {
        guard let atlas, let scalar = UnicodeScalar(cp) else { return }
        let w = glyph
        let h = glyph
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
            samplesPerPixel: 1, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite,
            bytesPerRow: w, bitsPerPixel: 8
        ), let pixels = rep.bitmapData else { return }
        let host = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let nerd = NSFont(name: "DejaVuSansM Nerd Font Mono", size: 12)
        let ch = Character(scalar)
        let font = macIsNerd(ch) ? (nerd ?? host) : host
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (String(ch) as NSString).draw(
            at: NSPoint(x: 0, y: 1),
            withAttributes: [.font: font, .foregroundColor: NSColor.white]
        )
        NSGraphicsContext.restoreGraphicsState()
        let region = MTLRegionMake2D(
            Int(slot % UInt32(atlasSide)) * w, Int(slot / UInt32(atlasSide)) * h, w, h
        )
        atlas.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: w)
    }

    private static func makeAtlas(_ device: MTLDevice) -> MTLTexture? {
        let side = 16 * 16
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: side, height: side, mipmapped: false
        )
        desc.usage = [.shaderRead]
        return device.makeTexture(descriptor: desc)
    }

    private static func makePipeline(_ device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct Cell { uint slot; uint fg; uint bg; uint attr; };
        struct VOut { float4 pos [[position]]; float2 uv; float4 fg; float4 bg; uint attr [[flat]]; };
        struct Dim { uint cols; uint rows; uint phase; };
        float4 unpack(uint c) {
          return float4(float((c >> 16) & 255) / 255.0, float((c >> 8) & 255) / 255.0, float(c & 255) / 255.0, 1);
        }
        vertex VOut wwn_term_vs(uint vid [[vertex_id]], uint iid [[instance_id]],
                                constant Cell *cells [[buffer(0)]], constant Dim &d [[buffer(1)]]) {
          float2 q[6] = { float2(0,0), float2(1,0), float2(0,1), float2(1,0), float2(1,1), float2(0,1) };
          Cell cell = cells[iid];
          float2 g = q[vid];
          if ((cell.attr & 4u) != 0u) g.x += (0.5 - g.y) * 0.25;
          uint col = iid % max(d.cols, 1u);
          uint row = iid / max(d.cols, 1u);
          float2 step = float2(2.0 / float(max(d.cols, 1u)), 2.0 / float(max(d.rows, 1u)));
          float2 ndc = float2(-1.0, 1.0) + float2(float(col) + g.x, -(float(row) + g.y)) * step;
          uint slot = cell.slot;
          float2 uv = (float2(slot % 16u, slot / 16u) + g) / 16.0;
          VOut o; o.pos = float4(ndc, 0, 1); o.uv = uv; o.fg = unpack(cell.fg); o.bg = unpack(cell.bg); o.attr = cell.attr;
          return o;
        }
        fragment float4 wwn_term_fs(VOut in [[stage_in]], texture2d<float> atlas [[texture(0)]],
                                    constant Dim &d [[buffer(0)]]) {
          constexpr sampler s(filter::linear, address::clamp_to_edge);
          float m = atlas.sample(s, in.uv).r;
          if ((in.attr & 1u) != 0u) m = max(m, atlas.sample(s, in.uv + float2(0.004, 0)).r);
          if ((in.attr & 16u) != 0u && d.phase == 0u) m = 0.0;
          float4 c = mix(in.bg, in.fg, m);
          float2 local = fract(in.uv * 16.0);
          if ((in.attr & 8u) != 0u && local.y > 0.86) c = in.fg;
          if ((in.attr & 32u) != 0u && abs(local.y - 0.5) < 0.07) c = in.fg;
          return c;
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil),
            let vs = lib.makeFunction(name: "wwn_term_vs"),
            let fs = lib.makeFunction(name: "wwn_term_fs")
        else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = pixelFormat
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    private static func makeImagePipeline(_ device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct IV { float4 pos [[position]]; float2 uv; };
        vertex IV wwn_img_vs(uint vid [[vertex_id]], constant float4 *v [[buffer(0)]]) {
          float4 q = v[vid];
          IV o; o.pos = float4(q.xy, 0, 1); o.uv = q.zw; return o;
        }
        fragment float4 wwn_img_fs(IV in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
          constexpr sampler s(filter::linear, address::clamp_to_edge);
          return tex.sample(s, in.uv);
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil),
            let vs = lib.makeFunction(name: "wwn_img_vs"),
            let fs = lib.makeFunction(name: "wwn_img_fs")
        else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = pixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: desc)
    }
}

struct TermPicture {
    var col: Int32
    var row: Int32
    var xPx: Int32
    var yPx: Int32
    var cols: Int
    var rows: Int
    var z: Int32
    var pxW: Int
    var pxH: Int
    var rgba: Data
}

private func macIsNerd(_ ch: Character) -> Bool {
    ch.unicodeScalars.allSatisfy { u in
        let v = u.value
        return (0xE000...0xF8FF).contains(v) || (0xF0000...0xFFFFD).contains(v) || (0x100000...0x10FFFD).contains(v)
    } && !ch.unicodeScalars.isEmpty
}
#endif
