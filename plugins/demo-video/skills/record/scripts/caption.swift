// Render a caption (or title) as a transparent PNG with CoreText. Used because Homebrew's ffmpeg
// ships without libfreetype/libass, so there is no `drawtext` filter to rely on.
// usage: caption <out.png> <width> <fontsize> <font-name-or-empty> <text...>
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 6, let width = Int(args[2]), let fontSize = Double(args[3]) else {
    FileHandle.standardError.write("usage: caption <out.png> <width> <fontsize> <font-name-or-empty> <text...>\n".data(using: .utf8)!)
    exit(2)
}
let out = args[1]
let fontName = args[4]
let text = args[5...].joined(separator: " ")
let pad = fontSize * 0.6

// Empty font name -> the system's bold UI font, which falls back per glyph across scripts (Latin, CJK, ...).
let font: CTFont = fontName.isEmpty
    ? CTFontCreateUIFontForLanguage(.emphasizedSystem, CGFloat(fontSize), nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(fontSize), nil)
    : CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)

var alignment = CTTextAlignment.center
let settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: &alignment)]
let paragraph = CTParagraphStyleCreate(settings, settings.count)
let attrs: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
]
let attributed = NSAttributedString(string: text, attributes: attrs)
let framesetter = CTFramesetterCreateWithAttributedString(attributed)
let maxWidth = CGFloat(width) - pad * 2
let fit = CTFramesetterSuggestFrameSizeWithConstraints(
    framesetter, CFRange(location: 0, length: 0), nil,
    CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
let height = Int(ceil(fit.height + pad * 2))

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

// White text on a translucent dark rounded band: readable over any frame content.
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.62))
let band = CGPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                  cornerWidth: fontSize * 0.35, cornerHeight: fontSize * 0.35, transform: nil)
ctx.addPath(band)
ctx.fillPath()
let path = CGPath(rect: CGRect(x: pad, y: pad, width: maxWidth, height: fit.height), transform: nil)
let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
CTFrameDraw(frame, ctx)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("\(out) \(width)x\(height)")
