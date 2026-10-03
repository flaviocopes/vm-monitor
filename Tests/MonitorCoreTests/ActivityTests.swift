import Foundation
import Testing

@testable import MonitorCore

func start(
  _ id: String, _ command: String, _ args: [String] = [], at time: Double = 1000, agent: String = "cursor",
  session: String = "chat-1", cwd: String = "/Users/flavio/dev/skillscout", input: String? = nil
) -> String {
  var object: [String: Any] = [
    "v": 1, "event": "start", "id": id, "time": time, "pid": 4242, "command": command, "args": args,
    "cwd": cwd, "agent": agent, "session": session, "target": "vm"
  ]
  if let input { object["input"] = input }
  let data = try! JSONSerialization.data(withJSONObject: object)
  return String(decoding: data, as: UTF8.self)
}

func end(_ id: String, status: Int = 0, at time: Double = 1001, last: String = "") -> String {
  let object: [String: Any] = ["v": 1, "event": "end", "id": id, "time": time, "status": status, "last": last]
  return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

func events(_ lines: [String]) -> [LogEvent] {
  ActivityLog.decode(Data((lines.joined(separator: "\n") + "\n").utf8))
}

func temporaryFolder() -> URL {
  let folder = FileManager.default.temporaryDirectory.appending(path: "vm-monitor-tests-\(UUID().uuidString)")
  try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  return folder
}

func append(_ text: String, to url: URL) {
  if let handle = try? FileHandle(forWritingTo: url) {
    handle.seekToEndOfFile()
    handle.write(Data(text.utf8))
    try? handle.close()
  } else {
    try! Data(text.utf8).write(to: url)
  }
}

@Suite struct ActivityLogTests {
  @Test func readsOnlyWhatsNewAndWaitsForWholeLines() throws {
    let folder = temporaryFolder()
    var log = ActivityLog(folder: folder)

    let first = log.read()
    #expect(first.isReload)
    #expect(first.events.isEmpty)

    // The file appearing for the first time is a reload too, with everything in it.
    append(start("a", "open", ["build/Skillscout.app"]) + "\n", to: log.file)
    #expect(log.read().events.map(\.id) == ["a"])

    let line = end("a", last: "Skillscout is open")
    append(String(line.prefix(20)), to: log.file)
    #expect(log.read().events.isEmpty)

    append(String(line.dropFirst(20)) + "\n", to: log.file)
    let third = log.read()
    #expect(!third.isReload)
    #expect(third.events.map(\.event) == ["end"])
    #expect(third.events.first?.last == "Skillscout is open")
  }

  @Test func startsOverWhenTheLogRotates() throws {
    let folder = temporaryFolder()
    var log = ActivityLog(folder: folder)
    append(start("a", "shot") + "\n" + end("a") + "\n", to: log.file)
    #expect(log.read().events.count == 2)

    try FileManager.default.moveItem(at: log.file, to: log.previousFile)
    append(start("b", "ui", ["Skillscout"]) + "\n", to: log.file)
    let batch = log.read()
    #expect(batch.isReload)
    #expect(batch.events.map(\.id) == ["a", "a", "b"])
  }

  @Test func repairsALastLineCutInsideACharacter() {
    // testvm cuts `last` at 300 bytes, which can leave half of a two-byte "é".
    var bytes = Array(#"{"v":1,"event":"end","id":"a","time":1,"status":0,"last":"caf"#.utf8)
    bytes.append(0xC3)
    bytes += Array(#""}"#.utf8)
    bytes.append(0x0A)
    let decoded = ActivityLog.decode(Data(bytes))
    #expect(decoded.count == 1)
    #expect(decoded.first?.last?.hasPrefix("caf") == true)
  }

  @Test func skipsBrokenLines() {
    let decoded = events(["not json", start("a", "shot"), "{\"half\":"])
    #expect(decoded.map(\.id) == ["a"])
  }
}

@Suite struct ActivityTests {
  @Test func mergesStartAndEndIntoRuns() {
    let activity = Activity(events([
      start("a", "open", ["build/Skillscout.app"], at: 100),
      end("a", at: 103.5, last: "Skillscout is open")
    ]))
    let run = activity.runs[0]
    #expect(run.command == "open")
    #expect(run.agent == .cursor)
    #expect(run.duration == 3.5)
    #expect(run.last == "Skillscout is open")
    #expect(run.state(isAlive: { _ in false }) == .succeeded)
  }

  @Test func aRunWithoutAnEndIsRunningWhileItsProcessLives() {
    let activity = Activity(events([start("a", "open", ["Skillscout"], at: 100)]))
    let run = activity.runs[0]
    let now = Date(timeIntervalSince1970: 110)
    #expect(run.state(now: now, isAlive: { _ in true }) == .running)
    #expect(run.state(now: now, isAlive: { _ in false }) == .interrupted)
    #expect(run.state(now: Date(timeIntervalSince1970: 100 + 31 * 60), isAlive: { _ in true }) == .interrupted)
  }

  @Test func exitCodesFromSignalsCountAsInterrupted() {
    let activity = Activity(events([start("a", "open"), end("a", status: 130), start("b", "ui"), end("b", status: 1)]))
    #expect(activity.runs[0].state(isAlive: { _ in false }) == .interrupted)
    #expect(activity.runs[1].state(isAlive: { _ in false }) == .failed(1))
  }

  @Test func clicksBelongToTheAppTheChatUsedLast() {
    let activity = Activity(events([
      start("a", "open", ["dist/CLI Tools.app/"]),
      start("b", "click", ["10", "20"]),
      start("c", "click", ["10", "20"], session: "chat-2"),
      start("d", "shot", ["Skillscout"]),
      start("e", "key", ["cmd+a"]),
      start("f", "run", ["defaults read"])
    ]))
    #expect(activity.runs.map(\.app) == ["CLI Tools", "CLI Tools", nil, "Skillscout", "Skillscout", nil])
  }

  @Test func groupsRunsIntoChats() {
    let activity = Activity(events([
      start("a", "note", ["Checking the sort menu"], at: 100),
      start("b", "open", ["Skillscout.app"], at: 101),
      end("b", at: 104),
      start("c", "shot", [], at: 200, agent: "claude", session: "claude-77", cwd: "/Users/flavio/dev/noterepo"),
      start("d", "ui", ["Skillscout"], at: 300)
    ]))
    let sessions = activity.sessions
    #expect(sessions.map(\.sessionID) == ["chat-1", "claude-77"])
    #expect(sessions[0].commandCount == 2)
    #expect(sessions[0].note == "Checking the sort menu")
    #expect(sessions[0].apps == ["Skillscout"])
    #expect(sessions[0].latestRunID == "d")
    #expect(sessions[1].agent == .claude)
    #expect(sessions[1].cwd == "/Users/flavio/dev/noterepo")
  }

  @Test func listsAppsWithWhoOpenedThem() {
    let activity = Activity(events([
      start("a", "open", ["build/Skillscout.app"], at: 100),
      start("b", "shot", ["Skillscout"], at: 101),
      start("c", "ui", ["CLI Tools"], at: 102)
    ]))
    let apps = activity.apps
    #expect(apps.map(\.name) == ["CLI Tools", "Skillscout"])
    #expect(apps[1].commandCount == 2)
    #expect(apps[1].lastOpenID == "a")
    #expect(apps[0].lastOpenID == nil)
  }

  @Test func findsTheListingAClickCameFrom() {
    let activity = Activity(events([
      start("a", "ui", ["Skillscout"]),
      start("b", "ui", ["Skillscout"], session: "chat-2"),
      start("c", "click", ["255", "200"])
    ]))
    let click = activity.runs[2]
    #expect(activity.previous("ui", before: click)?.id == "a")
  }

  @Test func ignoresDuplicateStartsAndOrphanEnds() {
    let activity = Activity(events([start("a", "shot"), start("a", "ui"), end("zzz")]))
    #expect(activity.runs.count == 1)
    #expect(activity.runs[0].command == "shot")
  }

  @Test func theImageIsWhatASuccessfulShotPrinted() {
    let activity = Activity(events([
      start("a", "shot", ["Skillscout"]), end("a", last: "/tmp/testvm/Skillscout-101500.png"),
      start("b", "shot"), end("b", status: 1, last: "testvm: no window for Skillscout")
    ]))
    #expect(activity.runs[0].image?.path == "/tmp/testvm/Skillscout-101500.png")
    #expect(activity.runs[1].image == nil)
  }
}
