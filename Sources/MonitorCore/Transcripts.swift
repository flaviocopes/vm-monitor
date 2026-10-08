import Foundation

/// Finds the chat behind a session and the prompt that started it, so the app can say what each agent works on.
/// Cursor keeps chats in `~/.cursor/projects/*/agent-transcripts`, Codex in `~/.codex/sessions/yyyy/MM/dd`
/// and Claude Code in `~/.claude/projects/<folder with dashes>`.
public enum Transcripts {
  public static func locate(_ session: Session, home: URL = .homeDirectory) -> URL? {
    let manager = FileManager.default
    switch session.agent {
    case .cursor:
      if let recorded = session.transcript, manager.fileExists(atPath: recorded) { return URL(filePath: recorded) }
      let projects = home.appending(path: ".cursor/projects")
      let folders = (try? manager.contentsOfDirectory(atPath: projects.path)) ?? []
      let id = session.sessionID
      return folders.lazy
        .map { projects.appending(path: "\($0)/agent-transcripts/\(id)/\(id).jsonl") }
        .first { manager.fileExists(atPath: $0.path) }
    case .codex:
      return codexTranscript(threadID: session.sessionID, around: [session.first, session.last], home: home)
    case .claude:
      return claudeTranscript(cwd: session.cwd, first: session.first, home: home)
    case .terminal, .other:
      return nil
    }
  }

  static func codexTranscript(threadID: String, around dates: [Date], home: URL) -> URL? {
    // Without CODEX_THREAD_ID, testvm names the session after the codex process instead.
    guard threadID.count >= 32 else { return nil }
    let manager = FileManager.default
    var days: [String] = []
    for date in dates + dates.map({ $0.addingTimeInterval(-86_400) }) {
      let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
      guard let year = parts.year, let month = parts.month, let day = parts.day else { continue }
      let folder = String(format: "%04d/%02d/%02d", year, month, day)
      if !days.contains(folder) { days.append(folder) }
    }
    for day in days {
      let folder = home.appending(path: ".codex/sessions/\(day)")
      let files = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
      if let file = files.first(where: { $0.contains(threadID) && $0.hasSuffix(".jsonl") }) {
        return folder.appending(path: file)
      }
    }
    return nil
  }

  /// Claude Code doesn't name its chat in the environment, so pick the transcript in the project's folder
  /// that started last before the first command, and was still being written after it.
  static func claudeTranscript(cwd: String, first: Date, home: URL) -> URL? {
    let manager = FileManager.default
    var folder = URL(filePath: cwd)
    while folder.path != "/" {
      let projects = home.appending(path: ".claude/projects/\(claudeFolderName(folder.path))")
      let names = (try? manager.contentsOfDirectory(atPath: projects.path)) ?? []
      let candidates: [(url: URL, created: Date, modified: Date)] = names.filter { $0.hasSuffix(".jsonl") }.compactMap { name in
        let url = projects.appending(path: name)
        guard let attributes = try? manager.attributesOfItem(atPath: url.path),
          let created = attributes[.creationDate] as? Date,
          let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return (url, created, modified)
      }
      let live = candidates.filter { $0.modified >= first.addingTimeInterval(-5) }
      if let best = live.filter({ $0.created <= first.addingTimeInterval(5) }).max(by: { $0.created < $1.created })
        ?? live.max(by: { $0.modified < $1.modified })
      {
        return best.url
      }
      folder.deleteLastPathComponent()
    }
    return nil
  }

  /// `/Users/flavio/dev/my.app` → `-Users-flavio-dev-my-app`.
  static func claudeFolderName(_ path: String) -> String {
    String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
  }

  /// The first thing the user asked in the chat. Reads at most the first 4 MB.
  public static func firstPrompt(in url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 4 << 20) else { return nil }
    for line in data.split(separator: 0x0A) {
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
      if let prompt = prompt(in: object) { return prompt }
    }
    return nil
  }

  static func prompt(in object: [String: Any]) -> String? {
    var raw: String?
    let message = object["message"] as? [String: Any]
    if object["role"] as? String == "user" {
      raw = text(message?["content"])
    } else if object["type"] as? String == "user", object["isMeta"] as? Bool != true {
      raw = text(message?["content"])
    } else if object["type"] as? String == "event_msg", let payload = object["payload"] as? [String: Any],
      payload["type"] as? String == "user_message"
    {
      raw = payload["message"] as? String
    }
    guard let raw else { return nil }
    let prompt = clean(raw)
    // Commands and context the agent added before the real prompt, like Claude Code's <command-name>.
    if prompt.isEmpty || prompt.hasPrefix("<") || prompt.hasPrefix("Caveat:") { return nil }
    return prompt
  }

  static func text(_ content: Any?) -> String? {
    if let string = content as? String { return string }
    guard let parts = content as? [[String: Any]] else { return nil }
    let texts = parts.compactMap { part -> String? in
      guard let type = part["type"] as? String, type == "text" || type == "input_text" else { return nil }
      return part["text"] as? String
    }
    return texts.isEmpty ? nil : texts.joined(separator: "\n")
  }

  /// Cursor wraps the prompt in `<user_query>` after attachments and context. Keep only the prompt, on one line.
  public static func clean(_ text: String) -> String {
    var prompt = Substring(text)
    if let start = prompt.range(of: "<user_query>") {
      let end = prompt.range(of: "</user_query>", range: start.upperBound..<prompt.endIndex)
      prompt = prompt[start.upperBound..<(end?.lowerBound ?? prompt.endIndex)]
    }
    let words = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return words.count > 2000 ? String(words.prefix(2000)) + "…" : words
  }
}

public enum Project {
  /// The project a folder belongs to: the folder that holds `.git`, or the folder itself.
  public static func name(for cwd: String, home: String = NSHomeDirectory()) -> String {
    guard !cwd.isEmpty else { return "Unknown folder" }
    if cwd == home { return "Home folder" }
    let manager = FileManager.default
    var folder = URL(filePath: cwd)
    while folder.path != "/", folder.path != home {
      if manager.fileExists(atPath: folder.appending(path: ".git").path) { return folder.lastPathComponent }
      folder.deleteLastPathComponent()
    }
    return URL(filePath: cwd).lastPathComponent
  }

  /// `/Users/flavio/dev/skill-cabinet` → `~/dev/skill-cabinet`.
  public static func tilde(_ path: String, home: String = NSHomeDirectory()) -> String {
    if path == home { return "~" }
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }
}
