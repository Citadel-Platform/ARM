import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/generate_conformance.dart';

/// `arm/contract/conformance.json` is what every ARM client — Dart, the
/// browser SDK, PHP, Node — must reproduce. This package is the reference, so
/// this test fails if the reference and the file disagree: either the Dart
/// contract changed without regenerating the file, or the file was edited by
/// hand. Both would leave the other clients testing against a contract the
/// reference no longer keeps. Feature 1.6.1.
void main() {
  test('the reference reproduces the conformance file exactly', () {
    final committed = jsonDecode(
      File('../contract/conformance.json').readAsStringSync(),
    );
    final regenerated = jsonDecode(jsonEncode(buildArmConformance()));
    expect(regenerated, committed);
  });
}
