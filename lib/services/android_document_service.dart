import 'package:flutter/services.dart';

class AndroidDocumentNode {
  const AndroidDocumentNode({
    required this.uri,
    required this.name,
    required this.isDirectory,
    required this.isFile,
    required this.mimeType,
  });

  final String uri;
  final String name;
  final bool isDirectory;
  final bool isFile;
  final String? mimeType;

  bool get isPdf =>
      isFile && ((mimeType?.toLowerCase() == 'application/pdf') || name.toLowerCase().endsWith('.pdf'));

  factory AndroidDocumentNode.fromMap(Map<Object?, Object?> map) {
    return AndroidDocumentNode(
      uri: map['uri'] as String,
      name: (map['name'] as String?) ?? 'Sem nome',
      isDirectory: (map['isDirectory'] as bool?) ?? false,
      isFile: (map['isFile'] as bool?) ?? false,
      mimeType: map['mimeType'] as String?,
    );
  }
}

class AndroidDocumentService {
  const AndroidDocumentService();

  static const MethodChannel _channel = MethodChannel('partituramaestro/document_browser');

  Future<String?> pickTree() async {
    return _channel.invokeMethod<String>('pickDocumentTree');
  }

  Future<List<AndroidDocumentNode>> listChildren({required String treeUri, required String parentUri}) async {
    final result = await _channel.invokeMethod<List<dynamic>>('listDocumentChildren', {
      'treeUri': treeUri,
      'parentUri': parentUri,
    });

    return (result ?? <dynamic>[])
        .whereType<Map>()
        .map((entry) => AndroidDocumentNode.fromMap(entry.cast<Object?, Object?>()))
        .toList();
  }
}
