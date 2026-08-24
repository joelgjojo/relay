import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/artifact_model.dart';

// ── Error types ──

/// Base class so callers can distinguish AI failures from other exceptions.
class AiServiceException implements Exception {
  AiServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiNetworkException extends AiServiceException {
  AiNetworkException([String? detail])
      : super(detail ?? 'Network error — check your connection and try again.');
}

class AiTimeoutException extends AiServiceException {
  AiTimeoutException() : super('Request timed out. Please try again.');
}

class AiRateLimitException extends AiServiceException {
  AiRateLimitException() : super('Rate limited — retrying with a smaller model…');
}

class AiParseException extends AiServiceException {
  AiParseException([String? detail]) : super(detail ?? "Couldn't process that — the response wasn't valid. Try again.");
}

// ── Service ──

class AiService {
  AiService({
    String? apiKey,
    this.primaryModel = 'llama-3.3-70b-versatile',
    this.fallbackModel = 'llama-3.1-8b-instant',
    this.timeout = const Duration(seconds: 12),
    http.Client? httpClient,
  })  : apiKey = apiKey ?? (dotenv.isInitialized ? (dotenv.env['GROQ_API_KEY'] ?? '') : ''),
        _client = httpClient ?? http.Client();

  final String apiKey;
  final String primaryModel;
  final String fallbackModel;
  final Duration timeout;
  final http.Client _client;

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  /// Main entry point — returns a structured [ArtifactModel] or throws an
  /// [AiServiceException] subclass the UI can handle.
  Future<ArtifactModel> createArtifact({
    required String rawText,
    required String type,
  }) async {
    if (apiKey.trim().isEmpty) {
      debugPrint('Relay AiService: API key is empty — returning MOCK artifact');
      return _mockArtifact(type, rawText);
    }
    debugPrint('Relay AiService: API key present (${apiKey.substring(0, 4)}…), calling Groq API');

    try {
      return await _callApi(rawText, type, primaryModel);
    } on AiRateLimitException {
      debugPrint('Relay AiService: Rate limited on $primaryModel, falling back to $fallbackModel');
      // Automatic fallback — try the smaller model once.
      return await _callApi(rawText, type, fallbackModel);
    }
  }

  Future<ArtifactModel> _callApi(String rawText, String type, String model) async {
    debugPrint('Relay AiService: POST $_endpoint (model: $model, type: $type, input: ${rawText.length} chars)');
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.2,
              'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'system', 'content': _systemPromptFor(type)},
                {'role': 'user', 'content': rawText},
              ],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiTimeoutException();
    } catch (e) {
      throw AiNetworkException(e.toString());
    }

    if (response.statusCode == 429) {
      throw AiRateLimitException();
    }

    if (response.body.trim().isEmpty) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiNetworkException('Groq returned ${response.statusCode}. Please try again.');
      }
      throw AiParseException('API returned an empty response body.');
    }

    // Parse the outer response envelope.
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw AiParseException('API response is not a valid JSON object.');
      }
      payload = decoded;
    } catch (_) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiNetworkException('Groq returned ${response.statusCode}. Please try again.');
      }
      throw AiParseException('Failed to parse API response JSON.');
    }

    // Handle Groq API returning an error object instead of success
    if (payload.containsKey('error') && payload['error'] != null) {
      final errorMsg = payload['error'] is Map ? payload['error']['message'] : payload['error'].toString();
      throw AiNetworkException('API Error: $errorMsg');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiNetworkException('Groq returned ${response.statusCode}. Please try again.');
    }

    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiParseException('Expected fields are missing from API response (choices).');
    }

    final message = choices[0]?['message'];
    if (message is! Map) {
      throw AiParseException('Expected fields are missing from API response (message).');
    }

    final content = message['content'];
    if (content == null) {
      throw AiParseException('Nested field "content" is null.');
    }
    if (content is! String || content.trim().isEmpty) {
      throw AiParseException('Nested field "content" is empty or not a string.');
    }

    // Parse the inner JSON object the model was forced to produce.
    final Map<String, dynamic> json;
    try {
      final decodedContent = jsonDecode(content);
      if (decodedContent is! Map<String, dynamic>) {
        throw AiParseException('LLM output is not a valid JSON object.');
      }
      json = decodedContent;
    } catch (_) {
      throw AiParseException('Failed to parse LLM output JSON.');
    }

    return ArtifactModel.fromJson(type, json);
  }

  // ── System prompts (exact spec) ──

  String _systemPromptFor(String type) => switch (type) {
        'commit' =>
          'You are a developer assistant that converts a spoken description of a code fix '
              'into a structured commit message and PR description. Always respond with valid JSON '
              'matching this exact schema: {commit_message, problem, solution, testing}. '
              'The commit_message must follow conventional commit format (type(scope): message).',
        'bug' =>
          'You are a developer assistant that converts error text into a structured bug report. '
              'Always respond with valid JSON matching this exact schema: '
              '{title, environment, possible_causes (array), debug_steps (array)}. '
              "If environment cannot be inferred, use 'Not specified'.",
        _ =>
          'You are a developer assistant that converts an architecture description into a '
              'structured feature proposal. Always respond with valid JSON matching this exact schema: '
              '{title, components (array), api_changes (array), implementation_tasks (array)}.',
      };

  // ── Mock fallback (no API key) ──

  ArtifactModel _mockArtifact(String type, String text) {
    switch (type) {
      case 'commit':
        return ArtifactModel.fromJson('commit', {
          'commit_message': 'fix(form): handle empty server response',
          'problem': text.isNotEmpty ? text : 'User did not provide problem description.',
          'solution': 'Validate the response before using its data.',
          'testing': 'Submit a form with an empty response and verify no crash.',
        });
      case 'bug':
        return ArtifactModel.fromJson('bug', {
          'title': text.isNotEmpty ? text : 'Bug Report',
          'environment': 'Not specified',
          'possible_causes': ['Captured input processing failed', 'Missing fallback handler'],
          'debug_steps': ['Check submitted text', 'Verify API key is configured'],
        });
      default:
        return ArtifactModel.fromJson('feature', {
          'title': text.isNotEmpty ? text : 'Feature Proposal',
          'components': ['Capture screen', 'AI service', 'Output screen'],
          'api_changes': ['None'],
          'implementation_tasks': [
            'Capture context',
            'Generate structured artifact',
            'Export it',
          ],
        });
    }
  }
}
