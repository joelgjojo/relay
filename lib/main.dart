import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'models/artifact_model.dart';
import 'services/ai_service.dart';

const _groqApiKey = String.fromEnvironment('GROQ_API_KEY');

void main() => runApp(const RelayApp());

class RelayApp extends StatelessWidget {
  const RelayApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Relay',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff5B5BD6)),
          useMaterial3: true,
        ),
        home: const CaptureScreen(),
      );
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _speech = stt.SpeechToText();
  final _recorder = AudioRecorder();
  final _textController = TextEditingController();
  String _type = 'bug';
  bool _recording = false;
  String _heard = '';

  @override
  void dispose() {
    _textController.dispose();
    _speech.stop();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      await _speech.stop();
      await _recorder.stop();
      setState(() => _recording = false);
      if (_heard.trim().isNotEmpty && mounted) _createArtifact(_heard);
      return;
    }
    final speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' && _recording && mounted) _toggleVoice();
      },
      onError: (error) => _showError('Speech recognition: ${error.errorMsg}'),
    );
    final canRecord = await _recorder.hasPermission();
    if (!speechAvailable || !canRecord) {
      _showError('Microphone and speech-recognition permissions are required.');
      return;
    }
    setState(() {
      _recording = true;
      _heard = '';
    });
    await _recorder.start(const RecordConfig(), path: 'relay_voice.m4a');
    await _speech.listen(
      onResult: (result) => setState(() => _heard = result.recognizedWords),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      if (photo == null) return;
      final recognizer = TextRecognizer();
      final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      await recognizer.close();
      if (result.text.trim().isEmpty) {
        _showError('No text was found in that photo.');
        return;
      }
      if (mounted) _createArtifact(result.text);
    } catch (error) {
      _showError('Photo text extraction failed: $error');
    }
  }

  Future<void> _createArtifact(String input) async {
    final artifact = await Navigator.of(context).push<ArtifactModel>(
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(input: input, type: _type),
      ),
    );
    if (artifact != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OutputScreen(artifact: artifact)));
    }
  }

  void _showError(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Relay'), centerTitle: false),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Capture developer context', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Turn a thought, error, or screenshot into a structured artifact.'),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bug', label: Text('Bug')),
                ButtonSegment(value: 'commit', label: Text('Commit / PR')),
                ButtonSegment(value: 'feature', label: Text('Feature')),
              ],
              selected: {_type},
              onSelectionChanged: (value) => setState(() => _type = value.first),
            ),
            const SizedBox(height: 24),
            _CaptureButton(
              icon: _recording ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
              label: _recording ? 'Stop & process voice' : 'Record Voice',
              subtitle: _recording ? (_heard.isEmpty ? 'Listening…' : _heard) : 'Speak a bug, fix, or idea',
              onPressed: _toggleVoice,
            ),
            const SizedBox(height: 12),
            _CaptureButton(icon: Icons.camera_alt_outlined, label: 'Take Photo', subtitle: 'Extract text from a screenshot or whiteboard', onPressed: _takePhoto),
            const SizedBox(height: 20),
            TextField(
              controller: _textController,
              minLines: 4,
              maxLines: 6,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Type developer context…'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Type Text & Create'),
              onPressed: () {
                if (_textController.text.trim().isEmpty) {
                  _showError('Enter some developer context first.');
                } else {
                  _createArtifact(_textController.text.trim());
                }
              },
            ),
            const Spacer(),
            Text('API key missing? Relay uses a clearly labelled sample result.', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.icon, required this.label, required this.subtitle, required this.onPressed});
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(18), alignment: Alignment.centerLeft),
        child: Row(children: [Icon(icon), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), const SizedBox(height: 3), Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)]))]),
      );
}

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.input, required this.type});
  final String input;
  final String type;
  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_process());
  }

  Future<void> _process() async {
    try {
      final artifact = await AiService(apiKey: _groqApiKey).createArtifact(rawText: widget.input, type: widget.type);
      if (mounted) Navigator.of(context).pop(artifact);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create artifact: $error')));
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 18), Text('Relay is structuring your developer context…')])));
}

class OutputScreen extends StatelessWidget {
  const OutputScreen({super.key, required this.artifact});
  final ArtifactModel artifact;

  String get _formatted => artifact.fields.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n\n');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(artifact.type.toUpperCase())),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(artifact.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          ...artifact.fields.entries.map(
            (entry) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SelectableText('${entry.value}'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _formatted));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Formatted artifact copied to clipboard.')));
            },
            icon: const Icon(Icons.content_copy),
            label: const Text('Copy formatted output'),
          ),
        ]),
      );
}
