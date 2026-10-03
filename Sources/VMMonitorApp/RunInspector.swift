import MonitorCore
import SwiftUI

/// One command in full: the screenshot, the command line, what it printed, and who ran it.
struct RunInspector: View {
  @Environment(AppModel.self) private var model
  let run: Run

  var body: some View {
    let state = model.state(of: run)
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 8) {
          StatusIcon(state: state, isNote: run.isNote)
            .padding(.top, 3)
          Text(model.summary(run))
            .font(.title3.weight(.semibold))
            .textSelection(.enabled)
        }
        if !run.isNote {
          HStack(spacing: 8) {
            Pill(text: state.title, color: state.color)
            if let duration = run.duration {
              Text("took \(Format.duration(duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        if let image = run.image {
          screenshot(image)
        }
        CodeBlock(title: "Command", text: Describe.commandLine(run))
        if let output = model.output(of: run) {
          CodeBlock(title: state == .running ? "Output so far" : "Output", text: output)
        } else if !run.isNote, state != .running {
          Text("It didn't print anything.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Divider()
        details
      }
      .padding(18)
    }
  }

  private func screenshot(_ url: URL) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Thumbnail(url: url, maxPixels: 1400)
        .frame(maxWidth: .infinity)
        .frame(height: 240)
      if FileManager.default.fileExists(atPath: url.path) {
        Button("Show in Finder") { Finder.reveal(url) }
          .controlSize(.small)
      } else {
        Text("The screenshot is gone. macOS empties /tmp when the Mac restarts.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var details: some View {
    let session = model.session(run.sessionKey)
    return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
      GridRow {
        label("Agent")
        HStack(spacing: 6) {
          AgentBadge(agent: run.agent, size: 16)
          Text(run.agent.name)
        }
      }
      if let session, let prompt = model.prompt(of: session) {
        GridRow(alignment: .top) {
          label("Chat")
          Text(prompt)
            .lineLimit(4)
            .textSelection(.enabled)
        }
      }
      GridRow(alignment: .top) {
        label("Folder")
        Text(Project.tilde(run.cwd))
          .textSelection(.enabled)
      }
      if let app = run.app {
        GridRow {
          label("App")
          Text(app)
        }
      }
      GridRow {
        label("Started")
        Text(Format.dateTime(run.started))
      }
      if let status = run.status {
        GridRow {
          label("Exit status")
          Text("\(status)")
            .monospacedDigit()
        }
      }
      GridRow {
        label("Ran on")
        Text(run.target == "vm" ? "The test VM" : run.target)
      }
      if session != nil {
        GridRow {
          Color.clear.frame(width: 1, height: 1)
          Button("Show This Chat") { model.selection = .session(run.sessionKey) }
            .controlSize(.small)
        }
      }
    }
    .font(.callout)
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.trailing)
  }
}
