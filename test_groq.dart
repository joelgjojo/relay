import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'lib/services/ai_service.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  final service = AiService();
  try {
    final artifact = await service.createArtifact(
      rawText: "app fails after submitting a form",
      type: "bug",
    );
    print(artifact.title);
    print(artifact.fields);
  } catch (e) {
    print("Error: $e");
  }
}
