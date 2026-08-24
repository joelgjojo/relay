/// Structured developer artifact produced by the AI service.
class ArtifactModel {
  const ArtifactModel({
    required this.type,
    required this.title,
    required this.fields,
  });

  final String type;
  final String title;
  final Map<String, dynamic> fields;

  /// Build a type-safe [ArtifactModel] from the JSON map returned by Groq.
  ///
  /// The [type] is injected by the caller because we don't rely on the model
  /// to echo it correctly — we already know what we asked for.
  factory ArtifactModel.fromJson(String type, Map<String, dynamic> json) {
    switch (type) {
      case 'commit':
        return ArtifactModel(
          type: 'commit',
          title: _str(json, 'commit_message', 'Untitled commit'),
          fields: {
            'commit_message': _str(json, 'commit_message', 'Untitled commit'),
            'problem': _str(json, 'problem', 'Not specified'),
            'solution': _str(json, 'solution', 'Not specified'),
            'testing': _str(json, 'testing', 'Not specified'),
          },
        );

      case 'bug':
        return ArtifactModel(
          type: 'bug',
          title: _str(json, 'title', 'Untitled bug'),
          fields: {
            'title': _str(json, 'title', 'Untitled bug'),
            'environment': _str(json, 'environment', 'Not specified'),
            'possible_causes': _strList(json, 'possible_causes'),
            'debug_steps': _strList(json, 'debug_steps'),
          },
        );

      default: // feature
        return ArtifactModel(
          type: 'feature',
          title: _str(json, 'title', 'Untitled feature'),
          fields: {
            'title': _str(json, 'title', 'Untitled feature'),
            'components': _strList(json, 'components'),
            'api_changes': _strList(json, 'api_changes'),
            'implementation_tasks': _strList(json, 'implementation_tasks'),
          },
        );
    }
  }

  /// Human-readable multi-line string for clipboard export.
  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('Type: ${type.toUpperCase()}');
    buffer.writeln();
    for (final entry in fields.entries) {
      final label =
          entry.key.replaceAll('_', ' ').replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());
      final value = entry.value;
      if (value is List) {
        buffer.writeln('$label:');
        for (var i = 0; i < value.length; i++) {
          buffer.writeln('  ${i + 1}. ${value[i]}');
        }
      } else {
        buffer.writeln('$label: $value');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  // ── helpers ──

  static String _str(Map<String, dynamic> json, String key, String fallback) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static List<String> _strList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return ['Not specified'];
  }
}
