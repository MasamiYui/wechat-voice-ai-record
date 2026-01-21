import SwiftUI
import ScreenCaptureKit

struct RecordingView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var settings: SettingsStore
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("New Recording")
                    .font(.title)
                Spacer()
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
            
            // Mode Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Recognition Mode:")
                Picker("Recognition Mode", selection: $recorder.recordingMode) {
                    Text("Mixed (Default)").tag(MeetingMode.mixed)
                    Text("Dual-Speaker Separated").tag(MeetingMode.separated)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                // Description area with fixed height to prevent layout jumping
                ZStack(alignment: .topLeading) {
                    if recorder.recordingMode == .separated {
                        Text("Separated mode treats System Audio as Speaker 2 (Remote) and Microphone as Speaker 1 (Local). They will be recognized independently.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    } else {
                        Text("Mixed mode combines all audio sources into a single track for recognition. Suitable for general recordings and single-speaker scenarios.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    }
                }
                .frame(height: 35, alignment: .topLeading)
                .padding(.top, 2)
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
                Text("Latest Task Processing")
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
        .padding()
    }
}
