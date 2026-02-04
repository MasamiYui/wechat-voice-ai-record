# Audio Import Guide

## Purpose

This document explains how to import existing audio files into the application and process them using the same transcription and analysis pipeline as real-time recordings.

## Entry Point

Click the **"Import Audio"** button at the top of the application sidebar to open the import sheet.

## File Import

The application supports importing single audio files for processing.

### Workflow

1. Select **"Import Audio"** in the sidebar.
2. Click the file selection area (or drag and drop a file).
3. Select **one** audio file.
4. Click **"Import"**.

### Processing Logic

- The system treats this file as `mixed.m4a`.
- Subsequent pipeline: Upload Raw -> Transcode -> Upload (Mixed) to OSS -> Create Tingwu task -> Poll and fetch results.

## Supported Formats

The application uses `AVFoundation` for processing and supports common audio formats compatible with macOS, including but not limited to:
- `.m4a`, `.mp3`, `.wav`, `.aac`

## Post-Import Workflow

After import, the task appears in the history list. You can manage it just like a real-time recording task:

1. **View Details**: Click the task to enter the details view.
2. **Execute Pipeline**: Click "Upload Raw" -> "Transcode" -> "Upload (Mixed)" -> "Create Task" -> "Poll" to fetch results.
3. **Playback**: You can play the imported audio.
