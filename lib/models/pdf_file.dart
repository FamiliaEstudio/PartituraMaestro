class PdfFile {
  final String id;
  String path;
  String title;
  List<String> tagIds;

  PdfFile({
    required this.id,
    required this.path,
    required this.title,
    List<String>? tagIds,
  }) : tagIds = tagIds ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'title': title,
    };
  }
}
