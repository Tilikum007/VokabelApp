import SwiftUI
import VokabelCore

@main
struct VokabelApp: App {
    @StateObject private var viewModel = TrainerViewModel(
        store: VocabularyStore(
            localFileName: "MASTER_vokabelheft_norwegisch.csv",
            driveFileID: "1JlZTzcUYnJAu3piX0oVCtxmoOI8Bcgy1"
        )
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.handleOpenURL(url)
                }
        }
    }
}
