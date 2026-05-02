import SwiftUI

@main
struct IGDMClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
                .onAppear {
                    appDelegate.model = model
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Instagram") {
                Button("Refresh") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Session") {
                    model.showSessionEditor = true
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Sign Out") {
                    model.signOut()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
