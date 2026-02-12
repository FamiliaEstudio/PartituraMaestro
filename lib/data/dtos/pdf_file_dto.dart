class PdfFileDto {
  const PdfFileDto({
    required this.id,
    required this.path,
    required this.title,
    required this.displayName,
    this.uri,
    this.sourceFolderUri,
    this.sourceDocumentUri,
    this.fileHash,
    this.tagIds = const [],
  });

  final String id;
  final String path;
  final String title;
  final String displayName;
  final String? uri;
  final String? sourceFolderUri;
  final String? sourceDocumentUri;
  final String? fileHash;
  final List<String> tagIds;

  factory PdfFileDto.fromMap(Map<String, Object?> map, {List<String> tagIds = const []}) {
    return PdfFileDto(
      id: map['id'] as String,
      path: map['path'] as String,
      title: map['title'] as String,
      displayName: (map['display_name'] as String?) ?? (map['title'] as String),
      uri: map['uri'] as String?,
      sourceFolderUri: map['source_folder_uri'] as String?,
      sourceDocumentUri: map['source_document_uri'] as String?,
      fileHash: map['file_hash'] as String?,
      tagIds: tagIds,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'path': path,
        'title': title,
        'display_name': displayName,
        'uri': uri,
        'source_folder_uri': sourceFolderUri,
        'source_document_uri': sourceDocumentUri,
        'file_hash': fileHash,
      };
}
