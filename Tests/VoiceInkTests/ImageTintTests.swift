import AppKit
import Foundation
import Testing
@testable import VoiceInk

struct ImageTintTests {
    private func solidImage(_ color: NSColor, size: NSSize = NSSize(width: 8, height: 8)) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    @Test func averageColorOfSolidRedIsRed() throws {
        let color = try #require(ImageTint.averageColor(of: solidImage(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))))
        #expect(abs(color.red - 1) <= 0.02)
        #expect(abs(color.green) <= 0.02)
        #expect(abs(color.blue) <= 0.02)
    }

    @Test func boardsTintDarkensEachChannelBy20Percent() {
        let tint = ImageTint.boardsTint(from: RGB(red: 1, green: 0.5, blue: 0.25))
        #expect(abs(tint.red - 0.8) < 0.0001)
        #expect(abs(tint.green - 0.4) < 0.0001)
        #expect(abs(tint.blue - 0.2) < 0.0001)
    }

    @Test func paletteTintIsDeterministicAndFromPalette() {
        #expect(ImageTint.clothPalette.count == 8)
        #expect(Set(ImageTint.clothPalette).count == 8)
        let ids = ["builtin.iliad", "builtin.odyssey", "custom.A", "custom.B", "", "custom.\(UUID().uuidString)"]
        for id in ids {
            let tint = ImageTint.paletteTint(forBookID: id)
            #expect(tint == ImageTint.paletteTint(forBookID: id))
            #expect(ImageTint.clothPalette.contains(tint))
        }
    }

    @Test func paletteTintUsesStableHash() {
        // FNV-1a 64 is process-independent; pin one value so a switch to `hashValue` fails.
        #expect(ImageTint.paletteTint(forBookID: "builtin.iliad") == ImageTint.clothPalette[Int(ImageTint.fnv1a64("builtin.iliad") % 8)])
        #expect(ImageTint.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(ImageTint.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
    }
}
