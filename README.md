# AI-Based Industrial Problem Prediction

This project uses Flutter to build an AI-powered application for industrial problem prediction using audio recordings. The app processes audio files, extracts features, runs predictions using a TensorFlow Lite model, and displays the results.

## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Logic and Steps](#logic-and-steps)
- [Packages Used](#packages-used)
- [Permissions](#permissions)
- [Project Structure](#project-structure)

## Features
- **Audio Recording**: Record audio directly within the app.
- **File Selection**: Choose audio files from storage.
- **Audio Processing**: Segment audio into chunks and extract Mel spectrogram features.
- **AI Predictions**: Use a TensorFlow Lite model for classification.
- **Dynamic Labeling**: Automatically label predictions and determine the most frequent label.

## Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/amine04bk/Prediction_industrial_Problem_with_AI.git
   cd Prediction_industrial_Problem_with_AI
   ```

2. **Install Flutter Dependencies**:
   Ensure Flutter is installed on your system, then run:
   ```bash
   flutter pub get
   ```

3. **Add Required Assets**:
   Ensure the following files exist in the `assets` directory:
   - `model.tflite`: TensorFlow Lite model file.
   - `labels.txt`: Text file containing label mappings.

4. **Run the App**:
   Connect a device or start an emulator, then run:
   ```bash
   flutter run
   ```

## Usage

1. Launch the app.
2. Tap the microphone icon to start recording or use the "+" button to select an audio file.
3. Tap "Make Prediction" to process the audio and get predictions.
4. View results, including the predicted labels and the most frequent label.

## Logic and Steps

### Audio Recording and File Handling
- **Recording**: Uses `flutter_sound` to record audio in WAV format.
- **File Selection**: Allows users to pick audio files using `file_picker`.

### Audio Processing
1. **Chunking**: The audio is divided into 2-second segments using FFmpeg.
2. **Feature Extraction**: Converts PCM data to Mel spectrogram features.
3. **Normalization**: Scales features to a fixed range and pads/truncates to 10,000 features.

### Model Inference
1. **Quantization**: Converts features to integers suitable for TensorFlow Lite.
2. **Inference**: Runs predictions using the TensorFlow Lite model.
3. **Labeling**: Matches predictions to labels from `labels.txt` or predefined rules.
4. **Final Output**: Determines the most frequent label across all chunks.

### UI Updates
- Real-time progress display during chunk processing.
- Shows predicted labels and the final most frequent label.

## Packages Used

| Package               | Version  | Purpose                                        |
|-----------------------|----------|------------------------------------------------|
| `flutter_sound`       | ^9.17.0  | Audio recording                                |
| `file_picker`         | ^8.1.4   | File selection                                |
| `ffmpeg_kit_flutter`  | ^6.0.3   | Audio processing                               |
| `path_provider`       | ^2.1.5   | Accessing device storage                      |
| `permission_handler`  | ^11.3.1  | Requesting runtime permissions                |
| `tflite_flutter`      | ^0.11.0  | TensorFlow Lite inference                     |
| `shared_preferences`  | ^2.3.3   | Persistent storage for app settings           |
| `scidart`             | ^0.0.2   | Scientific computations for FFT and filters   |

## Permissions

The app requests the following permissions:
- **Microphone**: For recording audio.
- **Storage**: For accessing audio files and saving processed data.
  
### Android
Ensure these permissions are added to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
```

### iOS
Add these keys to `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>App needs access to the microphone for recording.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>App needs access to the photo library to pick audio files.</string>
```

## Project Structure

```
├── lib
│   ├── main.dart          # Main entry point
├── assets
│   ├── model.tflite       # TensorFlow Lite model
│   ├── labels.txt         # Labels for classification
├── pubspec.yaml           # Dependencies and configurations
```

---

For further information, feel free to explore the code or contact the project maintainer.
