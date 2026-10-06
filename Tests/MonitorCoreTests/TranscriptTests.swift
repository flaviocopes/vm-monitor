import Foundation
import Testing

@testable import MonitorCore

@Suite struct TranscriptTests {
  func object(_ json: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
  }

  @Test func readsCursorsPromptOutOfItsUserQuery() {
    let line = object(#"""
      {"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Saturday</timestamp>\n<user_query>\nAdd a sort menu\nto Skillscout\n</user_query>"}]}}
      """#)
    #expect(Transcripts.prompt(in: line) == "Add a sort menu to Skillscout")
  }

  @Test func readsClaudeCodesPromptAndSkipsCommands() {
    #expect(Transcripts.prompt(in: object(#"{"type":"user","message":{"role":"user","content":"Fix the icon"}}"#)) == "Fix the icon")
    #expect(Transcripts.prompt(in: object(#"{"type":"user","isMeta":true,"message":{"content":"Caveat: local"}}"#)) == nil)
    #expect(Transcripts.prompt(in: object(#"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#)) == nil)
    #expect(Transcripts.prompt(in: object(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#)) == nil)
  }

  @Test func readsCodexsUserMessage() {
    let line = object(#"{"type":"event_msg","payload":{"type":"user_message","message":"Release Soundscape 1.2"}}"#)
    #expect(Transcripts.prompt(in: line) == "Release Soundscape 1.2")
    #expect(Transcripts.prompt(in: object(#"{"type":"session_meta","payload":{"id":"x"}}"#)) == nil)
  }

  @Test func findsTheFirstPromptInAFile() throws {
    let folder = temporaryFolder()
    let file = folder.appending(path: "chat.jsonl")
    let lines = [
      #"{"type":"session_meta","payload":{"id":"x"}}"#,
      #"{"type":"user","message":{"content":"<command-name>/model</command-name>"}}"#,
      #"{"type":"user","message":{"content":"Test the new onboarding"}}"#,
      #"{"type":"user","message":{"content":"Second message"}}"#
    ]
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    #expect(Transcripts.firstPrompt(in: file) == "Test the new onboarding")
  }

  @Test func findsCursorChatsInAnyProjectFolder() throws {
    let home = temporaryFolder()
    let file = home.appending(path: ".cursor/projects/Users-flavio-dev-skillscout/agent-transcripts/chat-9/chat-9.jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: file, atomically: true, encoding: .utf8)
    let session = Session(
      id: "Cursor|chat-9", agent: .cursor, sessionID: "chat-9", cwd: "/", transcript: "/gone/chat-9.jsonl",
      first: .now, last: .now, commandCount: 1, note: nil, apps: [], latestRunID: "a"
    )
    #expect(Transcripts.locate(session, home: home)?.path == file.path)
  }

  @Test func findsCodexChatsByThreadAndDay() throws {
    let home = temporaryFolder()
    let thread = "01a0f7fc-d18f-7eb0-ac8f-42c450e7a719"
    let date = Date()
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    let day = String(format: "%04d/%02d/%02d", parts.year!, parts.month!, parts.day!)
    let file = home.appending(path: ".codex/sessions/\(day)/rollout-2026-10-01T17-02-16-\(thread).jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: file, atomically: true, encoding: .utf8)
    #expect(Transcripts.codexTranscript(threadID: thread, around: [date], home: home)?.path == file.path)
    #expect(Transcripts.codexTranscript(threadID: "codex-4242", around: [date], home: home) == nil)
  }

  @Test func findsClaudeChatsFromTheProjectFolderUp() throws {
    let home = temporaryFolder()
    let projects = home.appending(path: ".claude/projects/\(Transcripts.claudeFolderName("/Users/flavio/dev/noterepo"))")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let file = projects.appending(path: "session.jsonl")
    try "{}".write(to: file, atomically: true, encoding: .utf8)
    let found = Transcripts.claudeTranscript(cwd: "/Users/flavio/dev/noterepo/Sources", first: Date().addingTimeInterval(-2), home: home)
    #expect(found?.path == file.path)
  }

  @Test func claudeFolderNamesUseDashes() {
    #expect(Transcripts.claudeFolderName("/Users/flavio/dev/cli-tools") == "-Users-flavio-dev-cli-tools")
    #expect(Transcripts.claudeFolderName("/Users/flavio/.agents") == "-Users-flavio--agents")
  }

  @Test func cleansLongPrompts() {
    #expect(Transcripts.clean("  one\n\n two\tthree ") == "one two three")
    #expect(Transcripts.clean(String(repeating: "a ", count: 1500)).count == 2001)
  }
}

@Suite struct ProjectTests {
  @Test func namesTheFolderThatHoldsGit() throws {
    let root = temporaryFolder().appending(path: "skillscout")
    try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "Sources/App"), withIntermediateDirectories: true)
    #expect(Project.name(for: root.appending(path: "Sources/App").path) == "skillscout")
    #expect(Project.name(for: "/Users/flavio", home: "/Users/flavio") == "Home folder")
  }

  @Test func shortensPathsInTheHomeFolder() {
    #expect(Project.tilde("/Users/flavio/dev/skillscout", home: "/Users/flavio") == "~/dev/skillscout")
    #expect(Project.tilde("/tmp/testvm", home: "/Users/flavio") == "/tmp/testvm")
  }
}

@Suite struct VMTargetTests {
  @Test func readsTheTestvmConfig() {
    let pairs = VMTarget.parseConfig("# another Mac\nTEST_HOST=mini.local\nexport TEST_USER=\"flavio\"\n")
    #expect(pairs.map(\.0) == ["TEST_HOST", "TEST_USER"])
    #expect(pairs.map(\.1) == ["mini.local", "flavio"])
  }

  @Test func defaultsToTheTartVM() {
    let target = VMTarget.load(home: temporaryFolder())
    #expect(target.host == nil)
    #expect(target.user == "admin")
    #expect(target.name == "Test VM")
  }

  @Test func checksTheHostKeyOfAnotherMacOnly() {
    var target = VMTarget(key: URL(filePath: "/tmp/testvm_ed25519"))
    #expect(VM.sshArguments(target, address: "192.168.64.3").contains("StrictHostKeyChecking=no"))
    target.host = "mini.local"
    let arguments = VM.sshArguments(target, address: "mini.local")
    #expect(arguments.contains("StrictHostKeyChecking=accept-new"))
    #expect(!arguments.contains("UserKnownHostsFile=/dev/null"))
  }
}
