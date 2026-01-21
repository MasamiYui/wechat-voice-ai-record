import SwiftUI
import ScreenCaptureKit

struct RecordingView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var settings: SettingsStore
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header & Status
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("New Recording")
                            .font(.system(size: 28, weight: .bold))
                        
                        Spacer()
                        
                        // Compact Status Indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(recorder.isRecording ? Color.red : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(recorder.statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                // Configuration Card
                VStack(spacing: 24) {
                    // App Selection Row
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "app.badge")
                                .foregroundColor(.accentColor)
                            Text("Target Application")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                Task { await recorder.refreshAvailableApps() }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .help("Refresh App List")
                            .disabled(recorder.isRecording)
                        }
                        
                        Picker("Select App to Record:", selection: $recorder.selectedApp) {
                            Text("Select an App").tag(nil as SCRunningApplication?)
                            ForEach(recorder.availableApps, id: \.processID) { app in
                                Text(app.applicationName).tag(app as SCRunningApplication?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300) // Fixed max width for better alignment
                    }
                    
                    Divider()

                    // Mode Selection Row
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "waveform.and.mic")
                                .foregroundColor(.accentColor)
                            Text("Recognition Mode")
                                .font(.headline)
                        }
                        
                        Picker("Recognition Mode", selection: $recorder.recordingMode) {
                            Text("Mixed (Default)").tag(MeetingMode.mixed)
                            Text("Dual-Speaker Separated").tag(MeetingMode.separated)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 400) // Consistent width
                        
                        // Description area
                        ZStack(alignment: .topLeading) {
                            if recorder.recordingMode == .separated {
                                Text("Separated mode treats System Audio as Speaker 2 (Remote) and Microphone as Speaker 1 (Local). They will be recognized independently.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity)
                            } else {
                                Text("Mixed mode combines all audio sources into a single track for recognition. Suitable for general recordings.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity)
                            }
                        }
                        .frame(minHeight: 32, alignment: .topLeading)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
                .disabled(recorder.isRecording)

                // Action Controls - Centered and compact
                HStack {
                    Spacer()
                    if !recorder.isRecording {
                        Button(action: {
                            recorder.startRecording()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "record.circle.fill")
                                Text("Record")
                                    .fontWeight(.semibold)
                            }
                            .frame(width: 120)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(recorder.selectedApp == nil)
                        .keyboardShortcut("R", modifiers: .command)
                    } else {
                        Button(action: {
                            recorder.stopRecording()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop")
                                    .fontWeight(.semibold)
                            }
                            .frame(width: 120)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                        .keyboardShortcut(".", modifiers: .command)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

                // Latest Task Pipeline Section
                if let task = recorder.latestTask {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Latest Task Processing")
                                .font(.headline)
                            Spacer()
                            StatusBadge(status: task.status)
                        }
                        .padding(.horizontal)
                        
                        PipelineView(task: task, settings: settings)
                            .id(task.id)
                            .padding(.bottom)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer(minLength: 20)
            }
            .animation(.default, value: recorder.isRecording)
            .animation(.default, value: recorder.recordingMode)
            .animation(.default, value: recorder.latestTask?.id)
        }
    }
}
