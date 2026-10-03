import Foundation

/// Everything that happened in the VM, built from the log one event at a time.
public struct Activity: Sendable {
  /// Oldest first, in the order the commands started.
  public private(set) var runs: [Run] = []
  private var positions: [String: Int] = [:]
  private var currentApp: [String: String] = [:]

  public init(_ events: [LogEvent] = []) {
    apply(events)
  }

  public mutating func apply(_ events: [LogEvent]) {
    for event in events { apply(event) }
  }

  public mutating func apply(_ event: LogEvent) {
    switch event.event {
    case "start":
      guard positions[event.id] == nil, var run = Run(start: event) else { return }
      if let app = Describe.app(named: run) {
        run.app = app
        currentApp[run.sessionKey] = app
      } else if Describe.actsOnCurrentApp(run.command) {
        run.app = currentApp[run.sessionKey]
      }
      positions[event.id] = runs.count
      runs.append(run)
    case "end":
      guard let index = positions[event.id] else { return }
      runs[index].ended = Date(timeIntervalSince1970: event.time)
      runs[index].status = event.status ?? 0
      runs[index].last = event.last.flatMap { $0.isEmpty ? nil : $0 }
    default:
      break
    }
  }

  public func run(_ id: String) -> Run? {
    positions[id].map { runs[$0] }
  }

  /// The last `command` the same chat ran before `run`, like the `ui` listing a click came from.
  public func previous(_ command: String, before run: Run) -> Run? {
    guard let index = positions[run.id] else { return nil }
    return runs[..<index].last { $0.command == command && $0.sessionKey == run.sessionKey }
  }

  // MARK: - Chats

  /// One entry per chat, the most recent first.
  public var sessions: [Session] {
    var byKey: [String: Session] = [:]
    for run in runs {
      let finished = run.ended ?? run.started
      if var session = byKey[run.sessionKey] {
        session.last = max(session.last, finished)
        session.cwd = run.cwd
        session.transcript = run.transcript ?? session.transcript
        session.latestRunID = run.id
        if run.isNote {
          session.note = run.args.joined(separator: " ")
        } else {
          session.commandCount += 1
        }
        if let app = run.app {
          session.apps.removeAll { $0 == app }
          session.apps.insert(app, at: 0)
        }
        byKey[run.sessionKey] = session
      } else {
        byKey[run.sessionKey] = Session(
          id: run.sessionKey,
          agent: run.agent,
          sessionID: run.session,
          cwd: run.cwd,
          transcript: run.transcript,
          first: run.started,
          last: finished,
          commandCount: run.isNote ? 0 : 1,
          note: run.isNote ? run.args.joined(separator: " ") : nil,
          apps: run.app.map { [$0] } ?? [],
          latestRunID: run.id
        )
      }
    }
    return byKey.values.sorted { $0.last > $1.last }
  }

  // MARK: - Apps

  /// Every app the agents touched, the most recent first.
  public var apps: [AppInfo] {
    var byName: [String: AppInfo] = [:]
    for run in runs {
      guard let name = run.app else { continue }
      var info = byName[name] ?? AppInfo(name: name, last: run.started)
      info.last = max(info.last, run.started)
      info.commandCount += 1
      if run.command == "open" || run.command == "install" { info.lastOpenID = run.id }
      byName[name] = info
    }
    return byName.values.sorted { $0.last > $1.last }
  }
}

public struct Session: Identifiable, Hashable, Sendable {
  public let id: String
  public var agent: Agent
  public var sessionID: String
  /// The folder of the latest command, usually the project the agent works on.
  public var cwd: String
  public var transcript: String?
  public var first: Date
  public var last: Date
  public var commandCount: Int
  /// What the agent said it's testing, with `testvm note`.
  public var note: String?
  /// The apps it touched, the most recent first.
  public var apps: [String]
  public var latestRunID: String

  public func isActive(at now: Date, running: Bool) -> Bool {
    running || now.timeIntervalSince(last) < 3 * 60
  }
}

public struct AppInfo: Identifiable, Hashable, Sendable {
  public var id: String { name }
  public let name: String
  public var last: Date
  public var commandCount = 0
  /// The latest `open` or `install`, to say who put the build in the VM.
  public var lastOpenID: String?
}
