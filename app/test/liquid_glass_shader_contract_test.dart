import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('liquid glass shader follows Flutter ImageFilter shader contract', () async {
    final source = await File('shaders/nexa_liquid_glass.frag').readAsString();

    // ImageFilter.shader reserves the first vec2 and first sampler for the
    // engine-provided filter input. Keep the application uniforms after them.
    expect(source, contains('uniform vec2 u_size;'));
    expect(source, contains('uniform vec4 u_corner_radii;'));
    expect(source, contains('uniform sampler2D u_texture;'));

    // Flutter 3.47 changed Impeller GLES render-target orientation. Retain
    // the legacy flip only on engines that have not adopted top-down targets.
    expect(
      source,
      contains(
        '#if defined(IMPELLER_TARGET_OPENGLES) && '
        '!defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)',
      ),
    );
    expect(source, isNot(contains('#ifdef IMPELLER_TARGET_OPENGLES')));
    expect(source, contains('vec3(source.a)'));
  });
}
