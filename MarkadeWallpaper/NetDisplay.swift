import AppKit
import MetalKit

final class NetDisplay {
    private let window: NSWindow
    private let view: MTKView

    init(screen: NSScreen, renderer: NetRenderer) {
        view = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        view.framebufferOnly = true
        view.colorPixelFormat = NetRenderer.pixelFormat
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.autoResizeDrawable = false
        view.preferredFramesPerSecond = 15
        view.layer?.magnificationFilter = .nearest
        view.delegate = renderer

        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = NSColor(srgbRed: 2 / 255, green: 7 / 255, blue: 5 / 255, alpha: 1)
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
    }

    func update(still: Bool, asleep: Bool) {
        let hidden = asleep || !window.occlusionState.contains(.visible)
        view.enableSetNeedsDisplay = still
        view.isPaused = still || hidden
        if still && !hidden { view.needsDisplay = true }
    }

    func close() {
        view.isPaused = true
        view.delegate = nil
        window.close()
    }
}

final class NetRenderer: NSObject, MTKViewDelegate {
    static let pixelFormat = MTLPixelFormat.bgra8Unorm
    private static let pixelPt: CGFloat = 3

    let device = MTLCreateSystemDefaultDevice()
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var start = CACurrentMediaTime()

    private struct Uniforms {
        var res: SIMD2<Float>; var px: Float; var t: Float; var fade: Float
        var rip: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    }

    override init() {
        super.init()
        guard let device else { print("[wallpaper] no Metal device"); return }
        let lib: MTLLibrary
        do { lib = try device.makeLibrary(source: flowingNetShaderSource, options: nil) }
        catch { print("[wallpaper] shader: \(error)"); return }
        guard let vfn = lib.makeFunction(name: "flowingNetVertex"),
              let ffn = lib.makeFunction(name: "flowingNetFragment") else { print("[wallpaper] missing functions"); return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = Self.pixelFormat
        do { pipeline = try device.makeRenderPipelineState(descriptor: desc) }
        catch { print("[wallpaper] pipeline: \(error)") }
        queue = device.makeCommandQueue()
    }

    func restartClock() { start = CACurrentMediaTime() }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let pts = view.bounds.size
        guard pts.width > 1, pts.height > 1, let origin = view.window?.frame.origin else { return }
        let want = CGSize(width: (pts.width / Self.pixelPt).rounded(),
                          height: (pts.height / Self.pixelPt).rounded())
        if view.drawableSize != want { view.drawableSize = want }
        guard let pipeline, let queue, let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let r = NetTaps.read(origin: origin)
        let fps = r.contains { $0.z >= 0 } ? 30 : 15
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
        var u = Uniforms(res: SIMD2(Float(want.width), Float(want.height)),
                         px: Float(want.width / pts.width),
                         t: Float(CACurrentMediaTime() - start),
                         fade: 1,
                         rip: (r[0], r[1], r[2], r[3], r[4]))
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

enum NetTaps {
    static let max = 5
    static let life: CFTimeInterval = 2.4

    nonisolated(unsafe) private static var taps: [(point: CGPoint, start: CFTimeInterval)?] = Array(repeating: nil, count: max)
    nonisolated(unsafe) private static var next = 0

    static func emit(_ point: CGPoint) {
        taps[next] = (point, CACurrentMediaTime())
        next = (next + 1) % max
    }

    static func read(origin: CGPoint) -> [SIMD4<Float>] {
        let now = CACurrentMediaTime()
        return (0..<max).map { i in
            guard let t = taps[i] else { return SIMD4(0, 0, -1, 0) }
            let age = now - t.start
            if age > life { taps[i] = nil; return SIMD4(0, 0, -1, 0) }
            return SIMD4(Float(t.point.x - origin.x), Float(t.point.y - origin.y), Float(age), 0)
        }
    }
}
