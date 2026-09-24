// Writes the plain background video that scripts/demo-server.py plays for
// every item in demo mode:
//
//     swift scripts/make-demo-video.swift
//
// Four hours long, so any programme can be joined mid-way, but only a few
// frames of a soft dusk gradient, so the file is tiny. Output goes to
// .build/demo/background.mp4 (not committed).

import AVFoundation
import CoreGraphics

let output = URL(fileURLWithPath: ".build/demo/background.mp4")
let width = 1280, height = 720
let length = 4 * 3600   // seconds

try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: output)

/// Dusk: deep blue at the top, warm rose low down, darker at the edges.
func frame() -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB,
                        [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                        &buffer)
    let pixels = buffer!
    CVPixelBufferLockBaseAddress(pixels, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    let space = CGColorSpace(name: CGColorSpace.sRGB)
    let sky = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.93, green: 0.55, blue: 0.45, alpha: 1),   // horizon glow
        CGColor(srgbRed: 0.55, green: 0.35, blue: 0.55, alpha: 1),
        CGColor(srgbRed: 0.12, green: 0.14, blue: 0.32, alpha: 1),   // night above
    ] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(height)), options: [])
    let vignette = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.45)] as CFArray,
                              locations: [0.55, 1])!
    let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.4)
    ctx.drawRadialGradient(vignette, startCenter: center, startRadius: 0, endCenter: center,
                           endRadius: CGFloat(width) * 0.75, options: [.drawsAfterEndLocation])
    CVPixelBufferUnlockBaseAddress(pixels, [])
    return pixels
}

let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
let image = frame()
// A frame every ten minutes, so seeking anywhere lands near one.
for second in stride(from: 0, through: length, by: 600) {
    while !input.isReadyForMoreMediaData { usleep(1000) }
    adaptor.append(image, withPresentationTime: CMTime(seconds: Double(second), preferredTimescale: 600))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed { fatalError("Couldn't write the video: \(String(describing: writer.error))") }
print("Wrote \(output.path)")
