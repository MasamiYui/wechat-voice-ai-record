import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case recording
    case importAudio
    case history
    case settings

    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .recording: return "Recording"
        case .importAudio: return "Import"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .recording: return "mic"
        case .importAudio: return "square.and.arrow.down"
        case .history: return "clock"
        case .settings: return "gear"
        }
    }
}

enum RecordingModeItem: String, Hashable, CaseIterable, Identifiable {
    case mixed
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .mixed: return "Mixed Mode"
        }
    }
    
    var description: String {
        switch self {
        case .mixed: return "Merges system and microphone audio automatically."
        }
    }
    
    var icon: String {
        switch self {
        case .mixed: return "arrow.triangle.merge"
        }
    }
}

enum ImportModeItem: String, Hashable, CaseIterable, Identifiable {
    case file
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .file: return "From File"
        }
    }
    
    var description: String {
        switch self {
        case .file: return "Import local audio files to create tasks."
        }
    }
    
    var icon: String {
        switch self {
        case .file: return "doc.badge.plus"
        }
    }
}

enum SettingsCategory: String, Hashable, CaseIterable, Identifiable {
    case general
    case cloud
    case storage
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .cloud: return "Cloud & AI"
        case .storage: return "Storage"
        }
    }
    
    var description: String {
        switch self {
        case .general: return "Basic settings including language and appearance."
        case .cloud: return "Configure cloud services and AI parameters."
        case .storage: return "Manage data persistence and database connections."
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .cloud: return "cloud"
        case .storage: return "externaldrive"
        }
    }
}
