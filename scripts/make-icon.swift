// Dessine l'icône de SweepIt (1024×1024) : un balai qui balaie des petites pommes.
// Usage : swift scripts/make-icon.swift sortie.png
import AppKit

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext

// MARK: - Fond (grille d'icône macOS : 824 px, coins ~185 px)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x3B3BD6))
ctx.fillPath()
ctx.restoreGState()

// Tout le reste est découpé dans la tuile.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x6A5CFF), rgb(0x3F7BEA), rgb(0x1EC3C9)]),
                       start: CGPoint(x: 200, y: 924), end: CGPoint(x: 820, y: 100), options: [])
ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)]),
                       startCenter: CGPoint(x: 300, y: 780), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 780), endRadius: 520, options: [])
// Sol.
ctx.setFillColor(rgb(0x0B1E5B, 0.22))
ctx.fillEllipse(in: CGRect(x: 110, y: 90, width: 760, height: 190))

// MARK: - Traînées de balayage et poussière

ctx.setLineCap(.round)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.38))
for (y, w, len) in [(250.0, 14.0, 230.0), (320.0, 10.0, 180.0), (190.0, 8.0, 150.0)] {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 400, y: y))
    p.addQuadCurve(to: CGPoint(x: 400 - len, y: y + 40), control: CGPoint(x: 400 - len * 0.5, y: y - 25))
    ctx.addPath(p)
    ctx.setLineWidth(w)
    ctx.strokePath()
}
ctx.setFillColor(rgb(0xFFFFFF, 0.35))
for (x, y, r) in [(190.0, 210.0, 9.0), (240.0, 400.0, 6.0), (150.0, 290.0, 7.0), (330.0, 300.0, 5.0),
                  (270.0, 520.0, 5.0), (175.0, 470.0, 8.0), (360.0, 250.0, 7.0)] {
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

// MARK: - Pommes (fruits génériques, pas le logo Apple)

func applePath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0.30))
    p.addCurve(to: CGPoint(x: 0.50, y: 0.08), control1: CGPoint(x: 0.12, y: 0.46), control2: CGPoint(x: 0.50, y: 0.48))
    p.addCurve(to: CGPoint(x: 0.14, y: -0.50), control1: CGPoint(x: 0.50, y: -0.24), control2: CGPoint(x: 0.32, y: -0.52))
    p.addCurve(to: CGPoint(x: 0, y: -0.45), control1: CGPoint(x: 0.08, y: -0.49), control2: CGPoint(x: 0.04, y: -0.45))
    p.addCurve(to: CGPoint(x: -0.14, y: -0.50), control1: CGPoint(x: -0.04, y: -0.45), control2: CGPoint(x: -0.08, y: -0.49))
    p.addCurve(to: CGPoint(x: -0.50, y: 0.08), control1: CGPoint(x: -0.32, y: -0.52), control2: CGPoint(x: -0.50, y: -0.24))
    p.addCurve(to: CGPoint(x: 0, y: 0.30), control1: CGPoint(x: -0.50, y: 0.48), control2: CGPoint(x: -0.12, y: 0.46))
    p.closeSubpath()
    return p
}

func drawApple(at c: CGPoint, size s: CGFloat, angle: CGFloat, light: UInt32, dark: UInt32) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.scaleBy(x: s, y: s)

    // Tige et feuille.
    ctx.setStrokeColor(rgb(0x6B3E1E))
    ctx.setLineWidth(0.07)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 0, y: 0.26))
    ctx.addQuadCurve(to: CGPoint(x: 0.06, y: 0.58), control: CGPoint(x: 0.01, y: 0.45))
    ctx.strokePath()
    ctx.saveGState()
    ctx.translateBy(x: 0.22, y: 0.50)
    ctx.rotate(by: 0.5)
    ctx.setFillColor(rgb(0x3DBE5A))
    ctx.fillEllipse(in: CGRect(x: -0.16, y: -0.07, width: 0.32, height: 0.14))
    ctx.restoreGState()

    // Corps avec ombre portée et dégradé.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0.02 * s, height: -0.05 * s), blur: 0.08 * s, color: rgb(0x000000, 0.3))
    ctx.addPath(applePath())
    ctx.setFillColor(rgb(dark))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(applePath())
    ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(light), rgb(dark)]),
                           startCenter: CGPoint(x: -0.18, y: 0.12), startRadius: 0,
                           endCenter: CGPoint(x: 0, y: -0.05), endRadius: 0.62, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Reflet.
    ctx.saveGState()
    ctx.translateBy(x: -0.24, y: 0.10)
    ctx.rotate(by: 0.45)
    ctx.setFillColor(rgb(0xFFFFFF, 0.45))
    ctx.fillEllipse(in: CGRect(x: -0.06, y: -0.12, width: 0.12, height: 0.24))
    ctx.restoreGState()

    ctx.restoreGState()
}

drawApple(at: CGPoint(x: 255, y: 215), size: 130, angle: 0.25, light: 0xFF6B6B, dark: 0xC81E3A)
drawApple(at: CGPoint(x: 170, y: 345), size: 82, angle: 0.6, light: 0x9BE15D, dark: 0x3E9B2F)
drawApple(at: CGPoint(x: 300, y: 400), size: 66, angle: -0.35, light: 0xFFE27A, dark: 0xF2A900)
drawApple(at: CGPoint(x: 205, y: 500), size: 48, angle: 0.9, light: 0xFF6B6B, dark: 0xC81E3A)
drawApple(at: CGPoint(x: 345, y: 150), size: 64, angle: -0.2, light: 0x9BE15D, dark: 0x3E9B2F)

// MARK: - Balai

ctx.saveGState()
ctx.translateBy(x: 565, y: 375)
ctx.rotate(by: -0.70) // le manche part vers le haut à droite

// Manche en bois.
let handle = CGPath(roundedRect: CGRect(x: -24, y: 110, width: 48, height: 350),
                    cornerWidth: 24, cornerHeight: 24, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 6, height: -10), blur: 18, color: rgb(0x000000, 0.3))
ctx.addPath(handle)
ctx.setFillColor(rgb(0x9A6233))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(handle)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xE0A869), rgb(0xB87838), rgb(0x8A5226)]),
                       start: CGPoint(x: -24, y: 0), end: CGPoint(x: 24, y: 0), options: [])
ctx.restoreGState()
// Embout.
ctx.setFillColor(rgb(0xE84855))
ctx.addPath(CGPath(roundedRect: CGRect(x: -26, y: 404, width: 52, height: 58), cornerWidth: 24, cornerHeight: 24, transform: nil))
ctx.fillPath()

// Poils.
let bristles = CGMutablePath()
bristles.move(to: CGPoint(x: -70, y: 100))
bristles.addLine(to: CGPoint(x: 70, y: 100))
bristles.addLine(to: CGPoint(x: 165, y: -150))
bristles.addQuadCurve(to: CGPoint(x: -165, y: -150), control: CGPoint(x: 0, y: -185))
bristles.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 6, height: -12), blur: 20, color: rgb(0x000000, 0.3))
ctx.addPath(bristles)
ctx.setFillColor(rgb(0xF2A900))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bristles)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xFFE08A), rgb(0xFFC23D), rgb(0xE89400)]),
                       start: CGPoint(x: -165, y: 0), end: CGPoint(x: 165, y: 0), options: [])
ctx.setStrokeColor(rgb(0xB06A00, 0.45))
ctx.setLineWidth(5)
for i in 0...12 {
    let t = CGFloat(i) / 12
    ctx.move(to: CGPoint(x: -60 + 120 * t, y: 95))
    ctx.addLine(to: CGPoint(x: -165 + 330 * t, y: -175))
}
ctx.strokePath()
ctx.restoreGState()

// Lien et virole.
ctx.setFillColor(rgb(0xD9480F))
ctx.fill(CGRect(x: -98, y: 18, width: 196, height: 18))
ctx.setFillColor(rgb(0xE84855))
ctx.addPath(CGPath(roundedRect: CGRect(x: -78, y: 90, width: 156, height: 46), cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.fillPath()
ctx.setFillColor(rgb(0xFFFFFF, 0.3))
ctx.addPath(CGPath(roundedRect: CGRect(x: -70, y: 118, width: 140, height: 10), cornerWidth: 5, cornerHeight: 5, transform: nil))
ctx.fillPath()
ctx.restoreGState()

// MARK: - Étincelles

func sparkle(_ c: CGPoint, _ r: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
    ctx.addPath(p)
    ctx.setFillColor(rgb(0xFFFFFF, 0.95))
    ctx.fillPath()
}
sparkle(CGPoint(x: 250, y: 720), 58)
sparkle(CGPoint(x: 385, y: 815), 30)
sparkle(CGPoint(x: 165, y: 610), 22)

ctx.restoreGState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("✓ \(out)")
