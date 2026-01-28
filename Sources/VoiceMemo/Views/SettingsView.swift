import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var storageManager = StorageManager.shared
    var category: SettingsCategory?
    
    @State private var akIdInput: String = ""
    @State private var akSecretInput: String = ""
    @State private var mysqlPasswordInput: String = ""
    @State private var testStatus: String = ""
    @State private var mysqlTestStatus: String = ""
    @State private var showingLog = false
    @State private var logText = ""
    
    init(settings: SettingsStore, category: SettingsCategory? = nil) {
        self.settings = settings
        self.category = category
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let category = category {
                    switch category {
                    case .general:
                        generalForm
                    case .cloud:
                        cloudForm
                    case .storage:
                        storageForm
                    }
                } else {
                    TabView {
                        generalForm.tabItem { Text("General") }
                        cloudForm.tabItem { Text("Cloud") }
                        storageForm.tabItem { Text("Storage") }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity, alignment: .top)
        }
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
                
                Button("Close") {
                    showingLog = false
                }
                .padding()
            }
            .frame(width: 700, height: 500)
        }
    }
    
    // MARK: - Helper Views
    
    private func FormRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
        }
    }
    
    private struct ToggleRow: View {
        let icon: String
        let title: String
        @Binding var isOn: Bool
        
        var body: some View {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.blue)
                Text(title)
                Spacer()
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
    }
    
    // MARK: - Forms
    
    private var generalForm: some View {
        VStack(spacing: 20) {
            GroupBox(label: Text("Audio & Features").bold()) {
                VStack(spacing: 16) {
                    FormRow(label: "Language") {
                        Picker("", selection: $settings.language) {
                            Text("Chinese (cn)").tag("cn")
                            Text("Mixed (cn_en)").tag("cn_en")
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    
                    Divider()
                    
                    FormRow(label: "Role Split") {
                        Toggle("Enable Role Split", isOn: $settings.enableRoleSplit)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Text("Distinguish speakers in audio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                    
                    Divider()
                    
                    // AI Features Group
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Analysis")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.leading, 120) // Align with form content
                        
                        VStack(spacing: 0) {
                            ToggleRow(icon: "doc.text", title: "Summary", isOn: $settings.enableSummary)
                            Divider().padding(.leading, 44)
                            ToggleRow(icon: "list.bullet.rectangle", title: "Key Points", isOn: $settings.enableKeyPoints)
                            Divider().padding(.leading, 44)
                            ToggleRow(icon: "checkmark.square", title: "Action Items", isOn: $settings.enableActionItems)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.leading, 120) // Align with form content
                    }
                }
                .padding(8)
            }
            
            GroupBox(label: Text("Logs").bold()) {
                VStack(spacing: 12) {
                    FormRow(label: "Settings") {
                        Toggle("Verbose Logging", isOn: $settings.enableVerboseLogging)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Text("Enable detailed debug logs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                    
                    Divider()
                    
                    FormRow(label: "Path") {
                        Text(settings.logFileURL().path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    FormRow(label: "Actions") {
                        HStack {
                            Button("Show Log") {
                                logText = settings.readLogText()
                                showingLog = true
                            }
                            Button("Open Folder") {
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
                .padding(8)
            }
        }
    }
    
    private var cloudForm: some View {
        VStack(spacing: 20) {
            GroupBox(label: Text("Tingwu Configuration").bold()) {
                VStack(spacing: 12) {
                    FormRow(label: "AppKey") {
                        TextField("Required", text: $settings.tingwuAppKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }
            
            GroupBox(label: Text("OSS Configuration").bold()) {
                VStack(spacing: 12) {
                    FormRow(label: "Region") {
                        TextField("e.g. cn-beijing", text: $settings.ossRegion)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "Endpoint") {
                        TextField("e.g. oss-cn-beijing.aliyuncs.com", text: $settings.ossEndpoint)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "Bucket") {
                        TextField("Bucket Name", text: $settings.ossBucket)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "Prefix") {
                        TextField("Path Prefix (e.g. voice/)", text: $settings.ossPrefix)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }
            
            GroupBox(label: Text("Access Credentials (RAM)").bold()) {
                VStack(spacing: 12) {
                    FormRow(label: "AccessKeyId") {
                        if settings.hasAccessKeyId {
                            HStack {
                                Text("******")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Clear") { settings.clearSecrets() }
                            }
                        } else {
                            TextField("Paste AccessKeyId", text: $akIdInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    FormRow(label: "AccessKeySecret") {
                        if settings.hasAccessKeySecret {
                            HStack {
                                Text("******")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Clear") { settings.clearSecrets() }
                            }
                        } else {
                            SecureField("Paste AccessKeySecret", text: $akSecretInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    if !settings.hasAccessKeyId || !settings.hasAccessKeySecret {
                        HStack {
                            Spacer()
                            Button("Save Credentials") {
                                if !akIdInput.isEmpty { settings.saveAccessKeyId(akIdInput) }
                                if !akSecretInput.isEmpty { settings.saveAccessKeySecret(akSecretInput) }
                                akIdInput = ""
                                akSecretInput = ""
                            }
                            .disabled(akIdInput.isEmpty || akSecretInput.isEmpty)
                        }
                    }
                }
                .padding(8)
            }
            
            GroupBox(label: Text("Connection Test").bold()) {
                VStack(spacing: 12) {
                    FormRow(label: "OSS Upload") {
                        HStack {
                            Button("Test Upload") {
                                Task { await testUpload() }
                            }
                            if !testStatus.isEmpty {
                                Text(testStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }
    
    private var storageForm: some View {
        VStack(spacing: 20) {
            GroupBox(label: Text("Storage Type").bold()) {
                VStack(spacing: 12) {
                    FormRow(label: "Type") {
                        Picker("", selection: $settings.storageType) {
                            Text("Local (SQLite)").tag(SettingsStore.StorageType.local)
                            Text("MySQL").tag(SettingsStore.StorageType.mysql)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                }
                .padding(8)
            }
            
            if settings.storageType == .mysql {
                GroupBox(label: Text("MySQL Configuration").bold()) {
                    VStack(spacing: 12) {
                        FormRow(label: "Host") {
                            TextField("127.0.0.1", text: $settings.mysqlHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        FormRow(label: "Port") {
                            TextField("3306", value: $settings.mysqlPort, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        FormRow(label: "User") {
                            TextField("Username", text: $settings.mysqlUser)
                                .textFieldStyle(.roundedBorder)
                        }
                        FormRow(label: "Database") {
                            TextField("Database Name", text: $settings.mysqlDatabase)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        FormRow(label: "Password") {
                            if settings.hasMySQLPassword {
                                HStack {
                                    Text("******")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Clear") { settings.saveMySQLPassword("") }
                                }
                            } else {
                                HStack {
                                    SecureField("Password", text: $mysqlPasswordInput)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Save") {
                                        settings.saveMySQLPassword(mysqlPasswordInput)
                                        mysqlPasswordInput = ""
                                    }
                                    .disabled(mysqlPasswordInput.isEmpty)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                
                GroupBox(label: Text("Actions").bold()) {
                    VStack(spacing: 12) {
                        FormRow(label: "Connection") {
                            HStack {
                                Button("Test Connection") {
                                    Task { await testMySQL() }
                                }
                                if !mysqlTestStatus.isEmpty {
                                    Text(mysqlTestStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Divider()
                        
                        FormRow(label: "Sync") {
                            HStack {
                                Button("Sync Local to MySQL") {
                                    Task { await storageManager.syncToMySQL() }
                                }
                                .disabled(storageManager.isSyncing)
                                
                                if storageManager.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                }
                            }
                        }
                        
                        if let err = storageManager.syncError {
                            FormRow(label: "Error") {
                                Text(err)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(8)
                }
            } else {
                GroupBox {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Switch to MySQL mode to configure connection and sync local history.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Setup MySQL") {
                            settings.storageType = .mysql
                        }
                    }
                    .padding(8)
                }
            }
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
