import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay/services/ai_service.dart';

void main() {
  group('AiService API tests', () {
    test('Successful form submission', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'title': 'Test title',
                    'environment': 'Test env',
                  })
                }
              }
            ]
          }),
          200,
        );
      });

      final service = AiService(apiKey: 'test_key', httpClient: client);
      final artifact = await service.createArtifact(rawText: 'test', type: 'bug');
      expect(artifact.type, 'bug');
      expect(artifact.title, 'Test title');
      expect(artifact.fields['environment'], 'Test env');
    });

    test('Expected API error response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Invalid API key provided.'}
          }),
          401,
        );
      });

      final service = AiService(apiKey: 'test_key', httpClient: client);
      expect(
        () => service.createArtifact(rawText: 'test', type: 'bug'),
        throwsA(isA<AiNetworkException>().having((e) => e.message, 'message', contains('API Error: Invalid API key provided.'))),
      );
    });

    test('Malformed response (invalid JSON outer)', () async {
      final client = MockClient((request) async {
        return http.Response('not valid json', 200);
      });

      final service = AiService(apiKey: 'test_key', httpClient: client);
      expect(
        () => service.createArtifact(rawText: 'test', type: 'bug'),
        throwsA(isA<AiParseException>().having((e) => e.message, 'message', contains('Failed to parse API response JSON.'))),
      );
    });
    
    test('Malformed response (invalid JSON inner content)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': 'not valid json'
                }
              }
            ]
          }),
          200,
        );
      });

      final service = AiService(apiKey: 'test_key', httpClient: client);
      expect(
        () => service.createArtifact(rawText: 'test', type: 'bug'),
        throwsA(isA<AiParseException>().having((e) => e.message, 'message', contains('Failed to parse LLM output JSON.'))),
      );
    });

    test('Null/missing fields (no choices)', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'other_field': 'value'}), 200);
      });

      final service = AiService(apiKey: 'test_key', httpClient: client);
      expect(
        () => service.createArtifact(rawText: 'test', type: 'bug'),
        throwsA(isA<AiParseException>().having((e) => e.message, 'message', contains('Expected fields are missing from API response (choices).'))),
      );
    });
    
    test('Null/missing fields (content is null)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': null
                }
              }
            ]
          }),
          200,
        );
      });

      final service = AiService(apiKey: 'test_key', httpClient: client);
      expect(
        () => service.createArtifact(rawText: 'test', type: 'bug'),
        throwsA(isA<AiParseException>().having((e) => e.message, 'message', contains('Nested field "content" is null.'))),
      );
    });

    test('Empty response body', () async {
      final client = MockClient((request) async {
        return http.Response('', 200);
      });

      final service = AiService(apiKey: 'test_key', httpClient: client);
      expect(
        () => service.createArtifact(rawText: 'test', type: 'bug'),
        throwsA(isA<AiParseException>().having((e) => e.message, 'message', contains('API returned an empty response body.'))),
      );
    });

    test('Mock fallback when API key is empty', () async {
      final service = AiService(apiKey: '');
      final artifact = await service.createArtifact(rawText: 'test input text', type: 'commit');
      expect(artifact.type, 'commit');
      // Mock should use the actual input text, not hardcoded data
      expect(artifact.fields['problem'], 'test input text');
    });

    test('Mock fallback uses actual input for bug type', () async {
      final service = AiService(apiKey: '');
      final artifact = await service.createArtifact(rawText: 'my real bug description', type: 'bug');
      expect(artifact.type, 'bug');
      expect(artifact.title, 'my real bug description');
    });
  });
}
