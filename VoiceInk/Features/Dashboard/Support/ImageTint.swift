import AppKit
import CoreImage

enum ImageTint {
    /// Fixed cloth colours for hardcover boards when a book has no `coverTint`.
    static let clothPalette: [RGB] = [
        RGB(red: 0.48, green: 0.13, blue: 0.16),  // oxblood
        RGB(red: 0.14, green: 0.23, blue: 0.40),  // navy
        RGB(red: 0.15, green: 0.33, blue: 0.22),  // forest
        RGB(red: 0.72, green: 0.52, blue: 0.16),  // ochre
        RGB(red: 0.36, green: 0.20, blue: 0.40),  // plum
        RGB(red: 0.17, green: 0.40, blue: 0.42),  // teal
        RGB(red: 0.45, green: 0.28, blue: 0.16),  // saddle brown
        RGB(red: 0.32, green: 0.34, blue: 0.38),  // slate
    ]

    private static let ciContext = CIContext()

    /// Average colour of the whole image (sRGB, 0...1), or nil if it can't be rendered.
    static func averageColor(of image: NSImage) -> RGB? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]
        ), let output = filter.outputImage,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return RGB(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }

    /// Hardcover boards: the banner's average colour darkened by 20 %.
    static func boardsTint(from color: RGB) -> RGB {
        RGB(red: color.red * 0.8, green: color.green * 0.8, blue: color.blue * 0.8)
    }

    static func paletteTint(forBookID id: String) -> RGB {
        clothPalette[Int(fnv1a64(id) % UInt64(clothPalette.count))]
    }

    /// Process-independent hash (`hashValue` is randomised per launch).
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}
