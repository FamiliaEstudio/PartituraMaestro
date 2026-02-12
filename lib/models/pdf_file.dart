class PdfFile {
  final String id;
  String path;
  String title;
  String? uri;
  String? sourceFolderUri;
  String? sourceDocumentUri;
  String displayName;
  String? fileHash;
  List<String> tagIds;

  PdfFile({
    required this.id,
    required this.path,
    required this.title,
    String? uri,
    this.sourceFolderUri,
    this.sourceDocumentUri,
    String? displayName,
    this.fileHash,
    List<String>? tagIds,
  })  : uri = uri,
        displayName = displayName ?? title,
        tagIds = tagIds ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'title': title,
      'uri': uri,
      'source_folder_uri': sourceFolderUri,
      'source_document_uri': sourceDocumentUri,
      'display_name': displayName,
      'file_hash': fileHash,
    };
  }
}
