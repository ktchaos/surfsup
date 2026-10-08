import ComposableArchitecture
import SwiftUI

@main
struct SurfsUpApp: App {
    private let store = Store(initialState: AnalyzePoseFeature.State()) {
        AnalyzePoseFeature()
    }

    var body: some Scene {
        WindowGroup {
            AnalyzePoseView(store: store)
        }
    }
}
