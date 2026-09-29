// Renders the Holographic theme's marbled foil.
//
//   xcrun swiftc -O scripts/assets/holographic_marble.swift -o /tmp/holographic_marble
//   /tmp/holographic_marble 2400 1200 21 HolographicMarble.png
//   sips -s format jpeg -s formatOptions 92 HolographicMarble.png \
//     --out Sources/RingStats/Resources/Assets.xcassets/HolographicMarble.imageset/HolographicMarble.jpg
//
// The output is deterministic for a given size and seed.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Domain-warped value noise (after Inigo Quilez), mapped through a repeating
// pastel ramp sampled from the article's hero image.
func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374761393 &+ y &* 668265263 &+ seed &* 2147483647))
    h = (h ^ (h >> 13)) &* 1274126177
    h = h ^ (h >> 16)
    return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
}
func noise(_ x: Double, _ y: Double, _ seed: Int) -> Double {
    let xi = Int(floor(x)), yi = Int(floor(y))
    let xf = x - floor(x), yf = y - floor(y)
    let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
    let a = hash(xi, yi, seed), b = hash(xi + 1, yi, seed), c = hash(xi, yi + 1, seed), d = hash(xi + 1, yi + 1, seed)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
}
func fbm(_ x: Double, _ y: Double, _ seed: Int) -> Double {
    var sum = 0.0, amp = 0.5, fx = x, fy = y
    for o in 0..<3 { sum += amp * noise(fx, fy, seed + o * 17); fx *= 2.02; fy *= 2.02; amp *= 0.5 }
    return sum
}
let palette: [(Double, Double, Double)] = [
    (0xF4, 0xB9, 0xE0), (0xF7, 0xF1, 0xA9), (0xC2, 0xEA, 0xF3), (0xDA, 0xCB, 0xF0), (0xD3, 0xF0, 0xD2), (0xF4, 0xB9, 0xE0),
].map { ($0.0 / 255, $0.1 / 255, $0.2 / 255) }
func ramp(_ t: Double) -> (Double, Double, Double) {
    let f = (t - floor(t)) * Double(palette.count - 1)
    let i = min(Int(f), palette.count - 2), k = f - Double(i)
    let s = k * k * (3 - 2 * k)
    let a = palette[i], b = palette[i + 1]
    return (a.0 + (b.0 - a.0) * s, a.1 + (b.1 - a.1) * s, a.2 + (b.2 - a.2) * s)
}
let args = CommandLine.arguments
let width = Int(args[1])!, height = Int(args[2])!, seed = Int(args[3])!, out = args[4]
// The approved prototype spans 1680 x 520 px at 1.15 / 520 noise units per px.
let unitsWide = 1680.0 * 1.15 / 520.0
let scale = unitsWide / Double(width)
let yOffset = (Double(height) * scale - 1.15) / 2
var pixels = [UInt8](repeating: 255, count: width * height * 4)
for py in 0..<height {
    for px in 0..<width {
        let x = Double(px) * scale, y = Double(py) * scale - yOffset
        let qx = fbm(x, y, seed), qy = fbm(x + 5.2, y + 1.3, seed)
        let rx = fbm(x + 4 * qx + 1.7, y + 4 * qy + 9.2, seed), ry = fbm(x + 4 * qx + 8.3, y + 4 * qy + 2.8, seed)
        let v = fbm(x + 4 * rx, y + 4 * ry, seed)
        let c = ramp(v * 1.9 + rx * 0.5)
        let o = (py * width + px) * 4
        pixels[o] = UInt8(max(0, min(255, c.0 * 255))); pixels[o + 1] = UInt8(max(0, min(255, c.1 * 255))); pixels[o + 2] = UInt8(max(0, min(255, c.2 * 255)))
    }
}
let provider = CGDataProvider(data: Data(pixels) as CFData)!
let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
