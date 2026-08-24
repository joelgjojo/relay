import 'package:flutter_test/flutter_test.dart';
import 'package:relay/models/artifact_model.dart';

void main() {
  test('ArtifactModel preserves structured fields', () {
    const artifact = ArtifactModel(type: 'bug', title: 'Crash', fields: {'environment': 'Android'});
    expect(artifact.type, 'bug');
    expect(artifact.fields['environment'], 'Android');
  });

  test('ArtifactModel.fromJson parses commit schema', () {
    final artifact = ArtifactModel.fromJson('commit', {
      'commit_message': 'fix(auth): handle null token',
      'problem': 'Token was null after refresh',
      'solution': 'Added null check before use',
      'testing': 'Run auth flow and verify no crash',
    });

    expect(artifact.type, 'commit');
    expect(artifact.title, 'fix(auth): handle null token');
    expect(artifact.fields['commit_message'], 'fix(auth): handle null token');
    expect(artifact.fields['problem'], 'Token was null after refresh');
    expect(artifact.fields['solution'], 'Added null check before use');
    expect(artifact.fields['testing'], 'Run auth flow and verify no crash');
  });

  test('ArtifactModel.fromJson parses bug schema with arrays', () {
    final artifact = ArtifactModel.fromJson('bug', {
      'title': 'Login crash on Android 14',
      'environment': 'Android 14, Pixel 7',
      'possible_causes': ['Null pointer in auth service', 'Missing permission'],
      'debug_steps': ['Open app', 'Tap login', 'Check logcat'],
    });

    expect(artifact.type, 'bug');
    expect(artifact.title, 'Login crash on Android 14');
    expect(artifact.fields['possible_causes'], isA<List>());
    expect((artifact.fields['possible_causes'] as List).length, 2);
    expect(artifact.fields['debug_steps'], isA<List>());
  });

  test('ArtifactModel.fromJson handles missing fields with defaults', () {
    final artifact = ArtifactModel.fromJson('commit', {});

    expect(artifact.type, 'commit');
    expect(artifact.title, 'Untitled commit');
    expect(artifact.fields['problem'], 'Not specified');
  });

  test('toFormattedString produces readable output', () {
    final artifact = ArtifactModel.fromJson('commit', {
      'commit_message': 'fix(auth): handle null token',
      'problem': 'Token was null',
      'solution': 'Added null check',
      'testing': 'Manual test',
    });

    final output = artifact.toFormattedString();
    expect(output, contains('COMMIT'));
    expect(output, contains('fix(auth): handle null token'));
    expect(output, contains('Token was null'));
  });
}
