// DDSDecoder.swift
// EVEOps
//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation
import CoreGraphics
import CoreImage
import Metal

/// Decodes DDS textures into CGImages usable anywhere (SceneKit material contents,
/// NSImage, etc.).
///
/// Software path (BC1/BC3): pure-CPU block decode → CGImage.
///
/// Metal path (BC7/DX10): MTKTextureLoader and ImageIO both refuse BC7.
///  1. Upload raw BC7 blocks to a managed/shared MTLTexture — Metal GPU can sample BC7
///     natively in fragment shaders.
///  2. Render to an RGBA8 private MTLTexture via a one-shot fullscreen-quad pass.
///  3. Use CIContext to read the private RGBA8 texture back to a CGImage.
/// Returning a CGImage (not an MTLTexture) is the key: SceneKit auto-generates the
/// 'u_diffuseTexture' GLSL uniform only for image types, not for MTLTexture objects.
enum DDSDecoder {

    // MARK:  Public: software decode (BC1/BC3)

    static func decode(_ data: Data) -> CGImage? {
        guard data.count >= 128,
              data[0] == 0x44, data[1] == 0x44, data[2] == 0x53, data[3] == 0x20
        else { return nil }

        let height = Int(data.le32(at: 12))
        let width  = Int(data.le32(at: 16))
        guard width > 0, height > 0 else { return nil }

        let fourCC = data.le32(at: 84)
        let pixels = Data(data.dropFirst(128))

        switch fourCC {
        case 0x31545844: return decodeBC1(pixels, w: width, h: height)  // "DXT1"
        case 0x35545844: return decodeBC3(pixels, w: width, h: height)  // "DXT5"
        default:         return nil
        }
    }

    // MARK:  Public: Metal path (BC7/DX10) → CGImage

    /// Uploads a BC7 DX10 DDS file to Metal, transcodes it to RGBA8 via a render
    /// pass, then reads the result back to a CGImage via CIContext.
    /// Returns nil for non-BC7 data or if Metal/CIContext setup fails.
    static func cgImage(from data: Data, device: MTLDevice) -> CGImage? {
        guard let rgba = rgbaTexture(from: data, device: device) else { return nil }
        // Wrap the private RGBA8 MTLTexture as a CIImage (GPU-side, lazy).
        // CIContext then renders it to CPU memory as a CGImage.
        guard let ci = CIImage(mtlTexture: rgba,
                               options: [.colorSpace: CGColorSpaceCreateDeviceRGB()])
        else { return nil }
        let ctx = CIContext(mtlDevice: device)
        let extent = CGRect(x: 0, y: 0, width: rgba.width, height: rgba.height)
        return ctx.createCGImage(ci, from: extent)
    }

    // MARK:  BC7 → RGBA8 MTLTexture (internal)

    private static func rgbaTexture(from data: Data, device: MTLDevice) -> MTLTexture? {
        guard data.count >= 148,
              data[0] == 0x44, data[1] == 0x44, data[2] == 0x53, data[3] == 0x20,
              data.le32(at: 84) == 0x30315844       // "DX10"
        else { return nil }

        let dxgi = data.le32(at: 128)
        guard dxgi == 98 || dxgi == 99 else { return nil }  // BC7_UNORM or _SRGB

        let w = Int(data.le32(at: 16))
        let h = Int(data.le32(at: 12))
        guard w > 0, h > 0 else { return nil }

        let bc7Fmt: MTLPixelFormat  = (dxgi == 99) ? .bc7_rgbaUnorm_srgb : .bc7_rgbaUnorm
        let rgbaFmt: MTLPixelFormat = (dxgi == 99) ? .rgba8Unorm_srgb    : .rgba8Unorm

        // Source: CPU-writable texture with raw BC7 blocks
        let srcDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: bc7Fmt, width: w, height: h, mipmapped: false)
        srcDesc.usage       = .shaderRead
        srcDesc.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let srcTex = device.makeTexture(descriptor: srcDesc) else { return nil }

        let blocksW     = (w + 3) / 4
        let blocksH     = (h + 3) / 4
        let bytesPerRow = blocksW * 16        // 16 bytes per BC7 4×4 block
        let dataOffset  = 148                  // 128-byte header + 20-byte DX10 ext
        guard dataOffset + bytesPerRow * blocksH <= data.count else { return nil }

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            srcTex.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                  size:   MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0,
                withBytes:   base.advanced(by: dataOffset),
                bytesPerRow: bytesPerRow)
        }

        // Destination: private RGBA8 texture (GPU-only, no mips needed — CGImage path)
        let dstDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: rgbaFmt, width: w, height: h, mipmapped: false)
        dstDesc.usage       = [.renderTarget, .shaderRead]
        dstDesc.storageMode = .private
        guard let dstTex = device.makeTexture(descriptor: dstDesc) else { return nil }

        // Compile a minimal fullscreen-quad copy shader at runtime
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct V2F { float4 pos [[position]]; float2 uv; };
        vertex V2F bc7v(uint i [[vertex_id]]) {
            const float2 p[4]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
            const float2 t[4]={float2(0,1),  float2(1,1), float2(0,0), float2(1,0)};
            V2F o; o.pos=float4(p[i],0,1); o.uv=t[i]; return o;
        }
        fragment float4 bc7f(V2F in [[stage_in]],
                              texture2d<float> src [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return src.sample(s, in.uv);
        }
        """
        guard let lib  = try? device.makeLibrary(source: src, options: nil),
              let vfn  = lib.makeFunction(name: "bc7v"),
              let ffn  = lib.makeFunction(name: "bc7f") else { return nil }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction   = vfn
        pipeDesc.fragmentFunction = ffn
        pipeDesc.colorAttachments[0].pixelFormat = rgbaFmt
        guard let pipe = try? device.makeRenderPipelineState(descriptor: pipeDesc) else { return nil }

        guard let queue  = device.makeCommandQueue(),
              let cmdbuf = queue.makeCommandBuffer() else { return nil }

        // Flush CPU writes → GPU (managed storage only; shared memory needs no sync)
        if srcTex.storageMode == .managed,
           let blitSync = cmdbuf.makeBlitCommandEncoder() {
            blitSync.synchronize(resource: srcTex)
            blitSync.endEncoding()
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = dstTex
        rpd.colorAttachments[0].loadAction  = .dontCare
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmdbuf.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
        enc.setRenderPipelineState(pipe)
        enc.setFragmentTexture(srcTex, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmdbuf.commit()
        cmdbuf.waitUntilCompleted()
        return cmdbuf.error == nil ? dstTex : nil
    }

    // MARK:  BC1 (DXT1)

    private static func decodeBC1(_ src: Data, w: Int, h: Int) -> CGImage? {
        var out = [UInt8](repeating: 255, count: w * h * 4)
        let bw = (w + 3) / 4, bh = (h + 3) / 4
        for by in 0..<bh {
            for bx in 0..<bw {
                let off = (by * bw + bx) * 8
                guard off + 8 <= src.count else { continue }
                let pal  = bc1Palette(src.le16(at: off), src.le16(at: off + 2), opaque: false)
                let cidx = src.le32(at: off + 4)
                writeBlock(pal, cidx: cidx, alpha: nil, abits: 0,
                           into: &out, bx: bx, by: by, w: w, h: h)
            }
        }
        return makeImage(out, w: w, h: h)
    }

    // MARK:  BC3 (DXT5)

    private static func decodeBC3(_ src: Data, w: Int, h: Int) -> CGImage? {
        var out = [UInt8](repeating: 255, count: w * h * 4)
        let bw = (w + 3) / 4, bh = (h + 3) / 4
        for by in 0..<bh {
            for bx in 0..<bw {
                let off = (by * bw + bx) * 16
                guard off + 16 <= src.count else { continue }
                let a0 = src[off], a1 = src[off + 1]
                var abits: UInt64 = 0
                for i in 0..<6 { abits |= UInt64(src[off + 2 + i]) << (i * 8) }
                let apal = bc3AlphaPalette(a0, a1)
                let pal  = bc1Palette(src.le16(at: off + 8), src.le16(at: off + 10), opaque: true)
                let cidx = src.le32(at: off + 12)
                writeBlock(pal, cidx: cidx, alpha: apal, abits: abits,
                           into: &out, bx: bx, by: by, w: w, h: h)
            }
        }
        return makeImage(out, w: w, h: h)
    }

    // MARK:  Shared helpers

    private struct RGBA { var r, g, b, a: UInt8 }

    private static func writeBlock(
        _ pal: [RGBA], cidx: UInt32,
        alpha: [UInt8]?, abits: UInt64,
        into out: inout [UInt8],
        bx: Int, by: Int, w: Int, h: Int
    ) {
        for py in 0..<4 {
            for px in 0..<4 {
                let pix  = py * 4 + px
                let ci   = Int((cidx >> (pix * 2)) & 0x3)
                let dx = bx * 4 + px, dy = by * 4 + py
                guard dx < w, dy < h else { continue }
                let base = (dy * w + dx) * 4
                out[base]     = pal[ci].r
                out[base + 1] = pal[ci].g
                out[base + 2] = pal[ci].b
                out[base + 3] = alpha != nil ? alpha![Int((abits >> (pix * 3)) & 0x7)] : pal[ci].a
            }
        }
    }

    private static func bc1Palette(_ c0: UInt16, _ c1: UInt16, opaque: Bool) -> [RGBA] {
        func r(_ v: UInt16) -> UInt8 { UInt8((v >> 11) & 0x1F) * 255 / 31 }
        func g(_ v: UInt16) -> UInt8 { UInt8((v >>  5) & 0x3F) * 255 / 63 }
        func b(_ v: UInt16) -> UInt8 { UInt8( v        & 0x1F) * 255 / 31 }
        let p0 = RGBA(r: r(c0), g: g(c0), b: b(c0), a: 255)
        let p1 = RGBA(r: r(c1), g: g(c1), b: b(c1), a: 255)
        if opaque || c0 > c1 {
            return [p0, p1,
                    RGBA(r: UInt8((Int(p0.r)*2+Int(p1.r)+1)/3),
                         g: UInt8((Int(p0.g)*2+Int(p1.g)+1)/3),
                         b: UInt8((Int(p0.b)*2+Int(p1.b)+1)/3), a: 255),
                    RGBA(r: UInt8((Int(p0.r)+Int(p1.r)*2+1)/3),
                         g: UInt8((Int(p0.g)+Int(p1.g)*2+1)/3),
                         b: UInt8((Int(p0.b)+Int(p1.b)*2+1)/3), a: 255)]
        } else {
            return [p0, p1,
                    RGBA(r: UInt8((Int(p0.r)+Int(p1.r))/2),
                         g: UInt8((Int(p0.g)+Int(p1.g))/2),
                         b: UInt8((Int(p0.b)+Int(p1.b))/2), a: 255),
                    RGBA(r: 0, g: 0, b: 0, a: 0)]
        }
    }

    private static func bc3AlphaPalette(_ a0: UInt8, _ a1: UInt8) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 8)
        p[0] = a0; p[1] = a1
        if a0 > a1 {
            for i in 1...6 { p[i+1] = UInt8((Int(a0)*(7-i)+Int(a1)*i+3)/7) }
        } else {
            for i in 1...4 { p[i+1] = UInt8((Int(a0)*(5-i)+Int(a1)*i+2)/5) }
            p[6] = 0; p[7] = 255
        }
        return p
    }

    private static func makeImage(_ pixels: [UInt8], w: Int, h: Int) -> CGImage? {
        var px = pixels
        return px.withUnsafeMutableBytes { buf -> CGImage? in
            guard let base = buf.baseAddress else { return nil }
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            return CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: w * 4, space: cs, bitmapInfo: bi.rawValue)?.makeImage()
        }
    }
}

// MARK:  Data helpers

private extension Data {
    func le16(at i: Int) -> UInt16 {
        guard i + 2 <= count else { return 0 }
        return UInt16(self[i]) | (UInt16(self[i+1]) << 8)
    }
    func le32(at i: Int) -> UInt32 {
        guard i + 4 <= count else { return 0 }
        return UInt32(self[i]) | (UInt32(self[i+1]) << 8)
            | (UInt32(self[i+2]) << 16) | (UInt32(self[i+3]) << 24)
    }
}
