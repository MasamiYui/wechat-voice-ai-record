# Audio Import Guide

## Purpose

This document explains how to import existing audio files into the application and process them using the same transcription and analysis pipeline as real-time recordings.

## Entry Point

Click the **"Import Audio"** button at the top of the application sidebar to open the import sheet.

## Import Modes

The application supports two import modes to accommodate different audio sources:

### 1. Meeting Mode

Suitable for single-file audio, such as:
- Pre-mixed meeting recordings
- Personal voice memos
- Phone recordings

**Workflow**:
1. Select **"Meeting Mode"** in the import sheet.
2. Click the file selection area (or drag and drop a file).
3. Select **one** audio file.
4. Click **"Import"**.

**Processing Logic**:
- The system treats this file as `mixed.m4a`.
- Creates a `Mixed` mode task.
- Subsequent pipeline: Transcode -> Upload to OSS -> Tingwu Transcription (diarization enabled).

### 2. Dictation Mode

Suitable for dual-track separated audio, such as:
- Files exported from professional dual-channel recording devices
- Previous "Separated Mode" recordings from this app (`*-local.m4a` and `*-remote.m4a`)

**Workflow**:
1. Select **"Dictation Mode"** in the import sheet.
2. Click the file selection areas for **"Speaker 1 (Local)"** and **"Speaker 2 (Remote)"** respectively.
3. Select the corresponding audio file for each track.
4. Ensure both files are selected.
5. Click **"Import"**.

**Processing Logic**:
- The system treats the two files as local and remote tracks respectively.
- Creates a `Separated` mode task.
- Subsequent pipeline: Upload separately to OSS -> Tingwu Dual-track Transcription -> Dialogue Alignment.

## Supported Formats

The application uses `AVFoundation` for processing and supports common audio formats compatible with macOS, including but not limited to:
- `.m4a`, `.mp3`, `.wav`, `.aac`

## Post-Import Workflow

After import, the task appears in the history list. You can manage it just like a real-time recording task:

1. **View Details**: Click the task to enter the details view.
2. **Execute Pipeline**: Click "Transcode" -> "Upload" -> "Analyze" to generate meeting notes.
3. **Playback**: You can play the imported audio (multi-track playback control is available in Separated Mode).
