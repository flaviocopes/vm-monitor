#!/usr/bin/env swift
// Renders the VM Monitor app icon: a display with a pulse line running across its screen and an amber
// live dot where the line ends, baked into a 1024px squircle on Apple's macOS icon grid.
// Scripts/build-app.sh turns it into AppIcon.icns.
// Usage: swift Scripts/render-icon.swift Assets/AppIcon.png

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
// Apple's macOS icon grid: an 824pt continuous-corner body centered on a 1024pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185.4

// The display: a thick frame around a slightly darker screen, on a short stand.
let screen = CGRect(x: 206, y: 236, width: 612, height: 420)
let screenRadius: CGFloat = 74
let frameWidth: CGFloat = 54
let screenShade: CGFloat = 0.2
let neck = CGRect(x: 467, y: 650, width: 90, height: 84)
let base = CGRect(x: 352, y: 728, width: 320, height: 50)

// The pulse, in canvas points, ending in the live dot.
let pulse: [CGPoint] = [
  CGPoint(x: 290, y: 452), CGPoint(x: 392, y: 452), CGPoint(x: 436, y: 372),
  CGPoint(x: 496, y: 548), CGPoint(x: 552, y: 330), CGPoint(x: 604, y: 500),
  CGPoint(x: 640, y: 452), CGPoint(x: 692, y: 452)
]
let pulseWidth: CGFloat = 40
let dotRadius: CGFloat = 38
let glowRadius: CGFloat = 84

let backgroundTop: UInt32 = 0x7B6CFF
let backgroundBottom: UInt32 = 0x2F1F9E
let shapeColor: UInt32 = 0xFFF5EC
let accentColor: UInt32 = 0xFFC53D

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
  CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
  RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

// The artwork, in 1024pt canvas coordinates with a top-left origin.
func drawArtwork(_ context: CGContext) {
  let dot = pulse[pulse.count - 1]

  // The stand goes under the frame, so the neck tucks into it.
  context.setFillColor(rgb(shapeColor))
  context.addPath(squircle(neck, radius: 10))
  context.addPath(squircle(base, radius: base.height / 2))
  context.fillPath()

  let inner = screen.insetBy(dx: frameWidth, dy: frameWidth)
  context.addPath(squircle(screen, radius: screenRadius))
  context.addPath(squircle(inner, radius: screenRadius - frameWidth))
  context.fillPath(using: .evenOdd)

  context.setFillColor(rgb(0x000000, screenShade))
  context.addPath(squircle(inner, radius: screenRadius - frameWidth))
  context.fillPath()

  context.saveGState()
  context.addPath(squircle(inner, radius: screenRadius - frameWidth))
  context.clip()
  context.drawRadialGradient(
    gradient([rgb(accentColor, 0.55), rgb(accentColor, 0)]),
    startCenter: dot, startRadius: dotRadius * 0.6,
    endCenter: dot, endRadius: glowRadius,
    options: []
  )
  context.restoreGState()

  context.setStrokeColor(rgb(shapeColor))
  context.setLineWidth(pulseWidth)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.addLines(between: pulse)
  context.strokePath()

  context.setFillColor(rgb(accentColor))
  context.fillEllipse(in: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
}

func drawIcon(_ context: CGContext, scale: CGFloat) {
  let bodyPath = squircle(body, radius: bodyRadius)

  // Drop shadow under the body, as in Apple's icon template. Shadows ignore the
  // transform: the offset is in unflipped pixels (negative is down), so scale it by hand.
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 22 * scale, color: rgb(0x000000, 0.32))
  context.addPath(bodyPath)
  context.setFillColor(rgb(backgroundBottom))
  context.fillPath()
  context.restoreGState()

  context.saveGState()
  context.addPath(bodyPath)
  context.clip()
  context.drawLinearGradient(
    gradient([rgb(backgroundTop), rgb(backgroundBottom)]),
    start: CGPoint(x: 0, y: body.minY),
    end: CGPoint(x: 0, y: body.maxY),
    options: []
  )
  drawArtwork(context)
  context.restoreGState()

  // Hairline highlight along the top edge of the body.
  context.saveGState()
  context.addPath(bodyPath)
  context.setLineWidth(3)
  context.replacePathWithStrokedPath()
  context.clip()
  context.drawLinearGradient(
    gradient([rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0)]),
    start: CGPoint(x: 0, y: body.minY),
    end: CGPoint(x: 0, y: body.midY),
    options: []
  )
  context.restoreGState()
}

func render(pixels: Int) -> CGImage {
  let context = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let scale = CGFloat(pixels) / canvas
  context.translateBy(x: 0, y: CGFloat(pixels))
  context.scaleBy(x: scale, y: -scale)
  drawIcon(context, scale: scale)
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasSuffix(".png") else {
  print("Usage: swift Scripts/render-icon.swift Assets/AppIcon.png")
  exit(1)
}
let output = URL(filePath: CommandLine.arguments[1])
try! FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
write(render(pixels: 1024), to: output)
print("Wrote \(output.path)")
