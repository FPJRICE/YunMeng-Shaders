#version 330 compatibility
/* =============================================================================
 * gbuffers_weather.fsh — Dedicated atmospheric precipitation accumulation pass
 * Writes soft rain/snow coverage to colortex3 without overwriting G-buffer
 * surface albedo (colortex0), normals/tags (colortex1), lightmaps (colortex2),
 * motion vectors (colortex5), or scene depth.
 * ============================================================================= */

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec4 vVertexColor;
in vec3 vPlayerPos;

uniform sampler2D gtexture;
uniform float rainStrength;

/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 outWeather;
/*
const int colortex3Format = RGBA16F;
*/
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

void main() {
    vec4 texSample = texture(gtexture, vTexCoord) * vVertexColor;
    if (texSample.a < 0.02) {
        discard;
    }

    // Smooth engine precipitation cylinder bounds (+/-10m vertical, 5m/10m radial)
    // so upward, downward, horizon, and elevated views do not show hard cutoffs.
    float radialDist   = length(vPlayerPos);
    float horizDist    = length(vPlayerPos.xz);
    float nearFade     = smoothstep(0.45, 1.35, radialDist);
    float verticalFade = 1.0 - smoothstep(5.2, 9.6, abs(vPlayerPos.y));
    float horizFade    = 1.0 - smoothstep(4.5, 9.8, horizDist) * 0.55;
    float shelterFade  = smoothstep(0.02, 0.16, vLmCoord.y);
    float boundsWeight = nearFade * verticalFade * horizFade * shelterFade;

    if (boundsWeight <= 0.002) {
        discard;
    }

    // Distinguish vanilla rain.png (saturated blue streaks) from snow.png (neutral white flakes).
    float blueExcess = clamp((texSample.b - max(texSample.r, texSample.g * 0.85)) * 2.5, 0.0, 1.0);
    bool isSnow = (blueExcess < 0.15);

    // Strip the raw blue tint from rain by extracting neutral streak luminance.
    float streakIntensity = isSnow
        ? clamp(dot(texSample.rgb, vec3(0.3333)), 0.55, 1.0)
        : clamp(dot(texSample.rgb, vec3(0.20, 0.35, 0.45)) * 1.35, 0.45, 1.0);

    float shapedAlpha = isSnow
        ? smoothstep(0.02, 0.45, texSample.a) * 0.62
        : smoothstep(0.02, 0.58, texSample.a) * (0.18 + 0.08 * clamp(rainStrength, 0.0, 1.0));

    float finalAlpha = clamp(shapedAlpha * boundsWeight, 0.0, 0.75);
    if (finalAlpha <= 0.002) {
        discard;
    }

    // Pack (streakIntensity, blockLight, isSnowFlag, alpha) into colortex3.
    outWeather = vec4(streakIntensity, vLmCoord.x, isSnow ? 1.0 : 0.0, finalAlpha);
}
