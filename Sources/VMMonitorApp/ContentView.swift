import MonitorCore
import SwiftUI

struct ContentView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      Sidebar()
        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
    } detail: {
      Group {
        switch model.selection {
        case .live, nil:
          LiveView()
        case .all:
          ActivityView(scope: .all)
        case .session(let id):
          if let session = model.session(id) {
            ActivityView(scope: .session(session))
          } else {
            ContentUnavailableView("This chat is gone", systemImage: "bubble.left.and.exclamationmark.bubble.right")
          }
        case .app(let name):
          ActivityView(scope: .app(name))
        }
      }
      .inspector(isPresented: Binding(get: { model.selectedRunID != nil }, set: { if !$0 { model.selectedRunID = nil } })) {
        Group {
          if let run = model.selectedRun {
            RunInspector(run: run)
          } else {
            Color.clear
          }
        }
        .inspectorColumnWidth(min: 320, ideal: 420, max: 640)
      }
    }
    .onChange(of: model.selection) {
      model.selectedRunID = nil
      model.search = ""
    }
  }
}

struct Sidebar: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    List(selection: $model.selection) {
      Section {
        HStack(spacing: 8) {
          Image(systemName: "play.display")
            .foregroundStyle(.tint)
            .frame(width: 20)
          VStack(alignment: .leading, spacing: 1) {
            Text("Live")
            Text(model.vmState.title)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Circle()
            .fill(model.vmState.color)
            .frame(width: 8, height: 8)
        }
        .tag(Selection.live)
        HStack(spacing: 8) {
          Image(systemName: "list.bullet.rectangle")
            .foregroundStyle(.tint)
            .frame(width: 20)
          Text("All activity")
          Spacer()
          if model.todayCount > 0 {
            Text("\(model.todayCount) today")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .tag(Selection.all)
      }
      if !model.activeSessions.isEmpty {
        Section("Working now") {
          ForEach(model.activeSessions) { SessionRow(session: $0, isActive: true).tag(Selection.session($0.id)) }
        }
      }
      if !model.earlierSessions.isEmpty {
        Section("Earlier") {
          ForEach(model.earlierSessions.prefix(60)) { SessionRow(session: $0, isActive: false).tag(Selection.session($0.id)) }
        }
      }
      if !model.apps.isEmpty {
        Section("Apps") {
          ForEach(model.apps) { AppRow(app: $0).tag(Selection.app($0.name)) }
        }
      }
    }
    .listStyle(.sidebar)
  }
}

private struct SessionRow: View {
  @Environment(AppModel.self) private var model
  let session: Session
  let isActive: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      AgentBadge(agent: session.agent, size: 22)
        .overlay(alignment: .bottomTrailing) {
          if isActive {
            Circle()
              .fill(.green)
              .frame(width: 8, height: 8)
              .overlay(Circle().stroke(.background, lineWidth: 1.5))
              .offset(x: 2, y: 2)
          }
        }
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(model.project(session.cwd))
            .fontWeight(.medium)
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(Format.relative(session.last, now: model.now))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(session.note ?? model.prompt(of: session) ?? model.activity.run(session.latestRunID).map(model.summary) ?? "")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Text("\(session.agent.name) · \(session.commandCount) command\(session.commandCount == 1 ? "" : "s")")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct AppRow: View {
  @Environment(AppModel.self) private var model
  let app: AppInfo

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "macwindow")
        .foregroundStyle(.secondary)
        .frame(width: 20)
      Text(app.name)
        .lineLimit(1)
      Spacer()
      if model.isRunningInVM(app.name) {
        Text("Open")
          .font(.caption)
          .foregroundStyle(.green)
      }
    }
  }
}
