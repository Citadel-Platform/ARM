import 'dart:convert';
import 'dart:io';

import 'package:arm_tooling_core/arm_tooling_core.dart';

const String armCaseIdHeaderName = 'X-ARM-Case-Id';

String? exposedArmCaseId(ArmCaptureResult? capture) {
  if (capture == null || !capture.caseIdExposed || capture.caseId.isEmpty) {
    return null;
  }
  return capture.caseId;
}

Map<String, Object?> buildArmJsonResponseBody({
  required Map<String, Object?> body,
  ArmCaptureResult? capture,
}) {
  final armCaseId = exposedArmCaseId(capture);
  return <String, Object?>{
    ...body,
    if (armCaseId != null) 'armCaseId': armCaseId,
  };
}

void applyArmCaseIdHeader(HttpResponse response, ArmCaptureResult? capture) {
  final armCaseId = exposedArmCaseId(capture);
  if (armCaseId != null) {
    response.headers.set(armCaseIdHeaderName, armCaseId);
  }
}

Future<void> respondArmJson(
  HttpRequest request, {
  required int statusCode,
  required Map<String, Object?> body,
  ArmCaptureResult? capture,
}) async {
  request.response.headers.contentType = ContentType.json;
  applyArmCaseIdHeader(request.response, capture);
  request.response.statusCode = statusCode;
  request.response.write(
    jsonEncode(buildArmJsonResponseBody(body: body, capture: capture)),
  );
  await request.response.close();
}
