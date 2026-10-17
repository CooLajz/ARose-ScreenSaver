import AppKit
import Metal
import QuartzCore
import Darwin

/// Metal renders halos and antialiased points. Core Graphics is used only for
/// the small optional debug label and reference snapshots. Simulation stays on CPU.
final class RoseMetalRenderer {
    let device: MTLDevice
    let surface = CAMetalLayer()
    private let queue: MTLCommandQueue
    private let additive: MTLRenderPipelineState
    private let interpolatePipeline: MTLComputePipelineState
    private let rainbowTable: MTLBuffer
    private let dots: MTLRenderPipelineState
    private var colors = [Double: (SIMD4<Float>, SIMD4<Float>)]()
    private let over: MTLRenderPipelineState
    private var pointAtlas: MTLTexture?
    private var pointDiameter: CGFloat = -1
    private var pointTile = 0
    private let atlas: MTLTexture
    private let available = DispatchSemaphore(value: 3)
    private var slotIndex = 0
    private(set) var frameStatistics = (submitted: 0, busy: 0, noDrawable: 0)
    private(set) var instanceBufferAllocations = 0
    // Reserve the longest supported trail up front per slot. Growing by one
    // history frame would reallocate both buffers throughout the opening motion.
    private let maximumTrailPoints = 20 * RoseEngine.pointCount
    private let snapshotSlot = Slot()
    private(set) var lastSnapshotPreparationCPU = 0.0
    private(set) var lastSnapshotGPUTime = 0.0
    private let failureLock = NSLock()
    private var commandFailed = false
    private static func cpuTime() -> Double {
        var r = rusage(); getrusage(RUSAGE_SELF, &r)
        return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec)
            + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
    }
    private var slots = [Slot(), Slot(), Slot()]
    private final class Slot {
        var endpoints: MTLBuffer?
        var endpointRevision: UInt64?
        var halos: MTLBuffer?
        var instances: MTLBuffer?
        var buffer: MTLBuffer?
        var context: CGContext?
        var texture: MTLTexture?
    }
    private struct Sprite {
        var rect: SIMD4<Float>
        var parameters: SIMD4<Float> // halo: hue/opacity; point: phaseX/opacity/phaseY/slice
        var color = SIMD4<Float>(repeating: 0)
    }
    init?(sprites: [CGImage]) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { NSLog("ARose Metal: device or command queue unavailable"); return nil }
        self.device = device; self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            func pipeline(_ fragment: String, additive: Bool) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = library.makeFunction(name: "roseVertex")
                d.fragmentFunction = library.makeFunction(name: fragment)
                let c = d.colorAttachments[0]!
                c.pixelFormat = .bgra8Unorm; c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                c.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: d)
            }
            interpolatePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "prepareInterpolated")!)
            dots = try pipeline("pointFragment", additive: false)
            additive = try pipeline("halo", additive: true)
            over = try pipeline("foreground", additive: false)
        } catch { NSLog("ARose Metal initialization: %@", String(describing: error)); return nil }
        // Convert the calibrated rainbow to device RGB once, not per displayed point.
        var rainbow = [SIMD4<Float>]()
        for i in 0...4096 {
            for saturation in [0.9, 0.25] {
                let c = NSColor(calibratedHue: Double(i % 4096) / 4096, saturation: saturation,
                                brightness: 1, alpha: 1).usingColorSpace(.deviceRGB)!
                rainbow.append(SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1))
            }
        }
        guard let table = device.makeBuffer(bytes: rainbow, length: rainbow.count * MemoryLayout<SIMD4<Float>>.stride,
                                             options: .storageModeShared) else { return nil }
        rainbowTable = table
        let d = MTLTextureDescriptor()
        d.textureType = .type2DArray; d.pixelFormat = .rgba8Unorm
        d.width = 64; d.height = 64; d.arrayLength = sprites.count
        d.usage = .shaderRead; d.storageMode = .shared
        guard let atlas = device.makeTexture(descriptor: d) else { return nil }
        for (i, image) in sprites.enumerated() {
            guard let c = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                    bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            c.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            atlas.replace(region: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0, slice: i,
                          withBytes: c.data!, bytesPerRow: 256, bytesPerImage: 16384)
        }
        self.atlas = atlas
        surface.device = device; surface.pixelFormat = .bgra8Unorm
        surface.framebufferOnly = true; surface.isOpaque = true
        surface.colorspace = CGColorSpaceCreateDeviceRGB()
        surface.maximumDrawableCount = 3
        surface.displaySyncEnabled = true
        surface.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
    }

    /// No blocking GPU wait on the display thread. Drop a presentation if all three
    /// resource slots are busy; the PAL simulation clock continues independently.
    func present(size: CGSize, backing: CGFloat, history: [[RoseEngine.ModernPoint]], glow: Double, previous: [[RoseEngine.ModernPoint]]? = nil, alpha: Double = 1, revision: UInt64? = nil,
                 foreground: ((CGContext) -> Void)? = nil, overlay: ((CGContext) -> Void)? = nil) -> Bool {
        failureLock.lock(); let failed = commandFailed; failureLock.unlock()
        guard !failed else { return false }
        guard available.wait(timeout: .now()) == .success else {
            frameStatistics.busy += 1; return true
        }
        let width = max(1, Int((size.width * backing).rounded()))
        let height = max(1, Int((size.height * backing).rounded()))
        let drawableSize = CGSize(width: width, height: height)
        if surface.drawableSize != drawableSize { surface.drawableSize = drawableSize }
        guard let drawable = surface.nextDrawable() else {
            // Temporary drawable starvation is not a device failure. Keep the
            // previous Metal image rather than flashing the CPU fallback layer.
            frameStatistics.noDrawable += 1
            available.signal(); return true
        }
        let slot = slots[slotIndex]
        guard let command = encode(target: drawable.texture, slot: slot, size: size, backing: backing,
                                   history: history, glow: glow, previous: previous, alpha: alpha, revision: revision, foreground: foreground, overlay: overlay) else {
            available.signal(); return false
        }
        slotIndex = (slotIndex + 1) % slots.count
        command.addCompletedHandler { [weak self, available] completed in
            if completed.status == .error, let self {
                self.failureLock.lock(); self.commandFailed = true; self.failureLock.unlock()
            }
            available.signal()
        }
        command.present(drawable); command.commit()
        frameStatistics.submitted += 1
        return true
    }

    /// Synchronous readback exists only for regression tests, never the display loop.
    func snapshot(size: CGSize, backing: CGFloat, history: [[RoseEngine.ModernPoint]], glow: Double, previous: [[RoseEngine.ModernPoint]]? = nil, alpha: Double = 1,
                  foreground: ((CGContext) -> Void)? = nil, overlay: ((CGContext) -> Void)? = nil) -> CGImage? {
        let width = Int(size.width * backing), height = Int(size.height * backing)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]; d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        let preparationStart = Self.cpuTime()
        guard let command = encode(target: texture, slot: snapshotSlot, size: size, backing: backing,
                                   history: history, glow: glow, previous: previous, alpha: alpha, foreground: foreground, overlay: overlay) else { return nil }
        lastSnapshotPreparationCPU = Self.cpuTime() - preparationStart
        command.commit(); command.waitUntilCompleted()
        lastSnapshotGPUTime = max(0, command.gpuEndTime - command.gpuStartTime)
        guard command.status == .completed else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // Preserve Core Graphics coverage of tiny ellipses, including its flattening
    // and antialiasing. Build only when pixel diameter changes, never per frame.
    // 32 subpixel phases plus an endpoint allow interpolation without tile bleed.
    private func preparePoints(diameter: CGFloat) -> Bool {
        if pointDiameter == diameter { return true }
        let tile = 2 * Int(ceil(diameter / 2)) + 3
        let width = tile * 33
        let d = MTLTextureDescriptor()
        d.textureType = .type2DArray; d.pixelFormat = .r8Unorm
        d.width = width; d.height = width; d.arrayLength = 2
        d.usage = .shaderRead; d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return false }
        for slice in 0..<2 {
            guard let c = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8,
                                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            c.setShouldAntialias(true); c.setAllowsAntialiasing(true)
            c.setFillColor(CGColor(gray: 1, alpha: 1))
            let radius = diameter * (slice == 0 ? 1 : 0.55) / 2
            let pad = CGFloat(tile / 2)
            for y in 0...32 { for x in 0...32 {
                // CGContext memory is top-down relative to its drawing coordinates.
                let cx = CGFloat(x * tile) + pad + CGFloat(x) / 32
                let cy = CGFloat(width - y * tile) - pad - CGFloat(y) / 32
                c.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            } }
            texture.replace(region: MTLRegionMake2D(0, 0, width, width), mipmapLevel: 0, slice: slice,
                            withBytes: c.data!, bytesPerRow: width, bytesPerImage: width * width)
        }
        pointAtlas = texture; pointDiameter = diameter; pointTile = tile
        return true
    }

    private func encode(target: MTLTexture, slot: Slot, size: CGSize, backing: CGFloat,
                        history: [[RoseEngine.ModernPoint]], glow: Double,
                        previous: [[RoseEngine.ModernPoint]]? = nil, alpha: Double = 1, revision: UInt64? = nil,
                        foreground: ((CGContext) -> Void)? = nil, overlay: ((CGContext) -> Void)? = nil) -> MTLCommandBuffer? {
        let width = target.width, height = target.height
        // Production only uploads a small debug label, never a full-screen bitmap.
        let overlayWidth = min(width, Int(512 * backing))
        let overlayHeight = min(height, Int(64 * backing))
        if foreground != nil || overlay != nil {
            let width = foreground != nil ? width : overlayWidth
            let height = foreground != nil ? height : overlayHeight
            if slot.texture?.width != width || slot.texture?.height != height {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
                d.usage = .shaderRead; d.storageMode = .shared
                let alignment = device.minimumLinearTextureAlignment(for: .rgba8Unorm)
                let rowBytes = ((width * 4 + alignment - 1) / alignment) * alignment
                slot.context = nil; slot.texture = nil; slot.buffer = nil
                guard let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
                      let texture = buffer.makeTexture(descriptor: d, offset: 0, bytesPerRow: rowBytes) else { return nil }
                slot.buffer = buffer; slot.texture = texture
                slot.context = CGContext(data: buffer.contents(), width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context = slot.context, slot.texture != nil else { return nil }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.saveGState(); context.scaleBy(x: backing, y: backing)
            if let foreground { foreground(context) }
            else {
                context.translateBy(x: -size.width + CGFloat(overlayWidth) / backing, y: 0)
                overlay?(context)
            }
            context.restoreGState()
        }
        guard let command = queue.makeCommandBuffer() else { return nil }
        let gpuCount = history.reduce(0) { $0 + $1.count }
        let interpolateOnGPU = previous != nil && foreground == nil
        if interpolateOnGPU && gpuCount > 0 {
            guard gpuCount <= maximumTrailPoints else { return nil }
            let diameter = max(1 / backing, min(1.8, min(size.width, size.height) / 600)) * backing
            guard preparePoints(diameter: diameter) else { return nil }
            if slot.endpoints == nil {
                slot.endpoints = device.makeBuffer(length: maximumTrailPoints * 2 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
            }
            if slot.halos == nil {
                slot.halos = device.makeBuffer(length: maximumTrailPoints * MemoryLayout<Sprite>.stride, options: .storageModeShared)
                instanceBufferAllocations += 1
            }
            if slot.instances == nil {
                slot.instances = device.makeBuffer(length: maximumTrailPoints * 2 * MemoryLayout<Sprite>.stride, options: .storageModeShared)
                instanceBufferAllocations += 1
            }
            guard let endpoints = slot.endpoints, let halos = slot.halos, let instances = slot.instances else { return nil }
            if revision == nil || slot.endpointRevision != revision {
                let output = endpoints.contents().bindMemory(to: SIMD4<Float>.self, capacity: maximumTrailPoints * 2)
                let old = previous!
                var index = 0
                for (age, points) in history.enumerated() {
                    let strength = Float(0.25 + 0.75 * Double(age + 1) / Double(history.count))
                    for (j, point) in points.enumerated() {
                        let before = old.count == history.count && old[age].count == points.count ? old[age][j] : point
                        output[index] = SIMD4(Float(before.x), Float(before.y), Float(before.hue), strength)
                        output[index + 1] = SIMD4(Float(point.x), Float(point.y), Float(point.hue), strength)
                        index += 2
                    }
                }
                slot.endpointRevision = revision
            }
            var parameters = [SIMD4(Float(width), Float(height), Float(min(size.width, size.height) / 640 * backing), Float(min(1, max(0, alpha)))),
                              SIMD4(Float(diameter), Float(glow), Float(pointTile), Float(gpuCount))]
            guard let compute = command.makeComputeCommandEncoder() else { return nil }
            compute.setComputePipelineState(interpolatePipeline)
            compute.setBuffer(endpoints, offset: 0, index: 0)
            compute.setBuffer(halos, offset: 0, index: 1)
            compute.setBuffer(instances, offset: 0, index: 2)
            compute.setBuffer(rainbowTable, offset: 0, index: 3)
            compute.setBytes(&parameters, length: 2 * MemoryLayout<SIMD4<Float>>.stride, index: 4)
            compute.dispatchThreads(MTLSize(width: gpuCount, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: interpolatePipeline.threadExecutionWidth, height: 1, depth: 1))
            compute.endEncoding()
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var viewport = SIMD2<Float>(Float(width), Float(height))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        if interpolateOnGPU && gpuCount > 0 && glow > 0 {
            encoder.setRenderPipelineState(additive); encoder.setVertexBuffer(slot.halos, offset: 0, index: 0)
            encoder.setFragmentTexture(atlas, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: gpuCount)
        }
        if !interpolateOnGPU && glow > 0 && !history.isEmpty {
            let scale = min(size.width, size.height) / 640
            let diameter = max(1 / backing, min(1.8, min(size.width, size.height) / 600))
            let halo = diameter * (4 + 12 * glow) * backing
            var instances = [Sprite](); instances.reserveCapacity(history.count * 96)
            for (age, points) in history.enumerated() {
                let alpha = glow * (0.25 + 0.75 * Double(age + 1) / Double(history.count)) * 0.5
                for p in points {
                    instances.append(Sprite(rect: SIMD4(Float((size.width/2 + p.x*scale)*backing - halo/2),
                                                        Float((size.height/2 - p.y*scale)*backing - halo/2), Float(halo), Float(halo)),
                                            parameters: SIMD4(Float(min(255, Int(p.hue*256))), Float(alpha), 0, 0)))
                }
            }
            let length = instances.count * MemoryLayout<Sprite>.stride
            if slot.halos == nil || slot.halos!.length < length {
                slot.halos = device.makeBuffer(length: max(length, maximumTrailPoints * MemoryLayout<Sprite>.stride), options: .storageModeShared)
                instanceBufferAllocations += 1
            }
            guard let buffer = slot.halos else { encoder.endEncoding(); return nil }
            _ = instances.withUnsafeBytes { memcpy(buffer.contents(), $0.baseAddress!, length) }
            encoder.setRenderPipelineState(additive); encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setFragmentTexture(atlas, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count)
        }
        if let texture = slot.texture, foreground != nil {
            var full = Sprite(rect: SIMD4(0, 0, Float(width), Float(height)), parameters: SIMD4(0, 1, 0, 0))
            encoder.setRenderPipelineState(over)
            encoder.setVertexBytes(&full, length: MemoryLayout<Sprite>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        } else if interpolateOnGPU {
            if gpuCount > 0 {
                encoder.setFragmentTexture(pointAtlas, index: 0)
                encoder.setRenderPipelineState(dots); encoder.setVertexBuffer(slot.instances, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: gpuCount * (glow > 0 ? 2 : 1))
            }
        } else {
            let scale = min(size.width, size.height) / 640
            let diameter = max(1 / backing, min(1.8, min(size.width, size.height) / 600)) * backing
            guard preparePoints(diameter: diameter) else { encoder.endEncoding(); return nil }
            var points = [Sprite](); points.reserveCapacity(history.count * 192)
            if colors.count > 8192 { colors.removeAll(keepingCapacity: true) }
            for (age, frame) in history.enumerated() {
                let alpha = Float(0.25 + 0.75 * Double(age + 1) / Double(history.count))
                for p in frame {
                    let pair: (SIMD4<Float>, SIMD4<Float>)
                    if let cached = colors[p.hue] { pair = cached }
                    else {
                        func color(_ saturation: CGFloat) -> SIMD4<Float> {
                            let c = NSColor(calibratedHue: p.hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.deviceRGB)!
                            return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1)
                        }
                        pair = (color(0.9), color(0.25)); colors[p.hue] = pair
                    }
                    let x = Float((size.width / 2 + p.x * scale) * backing)
                    let y = Float((size.height / 2 - p.y * scale) * backing)
                    func append(_ slice: Float, _ color: SIMD4<Float>, _ opacity: Float) {
                        let extent = Float(pointTile), pad = Float(pointTile / 2)
                        points.append(Sprite(rect: SIMD4(floor(x) - pad, floor(y) - pad, extent, extent),
                                             parameters: SIMD4(x - floor(x), opacity, y - floor(y), slice), color: color))
                    }
                    append(0, pair.0, alpha)
                    if glow > 0 { append(1, pair.1, alpha * Float(glow * 0.8)) }
                }
            }
            if !points.isEmpty {
                let length = points.count * MemoryLayout<Sprite>.stride
                if slot.instances == nil || slot.instances!.length < length {
                    slot.instances = device.makeBuffer(length: max(length, maximumTrailPoints * 2 * MemoryLayout<Sprite>.stride), options: .storageModeShared)
                    instanceBufferAllocations += 1
                }
                guard let buffer = slot.instances else { encoder.endEncoding(); return nil }
                _ = points.withUnsafeBytes { memcpy(buffer.contents(), $0.baseAddress!, length) }
                encoder.setFragmentTexture(pointAtlas, index: 0)
                encoder.setRenderPipelineState(dots)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: points.count)
            }
        }
        if overlay != nil, foreground == nil, let texture = slot.texture {
            var label = Sprite(rect: SIMD4(Float(width - overlayWidth), Float(height - overlayHeight), Float(overlayWidth), Float(overlayHeight)), parameters: SIMD4(0, 1, 0, 0))
            encoder.setRenderPipelineState(over)
            encoder.setVertexBytes(&label, length: MemoryLayout<Sprite>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        encoder.endEncoding()
        return command
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Sprite { float4 rect; float4 parameters; float4 color; };
    kernel void prepareInterpolated(device const float4 *endpoints [[buffer(0)]],
        device Sprite *halos [[buffer(1)]], device Sprite *points [[buffer(2)]],
        device const float4 *rainbow [[buffer(3)]], constant float4 *params [[buffer(4)]],
        uint i [[thread_position_in_grid]]) {
        float4 geometry = params[0], style = params[1];
        if (i >= uint(style.w)) return;
        float4 a = endpoints[i*2], b = endpoints[i*2+1];
        float delta = b.z-a.z;
        if (delta > 0.5) delta -= 1; if (delta < -0.5) delta += 1;
        float hue = fract(a.z + delta * geometry.w);
        float2 position = mix(a.xy,b.xy,geometry.w) * geometry.z;
        float haloSize = style.x * (4 + 12 * style.y);
        halos[i] = Sprite{float4(geometry.xy/2 + float2(position.x,-position.y) - haloSize/2,haloSize,haloSize),
                          float4(min(255.0,floor(hue*256)),style.y*b.w*0.5,0,0),float4(0)};
        float2 pixel = geometry.xy/2 + float2(position.x,-position.y);
        float2 phase = fract(pixel);
        float4 rect = float4(floor(pixel)-floor(style.z/2),style.z,style.z);
        float lookup = hue * 4096; uint base = uint(floor(lookup)); float t = fract(lookup);
        uint count = style.y > 0 ? 2 : 1;
        for (uint slice=0; slice<count; ++slice) {
            float4 color = mix(rainbow[base*2+slice],rainbow[(base+1)*2+slice],t);
            points[i*count+slice] = Sprite{rect,float4(phase.x,b.w*(slice==0?1:style.y*0.8),phase.y,float(slice)),color};
        }
    }
    struct Out { float4 position [[position]]; float2 uv; float4 params [[flat]]; float4 color [[flat]]; float2 extent [[flat]]; };
    vertex Out roseVertex(uint v [[vertex_id]], uint i [[instance_id]],
                    constant Sprite *sprites [[buffer(0)]], constant float2 &viewport [[buffer(1)]]) {
        const float2 corners[] = {float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};
        Sprite s = sprites[i]; float2 p = s.rect.xy + corners[v] * s.rect.zw;
        Out o; o.position = float4(p.x/viewport.x*2-1,1-p.y/viewport.y*2,0,1);
        o.uv=corners[v]; o.params=s.parameters; o.color=s.color; o.extent=s.rect.zw; return o;
    }
    fragment float4 halo(Out in [[stage_in]], texture2d_array<float> image [[texture(0)]]) {
        constexpr sampler s(coord::normalized, address::clamp_to_zero, filter::linear);
        float2 footprint = fwidth(in.uv) * 0.25;
        float4 light = image.sample(s,in.uv + float2(-footprint.x,-footprint.y),uint(in.params.x))
                     + image.sample(s,in.uv + float2( footprint.x,-footprint.y),uint(in.params.x))
                     + image.sample(s,in.uv + float2(-footprint.x, footprint.y),uint(in.params.x))
                     + image.sample(s,in.uv + float2( footprint.x, footprint.y),uint(in.params.x));
        return light * (in.params.y * 0.25);
    }
    fragment float4 pointFragment(Out in [[stage_in]], texture2d_array<float> coverage [[texture(0)]]) {
        float2 phase = in.params.xz * 32.0;
        uint2 base = uint2(floor(phase)); float2 blend = fract(phase);
        uint2 pixel = uint2(in.uv * in.extent);
        uint tile = uint(in.extent.x), slice = uint(in.params.w);
        float a = coverage.read(base * tile + pixel, slice).r;
        float b = coverage.read((base + uint2(1,0)) * tile + pixel, slice).r;
        float c = coverage.read((base + uint2(0,1)) * tile + pixel, slice).r;
        float d = coverage.read((base + uint2(1,1)) * tile + pixel, slice).r;
        float alpha = mix(mix(a,b,blend.x), mix(c,d,blend.x), blend.y) * in.params.y;
        return float4(in.color.rgb * alpha, alpha);
    }
    fragment float4 foreground(Out in [[stage_in]], texture2d<float> image [[texture(0)]]) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
        return image.sample(s,in.uv);
    }
    """
}
