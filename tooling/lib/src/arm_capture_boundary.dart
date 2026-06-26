import 'dart:ui' as ui;

import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ArmCaptureBoundaryController {
  final GlobalKey _boundaryKey = GlobalKey();

  GlobalKey get boundaryKey => _boundaryKey;

  Future<ArmBinaryAttachment?> capturePng({double pixelRatio = 1.5}) async {
    final context = _boundaryKey.currentContext;
    if (context == null) return null;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) return null;
    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return null;
      return ArmBinaryAttachment(
        bytes: byteData.buffer.asUint8List(),
        contentType: 'image/png',
        extension: 'png',
        name: 'screen_capture',
      );
    } catch (_) {
      return null;
    }
  }
}

class ArmCaptureBoundary extends StatelessWidget {
  const ArmCaptureBoundary({
    super.key,
    required this.controller,
    required this.child,
  });

  final ArmCaptureBoundaryController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: controller.boundaryKey, child: child);
  }
}
