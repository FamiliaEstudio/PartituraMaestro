import 'package:flutter/services.dart';

class UriAccessService {
  const UriAccessService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'partituramaestro/uri_access';
  final MethodChannel _channel;

  Future<bool> persistReadPermission(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>('persistUriPermission', {'uri': uri});
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Uint8List?> readBytes(String uri) async {
    try {
      return _channel.invokeMethod<Uint8List>('openUriBytes', {'uri': uri});
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<UriDocumentMetadata>> listTreeDocumentsRecursively(String treeUri) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'listTreeDocumentsRecursively',
        {'treeUri': treeUri},
      );

      return (result ?? <dynamic>[])
          .whereType<Map>()
          .map((entry) => UriDocumentMetadata.fromMap(entry.cast<Object?, Object?>()))
          .toList();
    } on MissingPluginException {
      return const [];
    }
  }
}

class UriDocumentMetadata {
  const UriDocumentMetadata({
    required this.displayName,
    required this.uri,
    required this.size,
    required this.mimeType,
  });

  final String displayName;
  final String uri;
  final int? size;
  final String? mimeType;

  bool get isPdf =>
      (mimeType?.toLowerCase() == 'application/pdf') || displayName.toLowerCase().endsWith('.pdf');

  factory UriDocumentMetadata.fromMap(Map<Object?, Object?> map) {
    return UriDocumentMetadata(
      displayName: (map['displayName'] as String?) ?? 'Sem nome',
      uri: map['uri'] as String,
      size: (map['size'] as num?)?.toInt(),
      mimeType: map['mimeType'] as String?,
    );
  }
}
