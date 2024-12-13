import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart'; // For getting the correct storage directory
import 'dart:math';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: Colors.black,
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
        ),
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  bool _isCanceling = false; // To control cancel action
  String? _filePath; // To store the file path of the selected file
  int _secondsElapsed = 0;
  Timer? _timer;
  List<List<double>> melFeaturesList = [];
  String _statusMessage = 'Ready to pick a file.';
  bool _isProcessing = false;
  int _processedChunks = 0;
  int _totalChunks = 0;
  List<String> labels = [];
  late Interpreter
      _interpreter; // Declare the model interpreter as a global variable

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _requestPermissions();
    _loadLabels();
    _initializeModel(); // Load the model during initialization
  }
/////// ************

  /// Load the TFLite model once during startup
  Future<void> _initializeModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      setState(() {
        _statusMessage = 'Model loaded successfully.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading model: $e';
      });
    }
  }

  Future<void> _loadLabels() async {
    String labelsText = await rootBundle.loadString('assets/labels.txt');
    labels = labelsText.split('\n').map((e) => e.trim()).toList();
  }

  Future<void> _requestPermissions() async {
    // Request microphone permission
    PermissionStatus microphoneStatus = await Permission.microphone.request();

    // Request storage permissions based on the platform
    bool isStoragePermissionGranted;
    if (Platform.isAndroid) {
      if (await Permission.storage.isGranted ||
          await Permission.manageExternalStorage.isGranted) {
        isStoragePermissionGranted = true;
      } else {
        // Request both storage and manage external storage permissions
        isStoragePermissionGranted =
            await Permission.storage.request().isGranted ||
                await Permission.manageExternalStorage.request().isGranted;
      }
    } else if (Platform.isIOS) {
      isStoragePermissionGranted = await Permission.storage.request().isGranted;
    } else {
      isStoragePermissionGranted = false;
    }

    // Check and display status
    if (microphoneStatus.isGranted && isStoragePermissionGranted) {
      print('All required permissions granted.');
    } else {
      print('Some permissions were denied.');
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _statusMessage = 'Picking file...';
    });

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        melFeaturesList.clear();
        _processedChunks = 0;
        _totalChunks = 0;

        _filePath = result.files.single.path!;
        _statusMessage = 'Selected file: $_filePath';
      });
    } else {
      setState(() {
        _statusMessage = 'No file selected.';
      });
    }
  }

  Future<void> _extractFeatures() async {
    if (_filePath == null) {
      setState(() {
        _statusMessage = 'Please select a file first.';
      });
      return;
    }

    setState(() {
      _statusMessage = 'Starting feature extraction...';
      _isProcessing = true;
      melFeaturesList.clear();
      _processedChunks = 0;
    });

    try {
      await _processAudioInChunks(_filePath!);
      setState(() {
        _statusMessage =
            'Feature extraction complete for $_processedChunks chunks.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error during extraction: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processAudioInChunks(String filePath) async {
    Directory tempDir = await getTemporaryDirectory();
    String randomFolderName = _generateRandomString(10);
    Directory audioFolder = Directory('${tempDir.path}/$randomFolderName');
    await audioFolder.create(recursive: true);

    _totalChunks = 30; // Assume 30 chunks for now
    setState(() {
      _processedChunks = 0;
    });

    for (int i = 0; i < _totalChunks; i++) {
      String chunkOutputPath = '${audioFolder.path}/chunk_$i.pcm';
      String command =
          '-i "$filePath" -f s16le -ac 1 -ar 10000 -ss ${(i * 2)} -t 2 "$chunkOutputPath"';
      print("FFmpeg Command: $command");

      try {
        await _processChunk(command, chunkOutputPath, i);
        await Future.delayed(
            Duration(milliseconds: 500)); // Delay between chunks
      } catch (e) {
        setState(() {
          _statusMessage = 'Error processing chunk $i: $e';
        });
      }
    }

    setState(() {
      _statusMessage =
          'Feature extraction complete for $_processedChunks chunks.';
    });
  }

  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rand = Random();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)])
        .join();
  }

  List<int> quantizeInput(List<double> input) {
    double scale = 0.0037837;
    int zeroPoint = -128;

    return input.map((value) {
      int quantizedValue = ((value / scale) + zeroPoint).round();
      return quantizedValue.clamp(-128, 127);
    }).toList();
  }

  Map<String, int> labelCounts = {}; // To store label counts
  String mostFrequentLabel = ''; // To store the most frequent label

  Future<void> _processChunk(
      String command, String chunkOutputPath, int chunkIndex) async {
    try {
      final session = await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();
        if (returnCode?.isValueSuccess() ?? false) {
          List<int> pcmData = await _readPcmData(chunkOutputPath);
          List<double> melFeatures = _extractMelFeatures(pcmData, 10000);

          List<int> quantizedMelFeatures = quantizeInput(melFeatures);

          var input = quantizedMelFeatures;
          var output = List.filled(1 * 3, 0).reshape([1, 3]);

          _interpreter.run(input, output);

          print(output);

          // Match the output with the labels
          List<num> outputList =
              output[0].cast<num>(); // Explicit cast to List<num>
          int predictedLabelIndex = outputList.indexOf(outputList.reduce(max));
          String predictedLabel = labels[predictedLabelIndex];
          print('Predicted label: $predictedLabel');

          melFeaturesList.add(melFeatures);

          // Count the label occurrences
          labelCounts[predictedLabel] = (labelCounts[predictedLabel] ?? 0) + 1;

          setState(() {
            _processedChunks++;
          });

          // Update the most frequent label after all chunks are processed
          if (_processedChunks == 30) {
            mostFrequentLabel = labelCounts.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key;
            setState(() {}); // Update UI with the most frequent label
          }
        } else {
          throw Exception('Error extracting PCM chunk $chunkIndex.');
        }
      });
    } catch (e) {
      throw Exception('Error processing chunk $chunkIndex: $e');
    }
  } 

  Future<List<int>> _readPcmData(String pcmPath) async {
    final file = File(pcmPath);
    if (await file.exists()) {
      Uint8List rawData = await file.readAsBytes();
      return rawData.buffer.asInt16List().toList();
    } else {
      throw Exception('PCM file does not exist at $pcmPath');
    }
  }

  List<double> _normalizeFeatures(List<double> melFeatures) {
    double minVal = melFeatures.reduce(min);
    double maxVal = melFeatures.reduce(max);

    return melFeatures.map((value) {
      return ((value - minVal) / (maxVal - minVal) * 255 - 128)
          .toInt()
          .toDouble();
    }).toList();
  }

  List<double> _extractMelFeatures(List<int> pcmData, int sampleRate) {
    List<double> normalizedData = pcmData.map((e) => e / pow(2, 15)).toList();
    List<double> fftMagnitudes = _computeFftMagnitudes(normalizedData);
    List<double> melSpectrogram =
        _computeMelSpectrogram(fftMagnitudes, sampleRate);
    List<double> logMelSpectrogram =
        melSpectrogram.map((value) => log(value + 1e-9)).toList();

    // Normalize features
    List<double> normalizedMelFeatures = _normalizeFeatures(logMelSpectrogram);

    // Truncate to 10,000 features or pad if less
    List<double> melFeatures = normalizedMelFeatures.take(10000).toList();

    if (melFeatures.length < 10000) {
      melFeatures.addAll(List.filled(10000 - melFeatures.length, 0.0));
    }

    return melFeatures;
  }

  List<double> _computeFftMagnitudes(List<double> audioData) {
    int n = audioData.length;
    List<double> magnitudes = List.filled(n ~/ 2, 0);

    for (int k = 0; k < n ~/ 2; k++) {
      double real = 0.0, imaginary = 0.0;
      for (int t = 0; t < n; t++) {
        real += audioData[t] * cos(2 * pi * k * t / n);
        imaginary -= audioData[t] * sin(2 * pi * k * t / n);
      }
      magnitudes[k] = sqrt(real * real + imaginary * imaginary);
    }

    return magnitudes;
  }

  List<double> _computeMelSpectrogram(
      List<double> fftMagnitudes, int sampleRate) {
    int melBinCount = 40;
    double lowerFreq = 20.0;
    double upperFreq = sampleRate / 2.0;
    List<List<double>> melFilterBanks = _createMelFilterBanks(
        melBinCount, lowerFreq, upperFreq, fftMagnitudes.length);

    List<double> melSpectrogram = List.filled(melBinCount, 0.0);
    for (int i = 0; i < melBinCount; i++) {
      for (int j = 0; j < fftMagnitudes.length; j++) {
        melSpectrogram[i] += melFilterBanks[i][j] * fftMagnitudes[j];
      }
    }

    return melSpectrogram;
  }

  List<List<double>> _createMelFilterBanks(
      int melBinCount, double lowerFreq, double upperFreq, int fftBinCount) {
    List<List<double>> filterBanks =
        List.generate(melBinCount, (index) => List.filled(fftBinCount, 0.0));

    double melLow = _hzToMel(lowerFreq);
    double melHigh = _hzToMel(upperFreq);
    double melStep = (melHigh - melLow) / (melBinCount + 1);

    for (int i = 0; i < melBinCount; i++) {
      double melCenter = melLow + (i + 1) * melStep;
      double hzCenter = _melToHz(melCenter);

      for (int j = 0; j < fftBinCount; j++) {
        double freq = j * (upperFreq / fftBinCount);
        double mel = _hzToMel(freq);
        double weight = max(0.0, 1.0 - (mel - melCenter).abs() / melStep);
        filterBanks[i][j] = weight;
      }
    }

    return filterBanks;
  }

  double _hzToMel(double hz) {
    return 1127.0 * log(1.0 + hz / 700.0);
  }

  double _melToHz(double mel) {
    return 700.0 * (exp(mel / 1127.0) - 1.0);
  }

///////********
  void _initRecorder() async {
    await _recorder.openRecorder();
  }

  Future<void> _toggleRecording() async {
    try {
      _secondsElapsed = 0; // Reset the timer
      _startTimer();

      // Get the correct directory for saving the audio file
      Directory directory;
      if (await Permission.manageExternalStorage.isGranted) {
        directory = (await getExternalStorageDirectory())!;
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      final filePath = '${directory.path}/recorded_audio.wav';

      // Start recording
      await _recorder.startRecorder(
        toFile: filePath,
        codec: Codec.pcm16WAV, // Use WAV format
      );

      setState(() {
        _isRecording = true;
        _filePath = filePath;
        _isCanceling = false; // Ensure cancel is hidden once recording starts
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording started')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stopRecorder();
      _stopTimer();

      setState(() {
        _isRecording = false;
        _isCanceling = false; // Reset cancel button state
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Recording stopped automatically after 60 seconds')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error stopping recording: $e')),
      );
    }
  }

  Future<void> _cancelRecording() async {
    try {
      await _recorder.stopRecorder();
      _stopTimer();

      setState(() {
        _isRecording = false;
        _isCanceling = false;
        _filePath = null; // Clear file path on cancel
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording canceled')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error canceling recording: $e')),
      );
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
      if (_secondsElapsed >= 60) {
        _stopRecording(); // Automatically stop after 60 seconds
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  @override
  void dispose() {
    super.dispose();
    _recorder.closeRecorder();
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI Classification'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Record/Cancel button icon
            IconButton(
              icon: Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                size: 150,
                color: _isRecording ? Colors.red : Colors.blue,
              ),
              onPressed: _isRecording
                  ? null
                  : _toggleRecording, // Disable during recording
            ),

            // If recording, show cancel button
            if (_isRecording)
              ElevatedButton(
                onPressed: _cancelRecording,
                child: Text('Cancel Recording'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
              ),
            SizedBox(height: 20),
            if (_isRecording)
              Text(
                'Recording time: ${_secondsElapsed}s',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            if (_secondsElapsed >= 60)
              Text(
                'Record saved',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isProcessing ? null : _extractFeatures,
              child: Text('Extract Features'),
            ),
            SizedBox(height: 16),
            Text(_statusMessage),
            SizedBox(height: 16),
            Text('Processed Chunks: $_processedChunks / $_totalChunks'),
            SizedBox(height: 16),
            if (mostFrequentLabel.isNotEmpty)
              Text(
                'Most Frequent Label: $mostFrequentLabel',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFile,
        backgroundColor: Colors.blueAccent,
        child: Icon(Icons.add, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
