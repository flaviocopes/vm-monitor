import AppKit
import ImageIO
import MonitorCore
import SwiftUI

extension Agent {
  var symbol: String {
    switch self {
    case .cursor: "cursorarrow"
    case .claude: "asterisk"
    case .codex: "chevron.left.forwardslash.chevron.right"
    case .terminal: "terminal"
    case .other: "sparkles"
    }
  }

  var color: Color {
    switch self {
    case .cursor: .blue
    case .claude: .orange
    case .codex: .teal
    case .terminal: .gray
    case .other: .purple
    }
  }
}

extension RunState {
  var title: String {
    switch self {
    case .running: "Running"
    case .succeeded: "Done"
    case .failed(let status): "Failed with status \(status)"
    case .interrupted: "Stopped before it finished"
    }
  }

  var color: Color {
    switch self {
    case .running: .blue
    case .succeeded: .green
    case .failed: .red
    case .interrupted: .orange
    }
  }
}

extension VMState {
  var title: String {
    switch self {
    case .checking: "Checking…"
    case .running(let address): address.isEmpty ? "Starting up" : "Running at \(address)"
    case .stopped: "Stopped"
    case .missing: "Not set up"
    case .unreachable: "Can't reach it"
    }
  }

  var color: Color {
    switch self {
    case .running(let address): address.isEmpty ? .orange : .green
    case .checking, .stopped: .secondary
    case .missing, .unreachable: .red
    }
  }

  var isRunning: Bool {
    if case .running(let address) = self { return !address.isEmpty }
    return false
  }
}

struct AgentBadge: View {
  let agent: Agent
  var size: CGFloat = 22

  var body: some View {
    Image(systemName: agent.symbol)
      .font(.system(size: size * 0.48, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Circle().fill(agent.color.gradient))
  }
}

struct StatusIcon: View {
  let state: RunState
  var isNote = false

  var body: some View {
    Group {
      if isNote {
        Image(systemName: "text.bubble.fill").foregroundStyle(.blue)
      } else {
        switch state {
        case .running:
          ProgressView().controlSize(.mini)
        case .succeeded:
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
          Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .interrupted:
          Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        }
      }
    }
    .frame(width: 16, height: 16)
  }
}

struct Pill: View {
  let text: String
  var color: Color = .secondary

  var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .foregroundStyle(color)
      .background(Capsule().fill(color.opacity(0.14)))
  }
}

struct Card<Content: View>: View {
  var tint: Color? = nil
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(tint.map { AnyShapeStyle($0.opacity(0.1)) } ?? AnyShapeStyle(.quaternary.opacity(0.45)))
      )
  }
}

struct SectionTitle: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.headline)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Monospaced text with a title and a copy button, for commands and output.
struct CodeBlock: View {
  let title: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Spacer()
        CopyButton(text: text)
          .buttonStyle(.borderless)
          .controlSize(.small)
      }
      Text(text)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
  }
}

struct CopyButton: View {
  let text: String
  var label = "Copy"
  @State private var copied = false

  var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      copied = true
      Task {
        try? await Task.sleep(for: .seconds(1.5))
        copied = false
      }
    } label: {
      Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
    }
    .disabled(text.isEmpty)
  }
}

// MARK: - Images

struct SendableImage: @unchecked Sendable {
  let cgImage: CGImage
}

enum Images {
  static func downsample(_ data: Data, maxPixels: Int) -> SendableImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return thumbnail(source, maxPixels: maxPixels)
  }

  static func thumbnail(at url: URL, maxPixels: Int) -> SendableImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return thumbnail(source, maxPixels: maxPixels)
  }

  private static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> SendableImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(SendableImage.init)
  }
}

@MainActor
enum ThumbnailCache {
  /// Weeks of screenshots add up, so the cache drops the oldest past about 200 MB of pixels.
  static let images: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.totalCostLimit = 200 << 20
    return cache
  }()
}

/// A screenshot from `/tmp/testvm`, decoded off the main thread at the size it's shown.
struct Thumbnail: View {
  let url: URL
  var maxPixels = 360
  @State private var image: NSImage?
  @State private var missing = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.5))
      if let image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
      } else if missing {
        Image(systemName: "photo")
          .foregroundStyle(.tertiary)
          .help("The screenshot is gone. macOS empties /tmp when the Mac restarts.")
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .task(id: url) {
      let key = "\(url.path)@\(maxPixels)" as NSString
      if let cached = ThumbnailCache.images.object(forKey: key) {
        image = cached
        return
      }
      let size = maxPixels
      let loaded = await Task.detached { Images.thumbnail(at: url, maxPixels: size) }.value
      if let loaded {
        let nsImage = NSImage(cgImage: loaded.cgImage, size: .zero)
        ThumbnailCache.images.setObject(nsImage, forKey: key, cost: loaded.cgImage.bytesPerRow * loaded.cgImage.height)
        image = nsImage
      } else {
        missing = true
      }
    }
  }
}

// MARK: - Formatting

enum Format {
  static func time(_ date: Date) -> String {
    date.formatted(.dateTime.hour().minute().second())
  }

  static func dateTime(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute().second())
  }

  /// `now` is passed in so the text follows the model's clock and redraws with it.
  static func relative(_ date: Date, now: Date) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
    if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
    return date.formatted(.dateTime.month(.abbreviated).day())
  }

  static func duration(_ seconds: TimeInterval) -> String {
    if seconds < 10 { return String(format: "%.1fs", seconds) }
    if seconds < 60 { return "\(Int(seconds))s" }
    return "\(Int(seconds) / 60)m \(Int(seconds) % 60)s"
  }

  static func day(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
  }
}

enum Finder {
  static func reveal(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
    }
  }
}
