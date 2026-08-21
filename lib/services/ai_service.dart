import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/artifact_model.dart';

class AiService {
  AiService({required this.apiKey, this.model = 'llama-3.3-70b-versatile'});

  final String apiKey;
  final String model;

  Future<ArtifactModel> createArtifact({
    required String rawText,
    required String type,
  }) async {
    if (apiKey.trim().isEmpty) return _mockArtifact(type, rawText);

    final response = await http.post(
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0.2,
        'messages': [
          {'role': 'system', 'content': _promptFor(type)},
          {'role': 'user', 'content': rawText},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI request failed (${response.statusCode}): ${response.body}');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final content = payload['choices'][0]['message']['content'] as String;
    return _parse(type, content);
  }

  String _promptFor(String type) => switch (type) {
        'bug' => '''Turn the user input into exactly this plain-text format. Do not add commentary.
Bug Title: [short title]
Description: [what's happening]
Environment: [inferred or "Not specified"]
Possible Causes: [numbered list]
Debug Steps: [numbered list]''',
        'commit' => '''Turn the user input into exactly this plain-text format. Do not add commentary.
Commit: [type(scope): short message, e.g. "fix(auth): handle null token response"]
PR Description:
Problem: [what was wrong]
Solution: [what was done]
Testing: [how to verify]''',
        _ => '''Turn the user input into exactly this plain-text format. Do not add commentary.
Feature: [title]
Components: [list]
API Changes: [list or "None"]
Implementation Tasks: [numbered list]''',
      };

  ArtifactModel _parse(String type, String content) {
    final labels = switch (type) {
      'bug' => ['Bug Title', 'Description', 'Environment', 'Possible Causes', 'Debug Steps'],
      'commit' => ['Commit', 'PR Description', 'Problem', 'Solution', 'Testing'],
      _ => ['Feature', 'Components', 'API Changes', 'Implementation Tasks'],
    };
    final fields = <String, dynamic>{};
    String? current;
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      final found = labels.where((label) => line.startsWith('$label:')).firstOrNull;
      if (found != null) {
        current = found;
        fields[current] = line.substring(found.length + 1).trim();
      } else if (current != null && line.isNotEmpty) {
        fields[current] = '${fields[current]}\n$line'.trim();
      }
    }
    for (final label in labels) {
      fields.putIfAbsent(label, () => 'Not specified');
    }
    final titleKey = type == 'bug' ? 'Bug Title' : type == 'commit' ? 'Commit' : 'Feature';
    return ArtifactModel(type: type, title: fields[titleKey] as String, fields: fields);
  }

  ArtifactModel _mockArtifact(String type, String text) {
    final fields = switch (type) {
      'bug' => {
          'Bug Title': 'Sample: app fails after submitting a form',
          'Description': text,
          'Environment': 'Not specified',
          'Possible Causes': '1. Invalid response parsing\n2. Missing null check',
          'Debug Steps': '1. Submit the form\n2. Inspect the network response',
        },
      'commit' => {
          'Commit': 'fix(form): handle empty server response',
          'PR Description': '',
          'Problem': text,
          'Solution': 'Validate the response before using its data.',
          'Testing': 'Submit a form with an empty response and verify no crash.',
        },
      _ => {
          'Feature': 'Sample: developer context relay',
          'Components': 'Capture screen, AI service, output screen',
          'API Changes': 'None',
          'Implementation Tasks': '1. Capture context\n2. Generate structured artifact\n3. Export it',
        },
    };
    final titleKey = type == 'bug' ? 'Bug Title' : type == 'commit' ? 'Commit' : 'Feature';
    return ArtifactModel(type: type, title: fields[titleKey]!, fields: fields);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
