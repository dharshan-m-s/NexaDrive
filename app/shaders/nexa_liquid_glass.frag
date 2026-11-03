#version 460 core
#include <flutter/runtime_effect.glsl>

// ImageFilter.shader supplies u_size (float slots 0-1) and u_texture
// (sampler slot 0). Keep these first and in this order.
uniform vec2 u_size;
uniform vec4 u_corner_radii; // top-left, top-right, bottom-right, bottom-left
uniform sampler2D u_texture;
out vec4 fragColor;

float cornerRadius(vec2 local) {
  if (local.x < 0.0) {
    return local.y < 0.0 ? u_corner_radii.x : u_corner_radii.w;
  }
  return local.y < 0.0 ? u_corner_radii.y : u_corner_radii.z;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 uv = pixel / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  vec2 halfSize = u_size * 0.5;
  vec2 local = pixel - halfSize;
  float radius = clamp(cornerRadius(local), 0.0, min(halfSize.x, halfSize.y));

  // Rounded-rectangle signed distance field.
  vec2 corner = abs(local) - (halfSize - vec2(radius));
  float signedDistance =
      length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - radius;
  float insideDistance = max(-signedDistance, 0.0);

  // Optical shoulder and rim are deliberately restrained: the centre remains
  // clear while the edge visibly lenses the live scene behind the surface.
  float edgeSpan = clamp(min(u_size.x, u_size.y) * 0.34, 15.0, 28.0);
  float edgeMask = 1.0 - smoothstep(1.0, edgeSpan, insideDistance);
  float softBulge = exp(-insideDistance / (edgeSpan * 1.65));
  float rimLine = exp(-pow((insideDistance - 1.5) / 1.8, 2.0));
  float innerRim = exp(-pow((insideDistance - 8.0) / 5.0, 2.0));

  // Nearest-edge normal; rounded corners use their true radial normal.
  vec2 outside = max(corner, vec2(0.0));
  vec2 normalVector;
  if (outside.x > 0.0 && outside.y > 0.0) {
    normalVector = outside * sign(local);
  } else if (corner.x > corner.y) {
    normalVector = vec2(sign(local.x), 0.0);
  } else {
    normalVector = vec2(0.0, sign(local.y));
  }
  vec2 normal = normalize(normalVector + vec2(0.0001, 0.0001));

  float wave = sin(insideDistance * 0.19 + uv.x * 7.0 - uv.y * 5.0);
  float shoulder = edgeMask * (13.5 + wave * 2.2);
  float centreWarp = softBulge * 1.15;
  vec2 bend = normal * ((shoulder + centreWarp) / u_size);
  vec2 dispersion = normal * (edgeMask * 1.65 / u_size);

  vec2 baseUv = clamp(uv, vec2(0.001), vec2(0.999));
  vec2 redUv = clamp(baseUv + bend + dispersion, vec2(0.001), vec2(0.999));
  vec2 greenUv = clamp(baseUv + bend, vec2(0.001), vec2(0.999));
  vec2 blueUv = clamp(baseUv + bend - dispersion, vec2(0.001), vec2(0.999));

  vec4 source = texture(u_texture, baseUv);
  vec3 refracted;
  refracted.r = texture(u_texture, redUv).r;
  refracted.g = texture(u_texture, greenUv).g;
  refracted.b = texture(u_texture, blueUv).b;
  float refractionStrength = clamp(edgeMask * 0.72 + softBulge * 0.10, 0.0, 0.78);
  vec3 optical = mix(source.rgb, refracted, refractionStrength);

  vec3 spectral = mix(
      vec3(0.22, 0.78, 0.96),
      vec3(0.68, 0.53, 1.0),
      smoothstep(0.02, 0.98, uv.x));
  float diagonal = uv.y - (0.055 + uv.x * 0.16);
  float specular = exp(-pow(diagonal / 0.075, 2.0)) *
      smoothstep(0.02, 0.25, uv.x) * 0.075;
  float edgeReflection = rimLine * 0.17 + innerRim * 0.045;
  float fresnel = pow(edgeMask, 1.35);

  optical += spectral * edgeReflection;
  optical += vec3(1.0) * (rimLine * 0.16 + specular);
  optical += vec3(0.10, 0.20, 0.33) * fresnel * 0.035;

  // Runtime-effect output is premultiplied alpha.
  fragColor = vec4(clamp(optical, 0.0, 1.0) * source.a, source.a);
}
