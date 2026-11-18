import SwiftUI

@main
struct MorrowWatchApp: App {
    @StateObject private var connection = WatchConnection()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(connection)
        }
    }
}
