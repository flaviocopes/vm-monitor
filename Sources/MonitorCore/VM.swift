import Foundation

/// Where `testvm` runs apps: the `mac-test` VM under Tart, or the Mac named by `TEST_HOST` in `~/.config/testvm/config`.
public struct VMTarget: Sendable, Equatable {
  public var host: String?
  public var user = "admin"
  public var vmName = "mac-test"
  public var key: URL

  public static func load(home: URL = .homeDirectory) -> VMTarget {
    var target = VMTarget(key: home.appending(path: ".ssh/testvm_ed25519"))
    let config = home.appending(path: ".config/testvm/config")
    guard let text = try? String(contentsOf: config, encoding: .utf8) else { return target }
    for (key, value) in parseConfig(text) {
      switch key {
      case "TEST_HOST": target.host = value.isEmpty ? nil : value
      case "TEST_USER": target.user = value
      default: break
      }
    }
    return target
  }

  /// `testvm` sources the config as shell, but it only ever holds `KEY=value` lines.
  static func parseConfig(_ text: String) -> [(String, String)] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
      var trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("export ") { trimmed = String(trimmed.dropFirst(7)) }
      guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
      let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
      var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
      if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
        value = String(value.dropFirst().dropLast())
      }
      return (key, value)
    }
  }

  public var name: String { host ?? "Test VM" }
}

public enum VMState: Sendable, Equatable {
  case checking
  /// The address is empty while the VM boots and doesn't have one yet.
  case running(address: String)
  case stopped
  /// Tart has no VM called `mac-test`, or isn't installed.
  case missing
  case unreachable
}

public struct VMError: LocalizedError, Sendable {
  public let message: String
  public var errorDescription: String? { message }
}

public enum VM {
  /// Homebrew puts Tart in a different folder on Intel Macs, which can still watch a Mac mini.
  static let tart = ["/opt/homebrew/bin/tart", "/usr/local/bin/tart"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/tart"
  static let ssh = "/usr/bin/ssh"

  public static func state(of target: VMTarget) async -> VMState {
    if let host = target.host {
      let result = try? await Shell.run(ssh, sshArguments(target, address: host) + ["true"], timeout: 8)
      return result?.status == 0 ? .running(address: host) : .unreachable
    }
    guard let list = try? await Shell.run(tart, ["list", "--format", "json"], timeout: 8), list.status == 0,
      let vms = try? JSONSerialization.jsonObject(with: list.stdout) as? [[String: Any]],
      let vm = vms.first(where: { $0["Name"] as? String == target.vmName })
    else { return .missing }
    guard vm["Running"] as? Bool == true || vm["State"] as? String == "running" else { return .stopped }
    let ip = try? await Shell.run(tart, ["ip", target.vmName], timeout: 5)
    let address = ip.map { String(decoding: $0.stdout, as: UTF8.self) }?.trimmingCharacters(in: .whitespacesAndNewlines)
    return .running(address: ip?.status == 0 ? address ?? "" : "")
  }

  /// The same options as `testvm`, so the app shares its SSH connection instead of opening new ones.
  static func sshArguments(_ target: VMTarget, address: String) -> [String] {
    [
      "-i", target.key.path, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
      "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes", "-o", "ControlMaster=auto",
      "-o", "ControlPath=/tmp/testvm-ssh-%C", "-o", "ControlPersist=10m", "\(target.user)@\(address)"
    ]
  }

  /// A JPEG of the whole screen. It goes to its own file in the VM, so it never clashes with an agent's `testvm shot`.
  public static func screenshot(_ target: VMTarget, address: String) async throws -> Data {
    let command = "screencapture -x -t jpg /tmp/vm-monitor.jpg && cat /tmp/vm-monitor.jpg"
    let result = try await Shell.run(ssh, sshArguments(target, address: address) + [command], timeout: 10)
    guard result.status == 0, !result.stdout.isEmpty else {
      throw VMError(message: result.errorText ?? "The screenshot didn't come back.")
    }
    return result.stdout
  }

  /// The apps running from `~/Apps`, where `testvm open` copies them.
  public static func runningApps(_ target: VMTarget, address: String) async throws -> [String] {
    let command = #"ps -axo comm= | sed -n 's#.*/Apps/\([^/]*\)\.app/Contents/MacOS/.*#\1#p' | sort -u"#
    let result = try await Shell.run(ssh, sshArguments(target, address: address) + [command], timeout: 8)
    guard result.status == 0 else { throw VMError(message: result.errorText ?? "Couldn't list the apps.") }
    return String(decoding: result.stdout, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
  }
}

public struct ShellResult: Sendable {
  public var status: Int32
  public var stdout: Data
  public var stderr: Data

  var errorText: String? {
    let text = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
}

enum Shell {
  /// Runs a program off the main thread and collects what it prints. Stops it after `timeout` seconds.
  static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ShellResult {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        let job = Job(executable: executable, arguments: arguments)
        do {
          try job.process.run()
        } catch {
          continuation.resume(throwing: error)
          return
        }
        let timer = DispatchWorkItem { if job.process.isRunning { job.process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        // Read both pipes at once, or a full stderr pipe would block the program while we wait on stdout.
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
          job.errors = job.errorPipe.fileHandleForReading.readDataToEndOfFile()
          group.leave()
        }
        let output = job.outputPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        job.process.waitUntilExit()
        timer.cancel()
        continuation.resume(returning: ShellResult(status: job.process.terminationStatus, stdout: output, stderr: job.errors))
      }
    }
  }

  private final class Job: @unchecked Sendable {
    let process = Foundation.Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    var errors = Data()

    init(executable: String, arguments: [String]) {
      process.executableURL = URL(filePath: executable)
      process.arguments = arguments
      process.standardOutput = outputPipe
      process.standardError = errorPipe
      process.standardInput = FileHandle.nullDevice
    }
  }
}
