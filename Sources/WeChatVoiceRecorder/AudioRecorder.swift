import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit

@available(macOS 13.0, *)
class AudioRecorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var isRecording = false
    @Published var statusMessage = "Ready to record"
    @Published var availableApps: [SCRunningApplication] = []
    @Published var selectedApp: SCRunningApplication?
    @Published var latestTask: MeetingTask?
    
    var lastUploadedURL: URL? {
        if let urlStr = latestTask?.ossUrl {
            return URL(string: urlStr)
        }
        return nil
    }
    
    private var settings: SettingsStore
    private var recordingId: String?
    
    // System Audio (Remote)
    private var stream: SCStream?
    private var remoteAssetWriter: AVAssetWriter?
    private var remoteAssetWriterInput: AVAssetWriterInput?
    private let remoteQueue = DispatchQueue(label: "com.wechatvoicerecorder.remote")
    private var isFirstRemoteBuffer = true
    private var remoteURL: URL?
    
    // Microphone Audio (Local)
    private var micSession: AVCaptureSession?
    private var micAssetWriter: AVAssetWriter?
    private var micAssetWriterInput: AVAssetWriterInput?
    private let micQueue = DispatchQueue(label: "com.wechatvoicerecorder.mic")
    private var isFirstMicBuffer = true
    private var localURL: URL?
    
    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        Task {
            await refreshAvailableApps()
        }
    }
    
    @MainActor
    func refreshAvailableApps() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            self.availableApps = content.applications.sorted { $0.applicationName < $1.applicationName }
            
            if let wechat = self.availableApps.first(where: { $0.applicationName.lowercased().contains("wechat") || $0.applicationName.contains("微信") }) {
                self.selectedApp = wechat
                self.statusMessage = "Auto-selected: \(wechat.applicationName)"
            }
        } catch {
            self.statusMessage = "Failed to load apps: \(error.localizedDescription)"
        }
    }
    
    func startRecording() {
        guard let app = selectedApp else {
            statusMessage = "Please select an app first"
            return
        }
        
        statusMessage = "Requesting permissions..."
        settings.log("Start recording: app=\(app.applicationName)")
        
        // Request Mic Permission first
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.beginRecordingSession(app: app)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    DispatchQueue.main.async { self.beginRecordingSession(app: app) }
                } else {
                    DispatchQueue.main.async { self.statusMessage = "Microphone permission denied" }
                }
            }
        case .denied, .restricted:
            statusMessage = "Microphone permission denied"
            return
        @unknown default:
            return
        }
    }
    
    private func beginRecordingSession(app: SCRunningApplication) {
        isFirstRemoteBuffer = true
        isFirstMicBuffer = true
        
        // Generate URLs
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let dateStr = formatter.string(from: Date())
        
        // Create Recording ID (Timestamp + Random)
        let uuid = UUID().uuidString.prefix(8)
        self.recordingId = "\(dateStr)-\(uuid)"
        
        let fileManager = FileManager.default
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let folder = downloads.appendingPathComponent("WeChatRecordings")
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        
        self.remoteURL = folder.appendingPathComponent("recording-\(dateStr)-remote.m4a")
        self.localURL = folder.appendingPathComponent("recording-\(dateStr)-local.m4a")
        if let recordingId, let remoteURL, let localURL {
            settings.log("Recording session: id=\(recordingId) remote=\(remoteURL.path) local=\(localURL.path)")
        }
        
        // Start System Audio Capture (SCK)
        startSystemAudioCapture(app: app)
        
        // Start Microphone Capture (AVCapture)
        startMicrophoneCapture()
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.statusMessage = "Recording (Remote + Local)..."
        }
    }
    
    // MARK: - System Audio (SCK)
    
    private func startSystemAudioCapture(app: SCRunningApplication) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let matchedApp = content.applications.first(where: { $0.processID == app.processID }) else { return }
                
                let filter = SCContentFilter(display: content.displays.first!, including: [matchedApp], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.sampleRate = 48000
                config.channelCount = 2
                config.excludesCurrentProcessAudio = true
                config.width = 2
                config.height = 2
                
                stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: remoteQueue)
                try await stream?.startCapture()
            } catch {
                settings.log("SCK start error: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupRemoteWriter(for sampleBuffer: CMSampleBuffer) {
        guard let url = remoteURL,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            
            remoteAssetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)
            
            let sampleRate = streamDesc.pointee.mSampleRate
            let channels = Int(streamDesc.pointee.mChannelsPerFrame)
            
            self.settings.log("Setup remote writer: rate=\(sampleRate), channels=\(channels)")
            
            if sampleRate <= 0 || channels <= 0 {
                self.settings.log("Invalid audio format: rate or channels is 0")
                return
            }

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128000
            ]
            
            remoteAssetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: formatDesc)
            remoteAssetWriterInput?.expectsMediaDataInRealTime = true
            
            if let writer = remoteAssetWriter, let input = remoteAssetWriterInput, writer.canAdd(input) {
                writer.add(input)
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.settings.log("Remote writer started successfully")
            }
        } catch {
            settings.log("Remote writer error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Microphone Audio (AVCapture)
    
    private func startMicrophoneCapture() {
        micQueue.async {
            self.micSession = AVCaptureSession()
            guard let session = self.micSession else { return }
            
            session.beginConfiguration()
            guard let micDevice = AVCaptureDevice.default(for: .audio),
                  let micInput = try? AVCaptureDeviceInput(device: micDevice),
                  session.canAddInput(micInput) else {
                self.settings.log("Cannot add mic input")
                return
            }
            session.addInput(micInput)
            
            let output = AVCaptureAudioDataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: self.micQueue)
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }
    
    private func setupMicWriter(for sampleBuffer: CMSampleBuffer) {
        guard let url = localURL,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            
            micAssetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)
            
            let sampleRate = streamDesc.pointee.mSampleRate
            let channels = Int(streamDesc.pointee.mChannelsPerFrame)
            
            self.settings.log("Setup mic writer: rate=\(sampleRate), channels=\(channels)")
            
            if sampleRate <= 0 || channels <= 0 {
                self.settings.log("Invalid mic audio format: rate or channels is 0")
                return
            }

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128000
            ]
            
            micAssetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: formatDesc)
            micAssetWriterInput?.expectsMediaDataInRealTime = true
            
            if let writer = micAssetWriter, let input = micAssetWriterInput, writer.canAdd(input) {
                writer.add(input)
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.settings.log("Mic writer started successfully")
            }
        } catch {
            settings.log("Mic writer error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Stop & Merge
    
    func stopRecording() {
        Task {
            settings.log("Stop recording")
            // 1. Stop System Audio
            try? await stream?.stopCapture()
            stream = nil
            if let writer = remoteAssetWriter {
                if writer.status == .writing {
                    remoteAssetWriterInput?.markAsFinished()
                    await writer.finishWriting()
                    settings.log("Remote writer finished. Final status: \(writer.status.rawValue)")
                } else {
                    settings.log("Remote writer was not writing. Status: \(writer.status.rawValue), Error: \(String(describing: writer.error))")
                }
            }
            
            // 2. Stop Microphone
            micSession?.stopRunning()
            micSession = nil
            if let writer = micAssetWriter {
                if writer.status == .writing {
                    micAssetWriterInput?.markAsFinished()
                    await writer.finishWriting()
                    settings.log("Mic writer finished. Final status: \(writer.status.rawValue)")
                } else {
                    settings.log("Mic writer was not writing. Status: \(writer.status.rawValue), Error: \(String(describing: writer.error))")
                }
            }
            
            // 3. Merge
            if let rURL = remoteURL, let lURL = localURL, let recId = recordingId {
                settings.log("Merge start: remote=\(rURL.path) local=\(lURL.path)")
                await MainActor.run { self.statusMessage = "Merging audio files..." }
                let mixedURL = rURL.deletingLastPathComponent().appendingPathComponent(rURL.lastPathComponent.replacingOccurrences(of: "remote", with: "mixed"))
                do {
                    try await mergeAudioFiles(audio1: rURL, audio2: lURL, output: mixedURL)
                    await MainActor.run {
                        self.isRecording = false
                        self.statusMessage = "Saved 3 files to Downloads/WeChatRecordings"
                        
                        // Create Meeting Task
                        let title = "Meeting \(recId)"
                        let task = MeetingTask(recordingId: recId, localFilePath: mixedURL.path, title: title)
                        DatabaseManager.shared.saveTask(task)
                        self.latestTask = task
                    }
                    settings.log("Merge success: mixed=\(mixedURL.path)")
                } catch {
                    await MainActor.run {
                        self.isRecording = false
                        self.statusMessage = "Merge failed: \(error.localizedDescription)"
                    }
                    settings.log("Merge failed: \(error.localizedDescription)")
                }
            }
            
            // Cleanup
            remoteAssetWriter = nil
            remoteAssetWriterInput = nil
            micAssetWriter = nil
            micAssetWriterInput = nil
        }
    }
    
    private func mergeAudioFiles(audio1: URL, audio2: URL, output: URL) async throws {
        let composition = AVMutableComposition()
        
        let asset1 = AVURLAsset(url: audio1)
        let asset2 = AVURLAsset(url: audio2)
        
        var hasTrack1 = false
        var hasTrack2 = false
        
        do {
            if let tracks1 = try? await asset1.loadTracks(withMediaType: .audio), let sourceTrack1 = tracks1.first {
                let track1 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                let duration = try await asset1.load(.duration)
                try track1?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack1, at: .zero)
                hasTrack1 = true
            }
        } catch {
            settings.log("Warning: Could not load track 1: \(error.localizedDescription)")
        }
        
        do {
            if let tracks2 = try? await asset2.loadTracks(withMediaType: .audio), let sourceTrack2 = tracks2.first {
                let track2 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                let duration = try await asset2.load(.duration)
                try track2?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack2, at: .zero)
                hasTrack2 = true
            }
        } catch {
            settings.log("Warning: Could not load track 2: \(error.localizedDescription)")
        }
        
        guard hasTrack1 || hasTrack2 else {
            throw NSError(domain: "AudioRecorder", code: 404, userInfo: [NSLocalizedDescriptionKey: "No valid audio tracks found to merge"])
        }
        
        if FileManager.default.fileExists(atPath: output.path) {
            try? FileManager.default.removeItem(at: output)
        }
        
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "AudioRecorder", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        export.outputURL = output
        export.outputFileType = .m4a
        await export.export()
        
        if let error = export.error {
            throw error
        }
    }
    
    // MARK: - Delegates
    
    // SCStreamDelegate
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        if isFirstRemoteBuffer {
            setupRemoteWriter(for: sampleBuffer)
            isFirstRemoteBuffer = false
        }
        if let input = remoteAssetWriterInput, input.isReadyForMoreMediaData {
            if !input.append(sampleBuffer) {
                settings.log("Remote append error: \(String(describing: remoteAssetWriter?.error))")
            }
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        settings.log("SCStream error: \(error.localizedDescription)")
    }
    
    // AVCaptureAudioDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        if isFirstMicBuffer {
            setupMicWriter(for: sampleBuffer)
            isFirstMicBuffer = false
        }
        if let input = micAssetWriterInput, input.isReadyForMoreMediaData {
            if !input.append(sampleBuffer) {
                settings.log("Mic append error: \(String(describing: micAssetWriter?.error))")
            }
        }
    }
}
