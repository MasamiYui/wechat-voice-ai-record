import SwiftUI
import ScreenCaptureKit

struct RecordingView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var settings: SettingsStore
    var showModeSelection: Bool = true
    var onViewResult: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header & Status
            HStack(alignment: .center) {
                Text("New Recording")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Status Text
                HStack(spacing: 6) {
                    Circle()
                        .fill(recorder.isRecording ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(recorder.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(spacing: 40) {
                    // Configuration Card
                    VStack(spacing: 0) {
                        // Target Application Section
                    HStack {
                        Text("Target Application")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Menu {
                                Button("Select an App") {
                                    recorder.selectedApp = nil
                                }
                                
                                ForEach(recorder.availableApps, id: \.processID) { app in
                                    Button(app.applicationName) {
                                        recorder.selectedApp = app
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(recorder.selectedApp?.applicationName ?? "Select an App")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .frame(width: 240)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                Task { await recorder.refreshAvailableApps() }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh App List")
                            .disabled(recorder.isRecording)
                        }
                    }
                    .padding(24)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Recognition Mode Section
                    if showModeSelection {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                Text("Recognition Mode")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Recognition Mode", selection: $recorder.recordingMode) {
                                    Text("Mixed (Default)").tag(MeetingMode.mixed)
                                    Text("Dual-Speaker Separated").tag(MeetingMode.separated)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                
                                Group {
                                    if recorder.recordingMode == .separated {
                                        Text("Separated mode treats System Audio as Speaker 2 (Remote) and Microphone as Speaker 1 (Local). They will be recognized independently.")
                                    } else {
                                        Text("Mixed mode combines all audio sources into a single track for recognition. Suitable for general recordings.")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(24)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor)) // White in light mode
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
                .frame(maxWidth: 600)
                .padding(.horizontal, 24)
                .disabled(recorder.isRecording)

                // Action Button
                if !recorder.isRecording {
                    Button(action: {
                        recorder.startRecording()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "record.circle")
                                .font(.title2)
                            Text("Record")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 60)
                        .background(
                            Capsule()
                                .fill(Color.red)
                                .shadow(color: Color.red.opacity(0.3), radius: 5, x: 0, y: 3)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(recorder.selectedApp == nil)
                    .keyboardShortcut("R", modifiers: .command)
                } else {
                    Button(action: {
                        recorder.stopRecording()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                            Text("Stop Recording")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 40)
                        .background(
                            Capsule()
                                .fill(Color.primary)
                                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(".", modifiers: .command)
                }

                // Latest Task Pipeline Section
                if let task = recorder.latestTask {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Latest Task Processing")
                                .font(.headline)
                            Spacer()
                            StatusBadge(status: task.status)
                        }
                        
                        PipelineView(task: task, settings: settings, onViewResult: onViewResult)
                            .id(task.id)
                            .padding(16)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .frame(maxWidth: 800)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer(minLength: 40)
            }
            .padding(.top, 24)
            .animation(.default, value: recorder.isRecording)
            .animation(.default, value: recorder.recordingMode)
            .animation(.default, value: recorder.latestTask?.id)
        }
        }
        .background(Color(nsColor: .windowBackgroundColor)) // Light gray background
    }
}
