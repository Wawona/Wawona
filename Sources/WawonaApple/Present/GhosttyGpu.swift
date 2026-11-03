#if os(macOS)
import AppKit
import CoreText
import Darwin
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

/// Metal paint for Wawona Terminal cells (host GPU path).
/// Grid ownership is UniFFI `GhosttySurface`; C viewport is a bridge, not a second VT.
/// Glyphs stamp into an atlas once. Not a second VT engine.
final class GhosttyGpuView: MTKView, MTKViewDelegate {
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
    /// Mono cell aspect (~1:2). Scale with backingScale so retina is sharp.
    private var glyphW: Int = 16
    private var glyphH: Int = 32
    private var atlasScale: Int = 1
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
        autoResizeDrawable = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = true
        // Hits must reach WWNTermSurface for focus + keyDown. This view only draws.
        guard let device else { return }
        queue = device.makeCommandQueue()
        rebuildAtlas(device: device, scale: 2)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("unused") }

    /// Never become first responder or steal mouse hits from the VT host.
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Rebuild glyph atlas when the host backing scale changes (retina).
    func syncBackingScale(_ scale: CGFloat) {
        let s = max(1, Int(scale.rounded()))
        guard s != atlasScale, let device else { return }
        rebuildAtlas(device: device, scale: s)
    }

    private func rebuildAtlas(device: MTLDevice, scale: Int) {
        atlasScale = max(1, scale)
        glyphW = 16 * atlasScale
        glyphH = 32 * atlasScale
        cache.removeAll()
        nextSlot = 1
        atlas = Self.makeAtlas(device, glyphW: glyphW, glyphH: glyphH, atlasSide: atlasSide)
        pipeline = Self.makePipeline(
            device, pixelFormat: colorPixelFormat, atlasSide: atlasSide, glyphW: glyphW)
        imagePipeline = Self.makeImagePipeline(device, pixelFormat: colorPixelFormat)
    }

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
            clearAtlas()
        }
        let slot = nextSlot
        nextSlot += 1
        cache[cp] = slot
        stamp(cp, slot: slot)
        return slot
    }

    private func clearAtlas() {
        guard let atlas else { return }
        let bytes = glyphW * glyphH
        var zeros = [UInt8](repeating: 0, count: bytes)
        for row in 0..<atlasSide {
            for col in 0..<atlasSide {
                let region = MTLRegionMake2D(col * glyphW, row * glyphH, glyphW, glyphH)
                zeros.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    atlas.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: glyphW)
                }
            }
        }
    }

    private func stamp(_ cp: UInt32, slot: UInt32) {
        guard let atlas, let scalar = UnicodeScalar(cp) else { return }
        let w = glyphW
        let h = glyphH
        var pixels = [UInt8](repeating: 0, count: w * h)
        let pointSize = CGFloat(h) * 0.72
        let font = Self.resolveMonoFont(size: pointSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attr = NSAttributedString(string: String(Character(scalar)), attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                let space = CGColorSpace(name: CGColorSpace.linearGray),
                let ctx = CGContext(
                    data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                    space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            // Top-left origin matching Metal. Baseline near bottom of slot.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            let baseline = max(CGFloat(1), -font.descender + 1)
            ctx.textPosition = CGPoint(x: 1, y: baseline)
            CTLineDraw(line, ctx)
        }
        let region = MTLRegionMake2D(
            Int(slot % UInt32(atlasSide)) * w, Int(slot / UInt32(atlasSide)) * h, w, h
        )
        pixels.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            atlas.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: w)
        }
    }

    private static func resolveMonoFont(size: CGFloat) -> NSFont {
        WWNBundleShareEnvironment.registerBundledFontsIfNeeded()
        if let nerd = NSFont(name: "DejaVuSansM Nerd Font Mono", size: size) {
            return nerd
        }
        if let mono = NSFont(name: "DejaVu Sans Mono", size: size) {
            return mono
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func makeAtlas(
        _ device: MTLDevice, glyphW: Int, glyphH: Int, atlasSide: Int
    ) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: glyphW * atlasSide,
            height: glyphH * atlasSide,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        return device.makeTexture(descriptor: desc)
    }

    private static func makePipeline(
        _ device: MTLDevice, pixelFormat: MTLPixelFormat, atlasSide: Int, glyphW: Int
    ) -> MTLRenderPipelineState? {
        let side = UInt32(atlasSide)
        // One texel in atlas UV space (atlas width = glyphW * side).
        let boldUV = String(format: "%.8f", 1.0 / Double(glyphW * atlasSide))
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct Cell { uint slot; uint fg; uint bg; uint attr; };
        struct VOut { float4 pos [[position]]; float2 uv; float4 fg; float4 bg; uint attr [[flat]]; };
        struct Dim { uint cols; uint rows; uint phase; };
        float4 unpack(uint c) {
          return float4(float((c >> 16) & 255) / 255.0, float((c >> 8) & 255) / 255.0, float(c & 255) / 255.0, 1);
        }
        vertex VOut ghostty_term_vs(uint vid [[vertex_id]], uint iid [[instance_id]],
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
          float side = \(side).0;
          // Stamp atlas is Metal top-down (CGContext flipped at write time).
          float2 uv = (float2(slot % \(side)u, slot / \(side)u) + g) / side;
          VOut o; o.pos = float4(ndc, 0, 1); o.uv = uv; o.fg = unpack(cell.fg); o.bg = unpack(cell.bg); o.attr = cell.attr;
          return o;
        }
        fragment float4 ghostty_term_fs(VOut in [[stage_in]], texture2d<float> atlas [[texture(0)]],
                                    constant Dim &d [[buffer(0)]]) {
          constexpr sampler s(filter::linear, address::clamp_to_edge);
          float m = atlas.sample(s, in.uv).r;
          if ((in.attr & 1u) != 0u) m = max(m, atlas.sample(s, in.uv + float2(\(boldUV), 0)).r);
          if ((in.attr & 16u) != 0u && d.phase == 0u) m = 0.0;
          float4 c = mix(in.bg, in.fg, step(0.28, m));
          float2 local = fract(in.uv * \(side).0);
          if ((in.attr & 8u) != 0u && local.y > 0.86) c = in.fg;
          if ((in.attr & 32u) != 0u && abs(local.y - 0.5) < 0.07) c = in.fg;
          return c;
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil),
            let vs = lib.makeFunction(name: "ghostty_term_vs"),
            let fs = lib.makeFunction(name: "ghostty_term_fs")
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
#endif
