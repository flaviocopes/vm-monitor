import AppKit
import MonitorCore
import Observation

enum Selection: Hashable {
  case live
  case all
  case session(String)
  case app(String)
}

/// What the window shows. `testvm` appends to its activity log while agents work, so the model reads
/// the new lines every second, checks the VM every 3 seconds, and grabs its screen every 2 while Live is open.
@MainActor @Observable
final class AppModel {
  let target = VMTarget.load()
  /// The screenshot script sets the VM's state and screen itself, so it turns this off.
  let watchesVM: Bool

  private(set) var activity = Activity()
  private(set) var sessions: [Session] = []
  private(set) var apps: [AppInfo] = []
  var selection: Selection? = .live
  var selectedRunID: String?
  var search = ""

  var vmState: VMState = .checking
  var runningApps: [String] = []
  var screen: NSImage?
  var screenDate: Date?
  private(set) var screenError: String?
  var liveScreen = true
  /// Moves every second, for running times and "2 min ago".
  private(set) var now = Date.now

  @ObservationIgnored private var log = ActivityLog()
  @ObservationIgnored private var outputs: [String: String] = [:]
  @ObservationIgnored private var listings: [String: [Control]] = [:]
  @ObservationIgnored private var projects: [String: String] = [:]
  private var prompts: [String: ChatInfo] = [:]

  private struct ChatInfo {
    var prompt: String?
    var transcript: URL?
    var checked: Date
  }

  var logFile: URL { log.file }

  init(watchesVM: Bool = true) {
    self.watchesVM = watchesVM
  }

  // MARK: - Watching

  func watch() async {
    var ticks = 0
    while !Task.isCancelled {
      await readLog()
      now = .now
      if watchesVM, ticks % 3 == 0 { await refreshVM() }
      if ticks % 30 == 0 { loadChats() }
      ticks += 1
      try? await Task.sleep(for: .seconds(1))
    }
  }

  func reload() {
    log = ActivityLog()
    outputs = [:]
    listings = [:]
    prompts = [:]
    Task { await readLog() }
  }

  private func readLog() async {
    let current = log
    let (updated, batch) = await Task.detached {
      var copy = current
      let batch = copy.read()
      return (copy, batch)
    }.value
    log = updated
    guard batch.isReload || !batch.events.isEmpty else { return }
    if batch.isReload {
      activity = Activity(batch.events)
    } else {
      activity.apply(batch.events)
    }
    sessions = activity.sessions
    apps = activity.apps
    if let id = selectedRunID, activity.run(id) == nil { selectedRunID = nil }
    loadChats()
  }

  private func refreshVM() async {
    vmState = await VM.state(of: target)
    guard case .running(let address) = vmState, !address.isEmpty else {
      runningApps = []
      screen = nil
      return
    }
    if windowIsVisible, let names = try? await VM.runningApps(target, address: address) {
      runningApps = names
    }
  }

  /// Runs while the Live view is on screen.
  func watchScreen() async {
    while watchesVM, !Task.isCancelled {
      if liveScreen, windowIsVisible, case .running(let address) = vmState, !address.isEmpty {
        do {
          let data = try await VM.screenshot(target, address: address)
          if let image = await Task.detached(operation: { Images.downsample(data, maxPixels: 2400) }).value {
            screen = NSImage(cgImage: image.cgImage, size: .zero)
            screenDate = .now
            screenError = nil
          }
        } catch {
          screenError = error.localizedDescription
        }
      }
      try? await Task.sleep(for: .seconds(2))
    }
  }

  private var windowIsVisible: Bool {
    NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
  }

  // MARK: - Chats

  /// Looks up each chat's transcript once, and again every 30 seconds while it isn't found.
  private func loadChats() {
    for session in sessions {
      if let info = prompts[session.id], info.prompt != nil || now.timeIntervalSince(info.checked) < 30 { continue }
      prompts[session.id] = ChatInfo(prompt: nil, transcript: nil, checked: now)
      Task {
        let (url, prompt) = await Task.detached {
          let url = Transcripts.locate(session)
          return (url, url.flatMap(Transcripts.firstPrompt))
        }.value
        prompts[session.id] = ChatInfo(prompt: prompt, transcript: url, checked: .now)
      }
    }
  }

  func prompt(of session: Session) -> String? { prompts[session.id]?.prompt }
  func transcript(of session: Session) -> URL? { prompts[session.id]?.transcript }

  func session(_ id: String) -> Session? { sessions.first { $0.id == id } }

  func project(_ cwd: String) -> String {
    if let name = projects[cwd] { return name }
    let name = Project.name(for: cwd)
    projects[cwd] = name
    return name
  }

  // MARK: - Runs

  /// Only a run without an end line depends on the clock, so finished rows don't redraw every second.
  func state(of run: Run) -> RunState {
    if run.status != nil { return run.state(isAlive: { _ in false }) }
    return run.state(now: now, isAlive: Run.processIsAlive)
  }

  var runningRuns: [Run] {
    activity.runs.suffix(300).filter { $0.status == nil && state(of: $0) == .running }
  }

  private var runningSessions: Set<String> { Set(runningRuns.map(\.sessionKey)) }

  func isActive(_ session: Session) -> Bool {
    session.isActive(at: now, running: runningSessions.contains(session.id))
  }

  var activeSessions: [Session] {
    let running = runningSessions
    return sessions.filter { $0.isActive(at: now, running: running.contains($0.id)) }
  }

  var earlierSessions: [Session] {
    let running = runningSessions
    return sessions.filter { !$0.isActive(at: now, running: running.contains($0.id)) }
  }

  /// Chats that used the VM in the last 90 seconds. Two at once can click on each other's apps.
  var overlapping: [Session] {
    let running = runningSessions
    return sessions.filter { running.contains($0.id) || now.timeIntervalSince($0.last) < 90 }
  }

  var selectedRun: Run? { selectedRunID.flatMap(activity.run) }

  func runs(in selection: Selection?) -> [Run] {
    var runs: [Run]
    switch selection {
    case .session(let id): runs = activity.runs.filter { $0.sessionKey == id }
    case .app(let name): runs = activity.runs.filter { $0.app == name }
    default: runs = activity.runs
    }
    let query = search.trimmingCharacters(in: .whitespaces)
    if !query.isEmpty {
      runs = runs.filter { run in
        [summary(run), Describe.commandLine(run), project(run.cwd), run.agent.name, state(of: run).title, run.last ?? ""]
          .contains { $0.localizedCaseInsensitiveContains(query) }
      }
    }
    return runs.reversed()
  }

  var todayCount: Int {
    let start = Calendar.current.startOfDay(for: now)
    return activity.runs.reversed().prefix { $0.started >= start }.count
  }

  func summary(_ run: Run) -> String {
    Describe.summary(run, clicked: clicked(run))
  }

  /// The control a click landed on, from the `testvm ui` listing the same chat read before it.
  func clicked(_ run: Run) -> Control? {
    guard run.command == "click", run.args.count >= 2, let x = Int(run.args[0]), let y = Int(run.args[1]),
      let listing = activity.previous("ui", before: run)
    else { return nil }
    if listings[listing.id] == nil {
      listings[listing.id] = output(of: listing).map(Control.parse) ?? []
    }
    return Control.at(x: x, y: y, in: listings[listing.id] ?? [])
  }

  /// What the command printed. A running command's output is read fresh every time.
  func output(of run: Run) -> String? {
    if let cached = outputs[run.id] { return cached.isEmpty ? nil : cached }
    let data = try? Data(contentsOf: log.outputURL(for: run.id))
    let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    if run.ended != nil { outputs[run.id] = text }
    return text.isEmpty ? nil : text
  }

  /// Who last put the app in the VM.
  func opener(of app: AppInfo) -> Run? { app.lastOpenID.flatMap(activity.run) }

  func isRunningInVM(_ app: String) -> Bool { runningApps.contains(app) }
}
