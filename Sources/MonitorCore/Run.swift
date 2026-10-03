import Foundation

/// One line of `~/Library/Logs/testvm/activity.jsonl`. `testvm` writes a `start` line when a command
/// begins and an `end` line with the same id when it finishes.
public struct LogEvent: Decodable, Sendable, Equatable {
  public var event: String
  public var id: String
  public var time: Double
  public var pid: Int32?
  public var command: String?
  public var args: [String]?
  public var cwd: String?
  public var agent: String?
  public var session: String?
  public var target: String?
  public var transcript: String?
  public var input: String?
  public var status: Int32?
  public var last: String?
}

/// Who ran a command. `testvm` writes `cursor`, `claude`, `codex` or `terminal`, and the name of
/// any other agent CLI it finds up the process tree.
public enum Agent: Hashable, Sendable {
  case cursor, claude, codex, terminal
  case other(String)

  public init(_ raw: String) {
    switch raw {
    case "cursor": self = .cursor
    case "claude": self = .claude
    case "codex": self = .codex
    case "terminal", "": self = .terminal
    default: self = .other(raw)
    }
  }

  public var name: String {
    switch self {
    case .cursor: "Cursor"
    case .claude: "Claude Code"
    case .codex: "Codex"
    case .terminal: "Terminal"
    case .other(let raw): raw.prefix(1).uppercased() + raw.dropFirst()
    }
  }
}

public enum RunState: Hashable, Sendable {
  case running, succeeded, failed(Int32), interrupted
}

/// One `testvm` command, from its start line and, once it finishes, its end line.
public struct Run: Identifiable, Hashable, Sendable {
  public let id: String
  public var started: Date
  public var ended: Date?
  public var pid: Int32
  public var command: String
  public var args: [String]
  public var cwd: String
  public var agent: Agent
  public var session: String
  public var target: String
  public var transcript: String?
  public var input: String?
  public var status: Int32?
  public var last: String?
  /// The app the command was about: named in its arguments, or the one the same chat used last.
  public var app: String?

  public init(
    id: String, started: Date, ended: Date? = nil, pid: Int32 = 0, command: String, args: [String] = [],
    cwd: String = "", agent: Agent = .terminal, session: String = "", target: String = "vm",
    transcript: String? = nil, input: String? = nil, status: Int32? = nil, last: String? = nil, app: String? = nil
  ) {
    self.id = id
    self.started = started
    self.ended = ended
    self.pid = pid
    self.command = command
    self.args = args
    self.cwd = cwd
    self.agent = agent
    self.session = session
    self.target = target
    self.transcript = transcript
    self.input = input
    self.status = status
    self.last = last
    self.app = app
  }

  init?(start event: LogEvent) {
    guard event.event == "start", let command = event.command else { return nil }
    self.init(
      id: event.id,
      started: Date(timeIntervalSince1970: event.time),
      pid: event.pid ?? 0,
      command: command,
      args: event.args ?? [],
      cwd: event.cwd ?? "",
      agent: Agent(event.agent ?? ""),
      session: event.session ?? "",
      target: event.target ?? "vm",
      transcript: event.transcript,
      input: event.input
    )
  }

  /// Groups the runs of one chat. Two agents can't share a session id, but keep them apart anyway.
  public var sessionKey: String { "\(agent.name)|\(session)" }

  public var isNote: Bool { command == "note" }

  public var duration: TimeInterval? { ended.map { $0.timeIntervalSince(started) } }

  /// The screenshot a successful `shot` printed.
  public var image: URL? {
    guard command == "shot", status == 0, let last, last.hasSuffix(".png") else { return nil }
    return URL(filePath: last)
  }

  /// A run with no end line is still going while its process lives. `testvm` ends with 130 or 143
  /// when Ctrl-C or the agent's timeout stops it.
  public func state(now: Date = .now, isAlive: (Int32) -> Bool) -> RunState {
    if let status {
      switch status {
      case 0: return .succeeded
      case 130, 143: return .interrupted
      default: return .failed(status)
      }
    }
    if now.timeIntervalSince(started) > 30 * 60 || !isAlive(pid) { return .interrupted }
    return .running
  }
}

extension Run {
  public static func processIsAlive(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    return kill(pid, 0) == 0 || errno == EPERM
  }
}
