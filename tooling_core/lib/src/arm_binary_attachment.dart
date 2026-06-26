import 'dart:typed_data';

import 'package:meta/meta.dart';

@immutable
class ArmBinaryAttachment {
  const ArmBinaryAttachment({
    required this.bytes,
    required this.contentType,
    required this.extension,
    this.name = 'attachment',
  });

  final Uint8List bytes;
  final String contentType;
  final String extension;
  final String name;
}
