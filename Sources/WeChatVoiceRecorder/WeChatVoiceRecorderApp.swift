import SwiftUI

@main
struct WeChatVoiceRecorderApp: App {
    @StateObject private var settings = SettingsStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
        }
    }
}
