class ArtifactModel {
  const ArtifactModel({
    required this.type,
    required this.title,
    required this.fields,
  });

  final String type;
  final String title;
  final Map<String, dynamic> fields;
}
