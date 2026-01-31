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
            .frame(maxWidth: Layout.containerWidth)
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
    
    // MARK: - Constants
    
    private enum Layout {
        static let labelWidth: CGFloat = 120
        static let containerWidth: CGFloat = 800
        static let standardPickerWidth: CGFloat = 200
        static let widePickerWidth: CGFloat = 240
        static let shortFieldWidth: CGFloat = 80
        static let standardSpacing: CGFloat = 20
        static let groupSpacing: CGFloat = 12
    }

    // MARK: - Helper Views
    
    private func FormRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: Layout.labelWidth, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
        }
    }
    
    private struct StyledGroupBox<Content: View>: View {
        let label: String
        let spacing: CGFloat
        let content: Content
        
        init(_ label: String, spacing: CGFloat = Layout.groupSpacing, @ViewBuilder content: () -> Content) {
            self.label = label
            self.spacing = spacing
            self.content = content()
        }
        
        var body: some View {
            GroupBox(label: Text(label).bold()) {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private struct CredentialRow: View {
        let hasValue: Bool
        @Binding var input: String
        let placeholder: String
        let isSecure: Bool
        var onSave: (() -> Void)? = nil
        let onClear: () -> Void
        
        var body: some View {
            if hasValue {
                HStack {
                    Text("******")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear", action: onClear)
                }
            } else {
                HStack {
                    if isSecure {
                        SecureField(placeholder, text: $input)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(placeholder, text: $input)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    if let onSave = onSave {
                        Button("Save") {
                            onSave()
                            input = ""
                        }
                        .disabled(input.isEmpty)
                    }
                }
            }
        }
    }
    
    // MARK: - Forms
    
    private var generalForm: some View {
        VStack(spacing: Layout.standardSpacing) {
            StyledGroupBox("Audio & Features", spacing: 16) {
                FormRow(label: "Language") {
                    Picker("", selection: $settings.language) {
                        Text("Chinese (cn)").tag("cn")
                        Text("Mixed (cn_en)").tag("cn_en")
                    }
                    .labelsHidden()
                    .frame(maxWidth: Layout.standardPickerWidth)
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
            }
            
            StyledGroupBox("AI Analysis") {
                FormRow(label: "Summary") {
                    Toggle("", isOn: $settings.enableSummary)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Spacer()
                }
                FormRow(label: "Key Points") {
                    Toggle("", isOn: $settings.enableKeyPoints)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Spacer()
                }
                FormRow(label: "Action Items") {
                    Toggle("", isOn: $settings.enableActionItems)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Spacer()
                }
            }

            StyledGroupBox("Appearance") {
                FormRow(label: "Theme") {
                    Picker("", selection: $settings.appTheme) {
                        Text("Auto").tag(SettingsStore.AppTheme.system)
                        Text("Light").tag(SettingsStore.AppTheme.light)
                        Text("Dark").tag(SettingsStore.AppTheme.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: Layout.widePickerWidth)
                    
                    Spacer()
                }
            }
            
            StyledGroupBox("Logs") {
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
        }
    }
    
    private var cloudForm: some View {
        VStack(spacing: Layout.standardSpacing) {
            StyledGroupBox("Tingwu Configuration") {
                FormRow(label: "AppKey") {
                    TextField("Required", text: $settings.tingwuAppKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            StyledGroupBox("OSS Configuration") {
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
            
            StyledGroupBox("Access Credentials (RAM)") {
                FormRow(label: "AccessKeyId") {
                    CredentialRow(
                        hasValue: settings.hasAccessKeyId,
                        input: $akIdInput,
                        placeholder: "Paste AccessKeyId",
                        isSecure: false,
                        onClear: { settings.clearSecrets() }
                    )
                }
                
                FormRow(label: "AccessKeySecret") {
                    CredentialRow(
                        hasValue: settings.hasAccessKeySecret,
                        input: $akSecretInput,
                        placeholder: "Paste AccessKeySecret",
                        isSecure: true,
                        onClear: { settings.clearSecrets() }
                    )
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
            
            StyledGroupBox("Connection Test") {
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
                        Spacer()
                    }
                }
            }
        }
    }
    
    private var storageForm: some View {
        VStack(spacing: Layout.standardSpacing) {
            StyledGroupBox("Storage Type") {
                FormRow(label: "Type") {
                    Picker("", selection: $settings.storageType) {
                        Text("Local (SQLite)").tag(SettingsStore.StorageType.local)
                        Text("MySQL").tag(SettingsStore.StorageType.mysql)
                    }
                    .labelsHidden()
                    .frame(maxWidth: Layout.standardPickerWidth)
                    
                    Spacer()
                }
            }
            
            if settings.storageType == .mysql {
                StyledGroupBox("MySQL Configuration") {
                    FormRow(label: "Host") {
                        TextField("127.0.0.1", text: $settings.mysqlHost)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "Port") {
                        TextField("3306", value: $settings.mysqlPort, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: Layout.shortFieldWidth)
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
                        CredentialRow(
                            hasValue: settings.hasMySQLPassword,
                            input: $mysqlPasswordInput,
                            placeholder: "Password",
                            isSecure: true,
                            onSave: { settings.saveMySQLPassword(mysqlPasswordInput) },
                            onClear: { settings.saveMySQLPassword("") }
                        )
                    }
                }
                
                StyledGroupBox("Actions") {
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
