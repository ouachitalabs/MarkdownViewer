#!/usr/bin/env swift

import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconsetPath = "AppIcon.iconset"

// Create iconset directory
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func createIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let scale = CGFloat(size) / 512.0

    // Background with rounded corners
    let cornerRadius = 100.0 * scale
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 2 * scale, dy: 2 * scale), xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient background
    let gradient = NSGradient(colors: [
        NSColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1.0),
        NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
    ])!
    gradient.draw(in: bgPath, angle: -90)

    // Draw markdown "M" symbol
    let fontSize = 280.0 * scale
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let text = "M"
    let textAttr: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let textSize = text.size(withAttributes: textAttr)
    let textRect = CGRect(
        x: (CGFloat(size) - textSize.width) / 2,
        y: (CGFloat(size) - textSize.height) / 2 + 10 * scale,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: textAttr)

    // Draw down arrow (markdown symbol)
    let arrowFont = NSFont.systemFont(ofSize: 120 * scale, weight: .bold)
    let arrow = "↓"
    let arrowAttr: [NSAttributedString.Key: Any] = [
        .font: arrowFont,
        .foregroundColor: NSColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
    ]
    let arrowSize = arrow.size(withAttributes: arrowAttr)
    let arrowRect = CGRect(
        x: (CGFloat(size) - arrowSize.width) / 2 + 90 * scale,
        y: 60 * scale,
        width: arrowSize.width,
        height: arrowSize.height
    )
    arrow.draw(in: arrowRect, withAttributes: arrowAttr)

    image.unlockFocus()
    return image
}

// Generate icons at different sizes
for size in sizes {
    let image = createIcon(size: size)

    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {

        // 1x
        let filename1x = "\(iconsetPath)/icon_\(size)x\(size).png"
        try! pngData.write(to: URL(fileURLWithPath: filename1x))

        // 2x (for sizes up to 512)
        if size <= 512 {
            let image2x = createIcon(size: size * 2)
            if let tiff2x = image2x.tiffRepresentation,
               let bitmap2x = NSBitmapImageRep(data: tiff2x),
               let png2x = bitmap2x.representation(using: .png, properties: [:]) {
                let filename2x = "\(iconsetPath)/icon_\(size)x\(size)@2x.png"
                try! png2x.write(to: URL(fileURLWithPath: filename2x))
            }
        }
    }
}

print("Iconset created at \(iconsetPath)")
print("Run: iconutil -c icns \(iconsetPath)")
