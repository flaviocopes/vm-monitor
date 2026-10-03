import Foundation

/// Reads `testvm`'s activity log a little at a time. Each `read` returns the lines added since the last one.
/// When `testvm` rotates the log past 20 MB into `activity.1.jsonl`, the next `read` starts over with both files.
public struct ActivityLog: Sendable {
  public static let defaultFolder = URL.homeDirectory.appending(path: "Library/Logs/testvm")

  public let folder: URL
  public var file: URL { folder.appending(path: "activity.jsonl") }
  public var previousFile: URL { folder.appending(path: "activity.1.jsonl") }

  /// What a command printed, saved by `testvm` next to the log.
  public func outputURL(for id: String) -> URL {
    folder.appending(path: "runs/\(id).txt")
  }

  private var loaded = false
  private var fileNumber: UInt64?
  private var offset: UInt64 = 0
  private var partialLine = Data()

  public init(folder: URL = ActivityLog.defaultFolder) {
    self.folder = folder
  }

  public struct Batch: Sendable {
    public var events: [LogEvent]
    /// The events are the whole history: replace what you have instead of adding to it.
    public var isReload: Bool
  }

  public mutating func read() -> Batch {
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
    let number = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0

    var batch = Batch(events: [], isReload: false)
    if !loaded || number != fileNumber || size < offset {
      loaded = true
      fileNumber = number
      offset = 0
      partialLine = Data()
      batch.isReload = true
      if let previous = try? Data(contentsOf: previousFile) {
        batch.events = Self.decode(previous)
      }
    }

    guard size > offset, let handle = try? FileHandle(forReadingFrom: file) else { return batch }
    defer { try? handle.close() }
    guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return batch }
    offset += UInt64(data.count)
    partialLine.append(data)
    // A line without its newline is still being written. Keep it for the next read.
    guard let newline = partialLine.lastIndex(of: 0x0A) else { return batch }
    batch.events += Self.decode(partialLine[..<newline])
    partialLine = Data(partialLine[partialLine.index(after: newline)...])
    return batch
  }

  static func decode(_ data: Data) -> [LogEvent] {
    let decoder = JSONDecoder()
    return data.split(separator: 0x0A).compactMap { line in
      // testvm cuts the last line of output at 300 bytes, which can split a character in two.
      let repaired = Data(String(decoding: line, as: UTF8.self).utf8)
      return try? decoder.decode(LogEvent.self, from: repaired)
    }
  }
}
