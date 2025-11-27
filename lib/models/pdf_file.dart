class PdfFile {
  final String id;
  String path;
  String title;
  List<String> tagIds;

  PdfFile({
    required this.id,
    required this.path,
    required this.title,
    this.tagIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'title': title,
      'tagIds': tagIds, // Na prática pode precisar converter para JSON string ou tabela relacional
    };
  }
}
