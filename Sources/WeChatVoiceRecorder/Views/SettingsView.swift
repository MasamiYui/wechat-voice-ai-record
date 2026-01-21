import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var akIdInput: String = ""
    @State private var akSecretInput: String = ""
    @State private var testStatus: String = ""
    @State private var showingLog = false
    @State private var logText = ""
    
    var body: some View {
        TabView {
            // MARK: - General
            Form {
                Section(header: Text("Audio & Features")) {
                    Picker("Language", selection: $settings.language) {
                        Text("Chinese (cn)").tag("cn")
                        Text("Mixed (cn_en)").tag("cn_en")
                    }
                    
                    Toggle("Enable Summary", isOn: $settings.enableSummary)
                    Toggle("Enable Key Points", isOn: $settings.enableKeyPoints)
                    Toggle("Enable Action Items", isOn: $settings.enableActionItems)
                    Toggle("Enable Role Split", isOn: $settings.enableRoleSplit)
                    Toggle("Enable Verbose Logging", isOn: $settings.enableVerboseLogging)
                }
                
                Section(header: Text("Logs")) {
                    Text(settings.logFileURL().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Show Log") {
                            logText = settings.readLogText()
                            showingLog = true
                        }
                        Button("Open Log Folder") {
                            let url = settings.logFileURL().deletingLastPathComponent()
                            NSWorkspace.shared.open(url)
                        }
                        Button("Clear Log") {
                            settings.clearLogFile()
                            logText = ""
                        }
                    }
                }
            }
            .tabItem { Text("General") }
            
            // MARK: - Cloud
            Form {
                Section(header: Text("Tingwu Configuration")) {
                    TextField("AppKey", text: $settings.tingwuAppKey)
                }
                
                Section(header: Text("OSS Configuration")) {
                    TextField("Region", text: $settings.ossRegion)
                    TextField("Endpoint", text: $settings.ossEndpoint)
                    TextField("Bucket", text: $settings.ossBucket)
                    TextField("Prefix", text: $settings.ossPrefix)
                }
                
                Section(header: Text("Access Credentials (RAM)")) {
                    if settings.hasAccessKeyId {
                        HStack {
                            Text("AccessKeyId: ******")
                            Spacer()
                            Button("Clear") {
                                settings.clearSecrets()
                            }
                        }
                    } else {
                        TextField("AccessKeyId", text: $akIdInput)
                    }
                    
                    if settings.hasAccessKeySecret {
                        HStack {
                            Text("AccessKeySecret: ******")
                            Spacer()
                            Button("Clear") {
                                settings.clearSecrets()
                            }
                        }
                    } else {
                        SecureField("AccessKeySecret", text: $akSecretInput)
                    }
                    
                    if !settings.hasAccessKeyId || !settings.hasAccessKeySecret {
                        Button("Save Credentials") {
                            if !akIdInput.isEmpty { settings.saveAccessKeyId(akIdInput) }
                            if !akSecretInput.isEmpty { settings.saveAccessKeySecret(akSecretInput) }
                            akIdInput = ""
                            akSecretInput = ""
                        }
                        .disabled(akIdInput.isEmpty || akSecretInput.isEmpty)
                    }
                }
                
                Section(header: Text("Connection Test")) {
                    Button("Test OSS Upload") {
                        Task {
                            await testUpload()
                        }
                    }
                    if !testStatus.isEmpty {
                        Text(testStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tabItem { Text("Cloud") }
        }
        .frame(width: 500, height: 400)
        .padding()
        .sheet(isPresented: $showingLog) {
            VStack {
                HStack {
                    Text("Verbose Log")
                        .font(.headline)
                    Spacer()
                    Button("Refresh") {
                        logText = settings.readLogText()
                    }
                }
                .padding()
                
                TextEditor(text: $logText)
                    .font(.body)
                    .padding()
            }
            .frame(width: 700, height: 500)
        }
    }
    
    private func testUpload() async {
        testStatus = "Testing..."
        settings.log("OSS test upload start")
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_oss.txt")
        do {
            try "Connection Test".write(to: tempFile, atomically: true, encoding: .utf8)
            let service = OSSService(settings: settings)
            let key = "\(settings.ossPrefix)test/connection_test.txt"
            let url = try await service.uploadFile(fileURL: tempFile, objectKey: key)
            testStatus = "Success! URL: \(url)"
            settings.log("OSS test upload success: url=\(url)")
        } catch {
            testStatus = "Failed: \(String(describing: error))"
            settings.log("OSS test upload failed: \(String(describing: error))")
        }
    }
}
