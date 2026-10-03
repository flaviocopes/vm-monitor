import MonitorCore
import SwiftUI

struct LiveView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        header
        if model.overlapping.count > 1 { overlapWarning }
        Screen()
        working
        if !model.runningApps.isEmpty { apps }
        latest
      }
      .padding(24)
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Live")
    .toolbar {
      ToolbarItem {
        Toggle(isOn: $model.liveScreen) {
          Label(model.liveScreen ? "Pause Screen" : "Resume Screen", systemImage: model.liveScreen ? "pause.fill" : "play.fill")
        }
        .help(model.liveScreen ? "Stop refreshing the VM's screen" : "Refresh the VM's screen every 2 seconds")
      }
    }
    .task { await model.watchScreen() }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(model.vmState.color)
        .frame(width: 10, height: 10)
      Text(model.target.name)
        .font(.title2.weight(.semibold))
      Text(model.vmState.title)
        .foregroundStyle(.secondary)
      Spacer()
    }
  }

  private var overlapWarning: some View {
    Card(tint: .orange) {
      Label {
        VStack(alignment: .leading, spacing: 3) {
          Text("\(model.overlapping.count) agents are using the VM at the same time")
            .fontWeight(.semibold)
          Text(model.overlapping.map { "\($0.agent.name) in \(model.project($0.cwd))" }.formatted(.list(type: .and)) + ". Their clicks and keys go to whatever app is in front, so they can get in each other's way.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
    }
  }

  private var working: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(text: "Working now")
      if model.activeSessions.isEmpty {
        Text("No agent has used the VM in the last 3 minutes.")
          .foregroundStyle(.secondary)
      }
      ForEach(model.activeSessions) { SessionCard(session: $0) }
    }
  }

  private var apps: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(text: "Open in the VM")
      ForEach(model.runningApps, id: \.self) { name in
        let info = model.apps.first { $0.name == name }
        let opener = info.flatMap(model.opener)
        Button {
          model.selection = .app(name)
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "macwindow")
              .foregroundStyle(.secondary)
            Text(name)
              .fontWeight(.medium)
            if let opener {
              Text("opened by \(opener.agent.name) in \(model.project(opener.cwd)) (\(Format.relative(opener.started, now: model.now)))")
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
      }
    }
  }

  private var latest: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        SectionTitle(text: "Latest")
        Button("Show All") { model.selection = .all }
          .buttonStyle(.link)
      }
      let runs = Array(model.activity.runs.suffix(8).reversed())
      if runs.isEmpty {
        Text("Nothing yet. Every testvm command shows up here as soon as an agent runs it.")
          .foregroundStyle(.secondary)
      }
      ForEach(runs) { run in
        Button {
          model.selectedRunID = run.id
        } label: {
          RunRow(run: run, showsAgent: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.summary(run))
        Divider()
      }
    }
  }
}

/// The VM's screen, refreshed every 2 seconds while the view is open.
private struct Screen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.black.opacity(0.88))
      if let screen = model.screen, model.vmState.isRunning {
        Image(nsImage: screen)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .opacity(model.liveScreen ? 1 : 0.6)
      } else {
        VStack(spacing: 8) {
          Image(systemName: placeholderSymbol)
            .font(.system(size: 34, weight: .light))
          Text(placeholder)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
        }
        .foregroundStyle(.white.opacity(0.7))
      }
    }
    .aspectRatio(1512 / 982, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(alignment: .bottomLeading) {
      if model.vmState.isRunning {
        Text(caption)
          .font(.caption.weight(.medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Capsule().fill(.black.opacity(0.55)))
          .padding(10)
      }
    }
  }

  private var caption: String {
    if !model.liveScreen { return "Paused" }
    if let error = model.screenError { return error }
    guard let date = model.screenDate else { return "Loading the screen…" }
    let seconds = Int(model.now.timeIntervalSince(date))
    return seconds < 3 ? "Live" : "Updated \(seconds)s ago"
  }

  private var placeholderSymbol: String {
    switch model.vmState {
    case .running: "hourglass"
    case .stopped: "moon.zzz"
    default: "exclamationmark.triangle"
    }
  }

  private var placeholder: String {
    switch model.vmState {
    case .checking: "Looking for the VM…"
    case .running(let address): address.isEmpty ? "The VM is starting up." : "Loading the screen…"
    case .stopped: "The VM is stopped. It starts on its own the next time an agent runs testvm."
    case .missing: "There's no VM called mac-test. Run testvm setup to create it."
    case .unreachable: "Can't reach \(model.target.name) over SSH."
    }
  }
}

private struct SessionCard: View {
  @Environment(AppModel.self) private var model
  let session: Session

  var body: some View {
    Button {
      model.selection = .session(session.id)
    } label: {
      Card {
        HStack(alignment: .top, spacing: 12) {
          AgentBadge(agent: session.agent, size: 32)
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
              Text(model.project(session.cwd))
                .font(.headline)
              Text(session.agent.name)
                .foregroundStyle(.secondary)
              Spacer()
              Text(Format.relative(session.last, now: model.now))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let prompt = model.prompt(of: session) {
              Text(prompt)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
            if let note = session.note {
              Label(note, systemImage: "text.bubble")
                .font(.callout)
            }
            if let run = model.activity.run(session.latestRunID), !run.isNote {
              HStack(spacing: 6) {
                StatusIcon(state: model.state(of: run))
                Text(model.summary(run))
                  .lineLimit(1)
                if model.state(of: run) == .running {
                  Text(Format.duration(model.now.timeIntervalSince(run.started)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
              }
              .font(.callout)
            }
          }
        }
        .contentShape(Rectangle())
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(model.project(session.cwd)), \(session.agent.name)")
  }
}
