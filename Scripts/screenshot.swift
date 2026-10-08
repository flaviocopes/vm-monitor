// Captures the real VM Peek window in light and dark: the Live view into screenshot-<appearance>.png,
// and a chat with one of its screenshots open into chat-<appearance>.png.
// Scripts/screenshot.sh compiles it with the app's sources in place of the @main file and runs it in the
// test VM, with the made-up history from Scripts/sample-activity.py.
// Arguments: the output folder, then the image to show as the VM's screen.

import AppKit
import MonitorCore
import SwiftUI

let output = URL(filePath: CommandLine.arguments[1])
let screen = URL(filePath: CommandLine.arguments[2])
let size = CGSize(width: 1320, height: 860)

@MainActor
enum Demo {
  // The VM side is made up: polling is off, and the screen is a picture.
  static let model: AppModel = {
    let model = AppModel(watchesVM: false)
    model.vmState = .running(address: "192.168.64.3")
    model.screen = NSImage(contentsOf: screen)
    model.screenDate = .now
    model.runningApps = ["Note Repo"]
    return model
  }()

  static func content() -> some View {
    ContentView()
      .environment(model)
      .task { await model.watch() }
  }

  static func show(_ state: String) async {
    if state == "chat", let session = model.sessions.first(where: { $0.agent == .cursor }) {
      model.selection = .session(session.id)
      // Changing the selection clears the selected run, so pick it once the chat is showing.
      try? await Task.sleep(for: .seconds(0.5))
      model.selectedRunID = model.activity.runs.last { $0.sessionKey == session.id && $0.command == "shot" }?.id
    } else {
      model.selection = .live
    }
    try? await Task.sleep(for: .seconds(1.5))
  }
}

@main
enum Screenshot {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let host = NSHostingView(rootView: Demo.content().frame(width: size.width, height: size.height))
    host.sceneBridgingOptions = .all
    let window = ActiveWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "VM Peek"
    window.toolbarStyle = .unified
    window.contentView = host
    window.center()
    _ = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await capture(window) }
      }
    }
    app.run()
  }
}

/// Draws as the active window even when another app is frontmost.
final class ActiveWindow: NSWindow {
  override var isKeyWindow: Bool { true }
  override var isMainWindow: Bool { true }
  @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
  @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
  @objc(_hasKeyAppearance) func hasKeyAppearance() -> Bool { true }
  @objc(_hasMainAppearance) func hasMainAppearance() -> Bool { true }
}

@MainActor
func capture(_ window: NSWindow) async {
  // The log, the chats' prompts and the thumbnails load in the background.
  try? await Task.sleep(for: .seconds(3))
  for state in ["screenshot", "chat"] {
    await Demo.show(state)
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      NSApp.appearance = NSAppearance(named: appearance)
      try? await Task.sleep(for: .seconds(1.5))
      write(framed(snapshot(window)), to: output.appending(path: "\(state)-\(name).png"))
    }
  }
  NSApp.terminate(nil)
}

/// The whole window, title bar included, at the screen's scale.
@MainActor
func snapshot(_ window: NSWindow) -> CGImage {
  let view = window.contentView!.superview!
  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  view.cacheDisplay(in: view.bounds, to: rep)
  return rep.cgImage!
}

/// Rounds the corners like a window and adds a soft shadow on a transparent 48pt margin.
func framed(_ image: CGImage) -> CGImage {
  let scale: CGFloat = 2
  let margin = 48 * scale
  let radius = 10 * scale
  let size = CGSize(width: CGFloat(image.width) + 2 * margin, height: CGFloat(image.height) + 2 * margin)
  let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let rect = CGRect(x: margin, y: margin, width: CGFloat(image.width), height: CGFloat(image.height))
  let window = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 36 * scale, color: CGColor(gray: 0, alpha: 0.32))
  context.addPath(window)
  context.setFillColor(CGColor(gray: 0.5, alpha: 1))
  context.fillPath()
  context.restoreGState()

  context.addPath(window)
  context.clip()
  context.draw(image, in: rect)
  context.resetClip()
  context.addPath(window)
  context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
  context.setLineWidth(1)
  context.strokePath()
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let rep = NSBitmapImageRep(cgImage: image)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print(url.path)
}
