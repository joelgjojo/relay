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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0C0E14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RelayApp());
}

class RelayApp extends StatelessWidget {
  const RelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Relay',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0E14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF131722),
          error: Color(0xFFF43F5E),
          onPrimary: Colors.white,
          onSurface: Color(0xFFF1F5F9),
        ),
        fontFamily: 'sans-serif',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C0E14),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFFF1F5F9),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF131722),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0xFF22283A), width: 1),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E2435),
          contentTextStyle: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF333D56), width: 1),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        useMaterial3: true,
      ),
      home: const CaptureScreen(),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with SingleTickerProviderStateMixin {
  final _speech = stt.SpeechToText();
  final _recorder = AudioRecorder();
  final _textController = TextEditingController();
  String _type = 'bug';
  bool _recording = false;
  String _heard = '';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFF43F5E), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
    }
  }

  Color get _currentTypeColor {
    switch (_type) {
      case 'bug':
        return const Color(0xFFF43F5E);
      case 'commit':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6366F1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2435),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2E374E)),
              ),
              child: const Text(
                'RELAY',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: Color(0xFFF1F5F9),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'READY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // Header Section
            const Text(
              'Capture Context',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF8FAFC),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Synthesize raw voice, optical text, or notes into structured developer artifacts.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF94A3B8),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Target Artifact Type Selector
            const _SectionLabel(label: 'TARGET ARTIFACT TYPE'),
            const SizedBox(height: 8),
            _TypeSelector(
              selectedType: _type,
              onChanged: (val) => setState(() => _type = val),
            ),
            const SizedBox(height: 24),

            // Mode 1: Voice Capture Card
            const _SectionLabel(label: 'INPUT SOURCE 01 / VOICE'),
            const SizedBox(height: 8),
            _VoiceCaptureCard(
              isRecording: _recording,
              heardText: _heard,
              pulseAnimation: _pulseController,
              accentColor: _currentTypeColor,
              onTap: _toggleVoice,
            ),
            const SizedBox(height: 16),

            // Mode 2: Photo OCR Card
            const _SectionLabel(label: 'INPUT SOURCE 02 / OPTICAL OCR'),
            const SizedBox(height: 8),
            _PhotoOcrCard(onTap: _takePhoto),
            const SizedBox(height: 16),

            // Mode 3: Direct Text Input Card
            const _SectionLabel(label: 'INPUT SOURCE 03 / DIRECT TEXT'),
            const SizedBox(height: 8),
            _DirectTextInputCard(
              controller: _textController,
              accentColor: _currentTypeColor,
              onSubmit: () {
                if (_textController.text.trim().isEmpty) {
                  _showError('Enter developer context before processing.');
                } else {
                  _createArtifact(_textController.text.trim());
                }
              },
            ),
            const SizedBox(height: 24),

            // Footer telemetry
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F121C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1E2435)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub_outlined, size: 12, color: Color(0xFF64748B)),
                    SizedBox(width: 6),
                    Text(
                      'GROQ LLAMA-3.3 • LOCAL MLKIT OCR',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF64748B),
        letterSpacing: 1.0,
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selectedType, required this.onChanged});
  final String selectedType;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final types = [
      {'id': 'bug', 'label': 'Bug', 'icon': Icons.bug_report_outlined, 'color': const Color(0xFFF43F5E)},
      {'id': 'commit', 'label': 'Commit/PR', 'icon': Icons.merge_type_rounded, 'color': const Color(0xFF10B981)},
      {'id': 'feature', 'label': 'Feature', 'icon': Icons.lightbulb_outline_rounded, 'color': const Color(0xFF818CF8)},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22283A)),
      ),
      child: Row(
        children: types.map((t) {
          final isSelected = selectedType == t['id'];
          final color = t['color'] as Color;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(t['id'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withAlpha(35) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? color.withAlpha(120) : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      t['icon'] as IconData,
                      size: 16,
                      color: isSelected ? color : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t['label'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? const Color(0xFFF8FAFC) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _VoiceCaptureCard extends StatelessWidget {
  const _VoiceCaptureCard({
    required this.isRecording,
    required this.heardText,
    required this.pulseAnimation,
    required this.accentColor,
    required this.onTap,
  });

  final bool isRecording;
  final String heardText;
  final Animation<double> pulseAnimation;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: isRecording ? const Color(0xFF1A1117) : const Color(0xFF131722),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isRecording
                  ? const Color(0xFFF43F5E).withAlpha((100 + (pulseAnimation.value * 155)).toInt())
                  : const Color(0xFF22283A),
              width: isRecording ? 1.5 : 1.0,
            ),
            boxShadow: isRecording
                ? [
                    BoxShadow(
                      color: const Color(0xFFF43F5E).withAlpha((30 * pulseAnimation.value).toInt()),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isRecording
                                ? const Color(0xFFF43F5E).withAlpha(40)
                                : const Color(0xFF1E2435),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isRecording
                                  ? const Color(0xFFF43F5E).withAlpha(120)
                                  : const Color(0xFF2E374E),
                            ),
                          ),
                          child: Icon(
                            isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
                            color: isRecording ? const Color(0xFFF43F5E) : const Color(0xFF38BDF8),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    isRecording ? 'RECORDING VOICE...' : 'Audio Stream',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isRecording ? const Color(0xFFF43F5E) : const Color(0xFFF1F5F9),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F121C),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF22283A)),
                                    ),
                                    child: const Text(
                                      'VOICE',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isRecording
                                    ? 'Tap card to finalize speech stream'
                                    : 'Dictate bug symptoms, PR context, or architecture ideas',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (isRecording) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0E14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2E1A24)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '> ',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: Color(0xFFF43F5E),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                heardText.isEmpty ? 'Listening for speech input...' : heardText,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: heardText.isEmpty
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFFF1F5F9),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoOcrCard extends StatelessWidget {
  const _PhotoOcrCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22283A)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2435),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF2E374E)),
                  ),
                  child: const Icon(
                    Icons.document_scanner_outlined,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Optical Lens OCR',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF1F5F9),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F121C),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF22283A)),
                            ),
                            child: const Text(
                              'ML KIT',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Extract text directly from terminal logs, IDE, or diagrams',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectTextInputCard extends StatelessWidget {
  const _DirectTextInputCard({
    required this.controller,
    required this.accentColor,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final Color accentColor;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22283A)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 16, color: Color(0xFF818CF8)),
              const SizedBox(width: 8),
              const Text(
                'Prompt Editor',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF1F5F9),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F121C),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF22283A)),
                ),
                child: const Text(
                  'TEXT',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF090B10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2435)),
            ),
            child: TextField(
              controller: controller,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFE2E8F0),
                height: 1.4,
              ),
              cursorColor: accentColor,
              decoration: const InputDecoration(
                hintText: 'e.g. auth service throwing 401 when refresh token expires...',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF475569),
                ),
                contentPadding: EdgeInsets.all(12),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text(
                'Synthesize Artifact',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              onPressed: onSubmit,
            ),
          ),
        ],
      ),
    );
  }
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
