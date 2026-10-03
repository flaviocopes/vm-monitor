import MonitorCore
import SwiftUI

enum Scope {
  case all
  case session(Session)
  case app(String)

  var selection: Selection {
    switch self {
    case .all: .all
    case .session(let session): .session(session.id)
    case .app(let name): .app(name)
    }
  }

  var isSession: Bool {
    if case .session = self { return true }
    return false
  }
}

/// Every command in a scope, the newest first, grouped by day. Selecting one opens it in the inspector.
struct ActivityView: View {
  @Environment(AppModel.self) private var model
  let scope: Scope

  var body: some View {
    @Bindable var model = model
    let runs = model.runs(in: scope.selection)
    List(selection: $model.selectedRunID) {
      Section {
        header
          .padding(.vertical, 8)
          .selectionDisabled()
      }
      ForEach(days(runs), id: \.title) { day in
        Section(day.title) {
          ForEach(day.runs) { run in
            RunRow(run: run, showsAgent: !scope.isSession, showsApp: !isApp)
              .tag(run.id)
          }
        }
      }
    }
    .listStyle(.inset)
    .searchable(text: $model.search, placement: .toolbar, prompt: "Search commands")
    .overlay {
      if runs.isEmpty {
        if model.search.isEmpty {
          ContentUnavailableView(
            "Nothing yet",
            systemImage: "list.bullet.rectangle",
            description: Text("Every testvm command shows up here as soon as an agent runs it.")
          )
        } else {
          ContentUnavailableView.search(text: model.search)
        }
      }
    }
    .navigationTitle(title)
  }

  private var isApp: Bool {
    if case .app = scope { return true }
    return false
  }

  private var title: String {
    switch scope {
    case .all: "All activity"
    case .session(let session): model.project(session.cwd)
    case .app(let name): name
    }
  }

  @ViewBuilder private var header: some View {
    switch scope {
    case .all: AllHeader()
    case .session(let session): SessionHeader(session: session)
    case .app(let name): AppHeader(name: name)
    }
  }

  private func days(_ runs: [Run]) -> [(title: String, runs: [Run])] {
    var days: [(title: String, runs: [Run])] = []
    for run in runs {
      let title = Format.day(run.started)
      if days.last?.title == title {
        days[days.count - 1].runs.append(run)
      } else {
        days.append((title, [run]))
      }
    }
    return days
  }
}

struct RunRow: View {
  @Environment(AppModel.self) private var model
  let run: Run
  var showsAgent = true
  var showsApp = true

  var body: some View {
    let state = model.state(of: run)
    HStack(alignment: .top, spacing: 10) {
      Text(Format.time(run.started))
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 78, alignment: .leading)
      StatusIcon(state: state, isNote: run.isNote)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 3) {
        Text(model.summary(run))
          .italic(run.isNote)
          .lineLimit(run.isNote ? 4 : 2)
        if case .failed = state, let last = run.last {
          Text(last)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
        HStack(spacing: 6) {
          if showsAgent {
            AgentBadge(agent: run.agent, size: 14)
            Text("\(run.agent.name) · \(model.project(run.cwd))")
          }
          if showsApp, let app = run.app, !run.isNote {
            Text(app)
              .padding(.horizontal, 5)
              .background(Capsule().fill(.quaternary.opacity(0.6)))
          }
          if state == .running {
            Text(Format.duration(model.now.timeIntervalSince(run.started)))
              .monospacedDigit()
          } else if let duration = run.duration, !run.isNote {
            Text(Format.duration(duration))
              .monospacedDigit()
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      if let image = run.image {
        Thumbnail(url: image)
          .frame(width: 112, height: 73)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct AllHeader: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("All activity")
        .font(.title2.weight(.semibold))
      Text("\(model.todayCount) commands today, from \(model.sessions.filter { Calendar.current.isDateInToday($0.last) }.count) chats. Everything any agent did in the VM.")
        .foregroundStyle(.secondary)
    }
  }
}

private struct SessionHeader: View {
  @Environment(AppModel.self) private var model
  let session: Session
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AgentBadge(agent: session.agent, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(model.project(session.cwd))
            .font(.title2.weight(.semibold))
          Text("\(session.agent.name) in \(Project.tilde(session.cwd))")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if model.isActive(session) {
          Pill(text: "Working now", color: .green)
        }
      }
      if let prompt = model.prompt(of: session) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Asked to")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(prompt)
            .textSelection(.enabled)
            .lineLimit(expanded ? nil : 4)
          if prompt.count > 300 {
            Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }
              .buttonStyle(.link)
              .font(.caption)
          }
        }
      }
      if let note = session.note {
        Label(note, systemImage: "text.bubble")
      }
      HStack(spacing: 12) {
        Text("\(session.commandCount) commands, from \(Format.time(session.first)) to \(Format.time(session.last))")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if let transcript = model.transcript(of: session) {
          Button("Show Transcript") { Finder.reveal(transcript) }
            .controlSize(.small)
        }
        CopyButton(text: session.sessionID, label: "Copy Chat ID")
          .controlSize(.small)
      }
    }
  }
}

private struct AppHeader: View {
  @Environment(AppModel.self) private var model
  let name: String

  var body: some View {
    let info = model.apps.first { $0.name == name }
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Image(systemName: "macwindow")
          .font(.title2)
          .foregroundStyle(.secondary)
        Text(name)
          .font(.title2.weight(.semibold))
        if model.isRunningInVM(name) {
          Pill(text: "Open in the VM", color: .green)
        }
        Spacer()
      }
      if let info, let opener = model.opener(of: info) {
        Text("Last opened by \(opener.agent.name) in \(model.project(opener.cwd)) (\(Format.relative(opener.started, now: model.now))). \(info.commandCount) commands so far.")
          .foregroundStyle(.secondary)
      } else if let info {
        Text("\(info.commandCount) commands so far.")
          .foregroundStyle(.secondary)
      }
    }
  }
}
