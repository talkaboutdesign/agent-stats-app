import SwiftUI

@main
struct Agent_StatsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
