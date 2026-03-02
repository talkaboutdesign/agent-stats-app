import SwiftData
import SwiftUI

@main
struct Agent_StatsApp: App {
    private let modelContainer: ModelContainer
    @State private var model: AppModel

    init() {
        do {
            modelContainer = try ModelContainer(
                for: CachedSnapshotRecord.self,
                CachedSessionFileRecord.self
            )
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }

        let context = ModelContext(modelContainer)
        let snapshotStore = SwiftDataSnapshotStore(modelContext: context)
        _model = State(initialValue: AppModel(snapshotStore: snapshotStore))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .modelContainer(modelContainer)
    }
}
