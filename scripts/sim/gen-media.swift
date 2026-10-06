// Generates a small, deterministic photo library for the Simulator proof job.
// Usage: gen-media <output-dir> [YYYY-MM-DD]
// Output: JPEG "photos" with EXIF dates across the current month, the two previous months and
// "On this day" in past years (incl. near-duplicate bursts), plus PNG "screenshots" tagged the way
// iOS tags its own screenshots (EXIF UserComment = "Screenshot", device-screen pixel size).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: gen-media <out-dir> [YYYY-MM-DD]\n", stderr); exit(2) }
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone.current
let today: Date = {
    if args.count >= 3 {
        let parts = args[2].split(separator: "-").compactMap { Int($0) }
        if parts.count == 3, let d = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) { return d }
    }
    return cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
}()

let exifFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return f
}()

struct LCG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
    }
}

func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [CGFloat(r), CGFloat(g), CGFloat(b), 1])!
}

/// A photo-like scene: diagonal sky gradient, sun, hills, a few "trees". `variant` nudges it like a burst shot.
func drawScene(seed: Int, variant: Int, width: Int, height: Int) -> CGImage {
    var rng = LCG(state: UInt64(seed) &* 7919 &+ 17)
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    let bright = 1.0 + Double(variant) * 0.03
    let hueA = rng.next(), hueB = rng.next()
    func sky(_ t: Double) -> CGColor {
        color(min(1, (0.35 + 0.6 * t) * bright), min(1, (0.45 + 0.4 * hueA) * bright), min(1, (0.75 + 0.25 * hueB) * bright))
    }
    let angle = rng.next()
    let start = CGPoint(x: angle < 0.5 ? 0 : w, y: h)
    let end = CGPoint(x: angle < 0.5 ? w : 0, y: h * 0.25)
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [sky(0), sky(1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Sun
    let sunX = w * (0.15 + 0.7 * rng.next()) + CGFloat(variant) * 6
    let sunY = h * (0.6 + 0.3 * rng.next())
    let sunR = w * (0.05 + 0.06 * rng.next())
    ctx.setFillColor(color(min(1, 1.0 * bright), min(1, 0.85 * bright), 0.55))
    ctx.fillEllipse(in: CGRect(x: sunX - sunR, y: sunY - sunR, width: sunR * 2, height: sunR * 2))

    // Hills
    for layer in 0..<3 {
        let shade = 0.55 - Double(layer) * 0.15
        ctx.setFillColor(color(0.05 + shade * 0.3, shade * bright, 0.35 * shade + 0.1))
        let hillY = h * (0.12 + 0.12 * Double(layer)) + CGFloat(variant) * 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: hillY))
        var x: CGFloat = 0
        while x < w {
            let bump = h * 0.08 * rng.next()
            path.addQuadCurve(to: CGPoint(x: x + w * 0.25, y: hillY + bump), control: CGPoint(x: x + w * 0.12, y: hillY + bump * 2))
            x += w * 0.25
        }
        path.addLine(to: CGPoint(x: w, y: 0))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
    // Trees / posts
    let trees = 2 + Int(rng.next() * 4)
    for _ in 0..<trees {
        let tx = w * rng.next()
        let th = h * (0.08 + 0.1 * rng.next())
        ctx.setFillColor(color(0.08, 0.16, 0.12))
        ctx.fill(CGRect(x: tx, y: h * 0.1, width: w * 0.012, height: th))
        ctx.fillEllipse(in: CGRect(x: tx - w * 0.03, y: h * 0.1 + th * 0.7, width: w * 0.072, height: th * 0.6))
    }
    // A little grain so JPEG sizes look like photos
    var noise = LCG(state: UInt64(seed * 31 + variant))
    for _ in 0..<600 {
        let nx = w * noise.next(), ny = h * noise.next()
        ctx.setFillColor(color(1, 1, 1))
        ctx.setAlpha(0.08)
        ctx.fill(CGRect(x: nx, y: ny, width: 3, height: 3))
    }
    ctx.setAlpha(1)
    return ctx.makeImage()!
}

/// A screenshot-like image at the device's pixel size: light background, a nav bar and card shapes.
func drawScreenshot(seed: Int, width: Int, height: Int) -> CGImage {
    var rng = LCG(state: UInt64(seed) &* 104729 &+ 3)
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    ctx.setFillColor(color(0.96, 0.96, 0.97)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(color(0.2 + 0.6 * rng.next(), 0.3 + 0.5 * rng.next(), 0.5 + 0.5 * rng.next()))
    ctx.fill(CGRect(x: 0, y: h - 330, width: w, height: 330))
    var y = h - 420
    for _ in 0..<(6 + Int(rng.next() * 5)) {
        let ch = 160 + 140 * rng.next()
        ctx.setFillColor(color(1, 1, 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 48, y: y - ch, width: w - 96, height: ch), cornerWidth: 36, cornerHeight: 36, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(color(0.75, 0.76, 0.8))
        ctx.fill(CGRect(x: 96, y: y - 70, width: (w - 192) * (0.3 + 0.5 * rng.next()), height: 26))
        ctx.fill(CGRect(x: 96, y: y - 120, width: (w - 192) * (0.2 + 0.3 * rng.next()), height: 20))
        y -= ch + 40
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL, type: UTType, date: Date, extraExif: [CFString: Any] = [:]) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw NSError(domain: "gen-media", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot create \(url.path)"])
    }
    let stamp = exifFormatter.string(from: date)
    var exif: [CFString: Any] = [
        kCGImagePropertyExifDateTimeOriginal: stamp,
        kCGImagePropertyExifDateTimeDigitized: stamp,
    ]
    for (k, v) in extraExif { exif[k] = v }
    var props: [CFString: Any] = [
        kCGImagePropertyExifDictionary: exif,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp, kCGImagePropertyTIFFSoftware: "Keepwell sim-proof"],
    ]
    if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.9 }
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "gen-media", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
    // Make the file dates agree with the EXIF date too.
    try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
}

var manifest: [String] = []
var seed = 1
func at(_ base: Date, day: Int, hour: Int, minute: Int) -> Date {
    var c = cal.dateComponents([.year, .month], from: base)
    c.day = day; c.hour = hour; c.minute = minute; c.second = 0
    return cal.date(from: c)!
}
func photo(name: String, date: Date, seed s: Int, variant: Int = 0, portrait: Bool = false) throws {
    let (w, h) = portrait ? (1200, 1600) : (1600, 1200)
    let url = outDir.appendingPathComponent("\(name).jpg")
    try write(drawScene(seed: s, variant: variant, width: w, height: h), to: url, type: .jpeg, date: date)
    manifest.append("\(url.lastPathComponent)\t\(exifFormatter.string(from: date))\tscene=\(s) variant=\(variant)")
}

let todayDay = cal.component(.day, from: today)
let thisMonth = today
let lastMonth = cal.date(byAdding: .month, value: -1, to: today)!
let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: today)!

// Current month: 4 bursts of 3 near-duplicates (within a few minutes) + 3 single shots = 15 photos.
var n = 0
for burst in 0..<4 {
    let day = max(1, todayDay - burst)
    for v in 0..<3 {
        n += 1
        try photo(name: String(format: "cur-%02d-burst%d-%d", n, burst, v), date: at(thisMonth, day: day, hour: 9 + burst, minute: v * 2),
                  seed: 100 + burst, variant: v, portrait: burst % 2 == 1)
    }
}
for single in 0..<3 {
    n += 1
    try photo(name: String(format: "cur-%02d-single%d", n, single), date: at(thisMonth, day: max(1, todayDay - single), hour: 15 + single, minute: 30),
              seed: 200 + single, portrait: single == 1)
}
// Last month: 6 distinct photos. Two months ago: 5 distinct photos.
for i in 0..<6 { try photo(name: String(format: "last-%02d", i), date: at(lastMonth, day: 3 + i * 4, hour: 10 + i, minute: 15), seed: 300 + i, portrait: i % 3 == 0) }
for i in 0..<5 { try photo(name: String(format: "prev-%02d", i), date: at(twoMonthsAgo, day: 2 + i * 5, hour: 8 + i, minute: 45), seed: 400 + i, portrait: i % 2 == 0) }
// On this day: same month/day in 2024, 2023 and 2022.
for (i, yearsBack) in [2, 3, 4].enumerated() {
    let d = cal.date(byAdding: .year, value: -yearsBack, to: today)!
    try photo(name: String(format: "otd-%02d", i), date: cal.date(bySettingHour: 11 + i, minute: 20, second: 0, of: d)!, seed: 500 + i, portrait: i == 1)
}
// Screenshots: PNG at the iPhone 17 Pro Max pixel size, tagged like iOS screenshots.
for i in 0..<4 {
    let date = at(thisMonth, day: max(1, todayDay - i), hour: 18, minute: 5 + i)
    let url = outDir.appendingPathComponent(String(format: "screenshot-%02d.png", i))
    try write(drawScreenshot(seed: 600 + i, width: 1320, height: 2868), to: url, type: .png, date: date,
              extraExif: [kCGImagePropertyExifUserComment: "Screenshot"])
    manifest.append("\(url.lastPathComponent)\t\(exifFormatter.string(from: date))\tscreenshot")
}
try manifest.joined(separator: "\n").appending("\n").write(to: outDir.appendingPathComponent("manifest.tsv"), atomically: true, encoding: .utf8)
print("generated \(manifest.count) files in \(outDir.path)")
