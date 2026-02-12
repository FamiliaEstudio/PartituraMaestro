import 'dart:typed_data';

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
}
