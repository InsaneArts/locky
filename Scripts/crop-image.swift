import CoreGraphics
import Foundation
import ImageIO

// crop-image IN OUT TOP MARGIN WIDTH: drops TOP pixels (a window's title bar) and MARGIN pixels at the sides and
// the bottom (its rounded corners), scales to WIDTH pixels wide, and writes OUT as a JPEG. sips cannot crop on
// macOS 26.
let arguments = CommandLine.arguments
guard arguments.count == 6, let top = Int(arguments[3]), let margin = Int(arguments[4]), let width = Int(arguments[5]),
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let cropped = image.cropping(to: CGRect(x: margin, y: top, width: image.width - 2 * margin, height: image.height - top - margin)),
      let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    FileHandle.standardError.write(Data("usage: crop-image IN OUT TOP MARGIN WIDTH\n".utf8))
    exit(2)
}
let height = cropped.height * width / cropped.width
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
context.interpolationQuality = .high
context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let scaled = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, "public.jpeg" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
