import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var recorder: AudioRecorder
    
    @State private var isShowingSettings = false
    
    init(settings: SettingsStore) {
        self.settings = settings
        _recorder = StateObject(wrappedValue: AudioRecorder(settings: settings))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("WeChat Voice Recorder")
                    .font(.title)
                
                Spacer()
                
                Button(action: {
                    isShowingSettings = true
                }) {
                    Image(systemName: "gear")
                }
                .disabled(recorder.isRecording)
            }
            .padding(.top)
            .padding(.horizontal)
            
            // Status Area
            HStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)
                Text(recorder.statusMessage)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            
            // App Selection
            Picker("Select App to Record:", selection: $recorder.selectedApp) {
                Text("Select an App").tag(nil as SCRunningApplication?)
                ForEach(recorder.availableApps, id: \.processID) { app in
                    Text(app.applicationName).tag(app as SCRunningApplication?)
                }
            }
            .disabled(recorder.isRecording)
            .padding(.horizontal)
            
            HStack {
                Button("Refresh Apps") {
                    Task { await recorder.refreshAvailableApps() }
                }
                .disabled(recorder.isRecording)
                
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
            
            // Controls
            HStack(spacing: 20) {
                Button(action: {
                    recorder.startRecording()
                }) {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Start Recording")
                    }
                    .padding()
                }
                .disabled(recorder.isRecording || recorder.selectedApp == nil)
                .keyboardShortcut("R", modifiers: .command)
                
                Button(action: {
                    recorder.stopRecording()
                }) {
                    HStack {
                        Image(systemName: "stop.circle")
                        Text("Stop")
                    }
                    .padding()
                }
                .disabled(!recorder.isRecording)
                .keyboardShortcut(".", modifiers: .command)
            }
            
            // Pipeline View
            if let task = recorder.latestTask {
                Divider()
                Text("Latest Task")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                PipelineView(task: task, settings: settings)
                    .id(task.id) // Ensure view recreation on new task
            }
            
            Spacer()
            
            Text("Note: Requires Screen Recording Permission in System Settings")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom)
        }
        .frame(minWidth: 600, minHeight: 600) // Increased size for pipeline
        .padding()
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings)
        }
    }
}
