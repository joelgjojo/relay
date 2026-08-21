import 'package:flutter_test/flutter_test.dart';
import 'package:relay/models/artifact_model.dart';

void main() {
  test('ArtifactModel preserves structured fields', () {
    const artifact = ArtifactModel(type: 'bug', title: 'Crash', fields: {'Environment': 'Android'});
    expect(artifact.type, 'bug');
    expect(artifact.fields['Environment'], 'Android');
  });
}
