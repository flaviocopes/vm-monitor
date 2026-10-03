import SwiftUI

@main
struct VMMonitorApp: App {
  @State private var model = AppModel()

  init() {
    AppUpdater.shared.start(repository: "flaviocopes/vm-monitor")
  }

  var body: some Scene {
    WindowGroup("VM Monitor") {
      ContentView()
        .environment(model)
        .frame(minWidth: 960, minHeight: 620)
        .task { await model.watch() }
    }
    .defaultSize(width: 1320, height: 880)
    .windowToolbarStyle(.unified(showsTitle: true))
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") {
          AppUpdater.shared.checkForUpdates()
        }
      }
      CommandGroup(replacing: .newItem) {}
      CommandGroup(before: .toolbar) {
        Button("Reload") { model.reload() }
          .keyboardShortcut("r")
        Toggle("Refresh the VM Screen", isOn: $model.liveScreen)
          .keyboardShortcut("l")
        Button("Show Activity Log in Finder") { Finder.reveal(model.logFile) }
        Divider()
      }
    }
  }
}
