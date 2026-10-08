import Foundation

/// Turns `testvm` commands into plain words.
public enum Describe {
  /// The app a command names: `open` and `install` take a path or a name, `quit`, `shot`, `ui` and `logs` a name.
  static func app(named run: Run) -> String? {
    guard let first = run.args.first, !first.isEmpty else { return nil }
    switch run.command {
    case "open", "install": return appName(first)
    case "quit", "shot", "ui", "logs": return first
    default: return nil
    }
  }

  /// Commands that act on whatever app is in front, so they belong to the app the chat used last.
  static func actsOnCurrentApp(_ command: String) -> Bool {
    ["click", "type", "key", "script", "shot"].contains(command)
  }

  /// `build/Debug/Skill Cabinet.app/` → `Skill Cabinet`.
  public static func appName(_ pathOrName: String) -> String {
    var trimmed = pathOrName
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    let last = (trimmed as NSString).lastPathComponent
    return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
  }

  public static func summary(_ run: Run, clicked: Control? = nil) -> String {
    let args = run.args
    let first = args.first
    switch run.command {
    case "open":
      guard let first else { return "Opened an app" }
      let verb = first.hasSuffix(".app") || first.hasSuffix(".app/") ? "Opened" : "Relaunched"
      let extra = args.count > 1 ? " with " + args.dropFirst().joined(separator: " ") : ""
      return "\(verb) \(appName(first))\(extra)"
    case "install":
      return "Copied \(first.map(appName) ?? "an app") into the VM"
    case "quit":
      return "Quit \(first ?? "the app")"
    case "shot":
      return first.map { "Took a screenshot of \($0)" } ?? "Took a screenshot of the screen"
    case "ui":
      return "Read the controls of \(first ?? "the app")"
    case "click":
      if let clicked {
        if let title = clicked.title { return "Clicked “\(title)”" }
        return "Clicked the \(clicked.kind)"
      }
      return args.count >= 2 ? "Clicked at \(args[0]), \(args[1])" : "Clicked"
    case "type":
      return "Typed “\(args.joined(separator: " "))”"
    case "key":
      return "Pressed \(keys(first ?? ""))"
    case "script":
      if let item = run.input.flatMap(menuItem) { return "Chose “\(item)” from a menu" }
      return "Ran an AppleScript"
    case "logs":
      return "Read the logs of \(first ?? "the app")"
    case "push":
      return "Copied \(fileName(first)) into the VM"
    case "pull":
      return "Copied \(fileName(first)) out of the VM"
    case "run":
      return "Ran \(args.joined(separator: " "))"
    case "ssh":
      return "Opened a shell in the VM"
    case "start":
      return "Started the VM"
    case "stop":
      return "Stopped the VM"
    case "status":
      return "Checked whether the VM is running"
    case "setup":
      return "Set up the VM"
    case "note":
      return args.joined(separator: " ")
    default:
      return commandLine(run)
    }
  }

  /// The command as the agent typed it, quoted for a shell.
  public static func commandLine(_ run: Run) -> String {
    var line = (["testvm", run.command] + run.args.map(shellQuote)).joined(separator: " ")
    if let input = run.input, !input.isEmpty { line += " <<'EOF'\n\(input)\nEOF" }
    return line
  }

  static func shellQuote(_ word: String) -> String {
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=+,@%")
    if !word.isEmpty, word.unicodeScalars.allSatisfy(safe.contains) { return word }
    return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func fileName(_ path: String?) -> String {
    guard let path, !path.isEmpty else { return "files" }
    var trimmed = path
    while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
    return (trimmed as NSString).lastPathComponent
  }

  /// `cmd+shift+s` → `⇧⌘S`, in the order the menus use.
  public static func keys(_ combo: String) -> String {
    let parts = combo.split(separator: "+").map(String.init)
    guard let key = parts.last else { return combo }
    let modifiers = Set(parts.dropLast().map { $0.lowercased() })
    var symbols = ""
    if modifiers.contains("ctrl") || modifiers.contains("control") { symbols += "⌃" }
    if modifiers.contains("option") || modifiers.contains("opt") || modifiers.contains("alt") { symbols += "⌥" }
    if modifiers.contains("shift") { symbols += "⇧" }
    if modifiers.contains("cmd") || modifiers.contains("command") { symbols += "⌘" }
    let named: [String: String] = [
      "return": "Return", "enter": "Enter", "tab": "Tab", "esc": "Esc", "escape": "Esc", "space": "Space",
      "delete": "Delete", "fwd-delete": "Forward Delete", "home": "Home", "end": "End",
      "page-up": "Page Up", "page-down": "Page Down",
      "left": "←", "arrow-left": "←", "right": "→", "arrow-right": "→",
      "up": "↑", "arrow-up": "↑", "down": "↓", "arrow-down": "↓"
    ]
    if let name = named[key.lowercased()] {
      return symbols.isEmpty || name.count == 1 ? symbols + name : symbols + " " + name
    }
    return symbols + key.uppercased()
  }

  /// The menu item an AppleScript clicks, like `click menu item "Settings…" of menu …`.
  public static func menuItem(in script: String) -> String? {
    guard let match = script.firstMatch(of: /click menu item "([^"]+)"/) else { return nil }
    return String(match.1)
  }
}

/// One line of `testvm ui`, like `AXButton "Find repeated tasks" (disabled)  center 976,113`.
public struct Control: Hashable, Sendable {
  public var role: String
  /// The label in quotes. Controls without one show their type in brackets instead.
  public var title: String?
  /// The type in brackets, like `search text field`, or the role when there's none.
  public var kind: String
  public var value: String?
  public var x: Int
  public var y: Int

  public static func parse(_ listing: String) -> [Control] {
    let pattern = /^(\S+) (?:"(.*)"|\[(.*?)\])(?: = (.*?))?(?: \(disabled\))?  center (-?\d+),(-?\d+)$/
    return listing.split(whereSeparator: \.isNewline).compactMap { line in
      guard let match = String(line).wholeMatch(of: pattern), let x = Int(match.5), let y = Int(match.6) else {
        return nil
      }
      let role = String(match.1)
      return Control(
        role: role,
        title: match.2.map(String.init),
        kind: match.3.map(String.init) ?? role,
        value: match.4.map(String.init),
        x: x,
        y: y
      )
    }
  }

  /// The control an agent clicked. Agents click the centers `testvm ui` prints, so only a point within
  /// 2 points of a center counts. The front-most control comes last in the listing.
  public static func at(x: Int, y: Int, in controls: [Control]) -> Control? {
    controls.last { abs($0.x - x) <= 2 && abs($0.y - y) <= 2 }
  }
}
