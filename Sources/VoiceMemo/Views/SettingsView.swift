import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var storageManager = StorageManager.shared
    @State private var akIdInput: String = ""
    @State private var akSecretInput: String = ""
    @State private var mysqlPasswordInput: String = ""
    @State private var testStatus: String = ""
    @State private var mysqlTestStatus: String = ""
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
            
            // MARK: - Storage
            Form {
                Section(header: Text("Storage Type")) {
                    Picker("Type", selection: $settings.storageType) {
                        Text("Local (SQLite)").tag(SettingsStore.StorageType.local)
                        Text("MySQL").tag(SettingsStore.StorageType.mysql)
                    }
                }
                
                if settings.storageType == .mysql {
                    Section(header: Text("MySQL Configuration")) {
                        TextField("Host", text: $settings.mysqlHost)
                        TextField("Port", value: $settings.mysqlPort, formatter: NumberFormatter())
                        TextField("User", text: $settings.mysqlUser)
                        TextField("Database", text: $settings.mysqlDatabase)
                        
                        if settings.hasMySQLPassword {
                            HStack {
                                Text("Password: ******")
                                Spacer()
                                Button("Clear") {
                                    settings.saveMySQLPassword("")
                                }
                            }
                        } else {
                            SecureField("Password", text: $mysqlPasswordInput)
                            Button("Save Password") {
                                settings.saveMySQLPassword(mysqlPasswordInput)
                                mysqlPasswordInput = ""
                            }
                            .disabled(mysqlPasswordInput.isEmpty)
                        }
                    }
                    
                    Section(header: Text("Actions")) {
                        Button("Test MySQL Connection") {
                            Task {
                                await testMySQL()
                            }
                        }
                        if !mysqlTestStatus.isEmpty {
                            Text(mysqlTestStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        Button("Sync Local to MySQL") {
                            Task {
                                await storageManager.syncToMySQL()
                            }
                        }
                        .disabled(storageManager.isSyncing)
                        
                        if storageManager.isSyncing {
                            ProgressView("Syncing...", value: storageManager.syncProgress, total: 1.0)
                        }
                        
                        if let err = storageManager.syncError {
                            Text("Sync Error: \(err)").foregroundColor(.red)
                        }
                    }
                } else {
                    Section(header: Text("MySQL")) {
                        Text("Switch to MySQL mode to configure connection and sync local history.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Go to MySQL Setup") {
                            settings.storageType = .mysql
                        }
                    }
                }
            }
            .tabItem { Text("Storage") }
        }
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
                
                TextEditor(text: .constant(logText.isEmpty ? "No logs found.\n\nTip: Enable 'Verbose Logging' in General settings to see more details." : logText))
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
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
    
    private func testMySQL() async {
        mysqlTestStatus = "Testing..."
        do {
            try await storageManager.testMySQLConnection()
            mysqlTestStatus = "Success! Connection established."
        } catch {
            mysqlTestStatus = "Failed: \(error.localizedDescription)"
        }
    }
}
