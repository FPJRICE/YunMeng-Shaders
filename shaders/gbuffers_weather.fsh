#version 330 compatibility
/* =============================================================================
 * gbuffers_weather.fsh — Dedicated atmospheric precipitation accumulation pass
 * Replaces dense vanilla rain curtains with sparse, style-matched procedural
 * rain (Silk-Needle Rain in Wuxia Smooth; Crisp Minimal Voxel Rain in Voxel)
 * while preserving clean vanilla snowflakes.
 * ============================================================================= */

#define SKY_STYLE 0       // [0 1] 0: Wuxia Smooth, 1: Minecraft Voxel
#define WIND_SPEED 1.00   // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec4 vVertexColor;
in vec3 vPlayerPos;
in vec3 vWorldPos;

uniform sampler2D gtexture;
uniform float rainStrength;
uniform float thunderStrength;
uniform float frameTimeCounter;

/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 outWeather;
/*
const int colortex3Format = RGBA16F;
*/
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

float weatherHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

bool detectSnowTexture() {
    // Alpha-weighted probe across 4 fixed UVs distinguishes vanilla rain.png (blue)
    // from snow.png (neutral white) reliably on every pixel of the precipitation quad.
    vec4 s0 = texture(gtexture, vec2(0.18, 0.22));
    vec4 s1 = texture(gtexture, vec2(0.52, 0.48));
    vec4 s2 = texture(gtexture, vec2(0.78, 0.32));
    vec4 s3 = texture(gtexture, vec2(0.34, 0.78));
    vec3 rgbSum = s0.rgb * s0.a + s1.rgb * s1.a + s2.rgb * s2.a + s3.rgb * s3.a;
    float aSum  = s0.a + s1.a + s2.a + s3.a;
    if (aSum < 0.01) return false;
    vec3 avgRgb = rgbSum / aSum;
    float blueExcess = avgRgb.b - max(avgRgb.r, avgRgb.g * 0.88);
    return (blueExcess < 0.08);
}

void main() {
    float radialDist   = length(vPlayerPos);
    float horizDist    = length(vPlayerPos.xz);
    float shelterFade  = smoothstep(0.02, 0.16, vLmCoord.y);
    float verticalFade = 1.0 - smoothstep(5.4, 9.6, abs(vPlayerPos.y));
    float horizFade    = 1.0 - smoothstep(7.2, 9.9, horizDist) * 0.28;

    if (shelterFade <= 0.002 || verticalFade <= 0.002) {
        discard;
    }

    bool isSnow = detectSnowTexture();
    if (isSnow) {
        vec4 texSample = texture(gtexture, vTexCoord) * vVertexColor;
        if (texSample.a < 0.02) discard;
        float nearFade = smoothstep(0.55, 1.45, radialDist);
        float boundsWeight = nearFade * verticalFade * horizFade * shelterFade;
        float streakIntensity = clamp(dot(texSample.rgb, vec3(0.3333)), 0.55, 1.0);
        float finalAlpha = clamp(smoothstep(0.02, 0.45, texSample.a) * 0.60 * boundsWeight, 0.0, 0.72);
        if (finalAlpha <= 0.002) discard;
        outWeather = vec4(streakIntensity, vLmCoord.x, 1.0, finalAlpha);
        return;
    }

    // Push near-camera clearance out slightly so drops never clutter the player's face
    float nearFade = smoothstep(1.15, 2.35, radialDist);
    float boundsWeight = nearFade * verticalFade * horizFade * shelterFade;
    if (boundsWeight <= 0.002) {
        discard;
    }

    float stormBoost = clamp(thunderStrength, 0.0, 1.0);
    float rainWeight = clamp(rainStrength, 0.0, 1.0);
    vec2 colCell = floor(vWorldPos.xz);

    float dropMask = 0.0;
    float streakIntensity = 0.78;

    #if SKY_STYLE == 1
    // Concept 3: Crisp Minimal Voxel Rain (slender 1-pixel-wide sparse droplets, ~62% sparser than vanilla)
    float pxU = floor(fract(vTexCoord.x) * 16.0);
    vec2 laneKey = colCell * 16.0 + vec2(pxU, 0.0);
    float hKeep = weatherHash12(laneKey + vec2(13.7, 29.3));
    float keepThreshold = mix(0.84, 0.76, stormBoost);
    if (hKeep < keepThreshold) discard;

    float hPhase = weatherHash12(laneKey + vec2(47.1, 71.9));
    float hSpeed = weatherHash12(laneKey + vec2(83.3, 19.1));
    float fallSpeed = (10.5 + 4.5 * hSpeed) * max(WIND_SPEED, 0.35);
    float pxY = floor((vWorldPos.y + frameTimeCounter * fallSpeed + hPhase * 24.0) * 16.0);
    float periodPx = 96.0 + floor(hPhase * 48.0);
    float inPeriod = mod(pxY, periodPx);
    float dropLenPx = 6.0 + floor(hSpeed * 4.0);
    if (inPeriod >= dropLenPx) discard;

    // 2-step voxel head-to-tail fade (brighter droplet tip at bottom, softer tail above)
    float headT = 1.0 - (inPeriod / dropLenPx);
    dropMask = (headT > 0.65) ? 0.95 : ((headT > 0.30) ? 0.60 : 0.32);
    streakIntensity = 0.68 + 0.28 * headT;
    #else
    // Concept 1 + 2: Wuxia Smooth Silk-Needle Rain (sparse, razor-thin tapered streaks with mist fade)
    float subLane = floor(fract(vTexCoord.x) * 2.0);
    float laneU   = fract(fract(vTexCoord.x) * 2.0);
    vec2 laneKey  = colCell * 2.0 + vec2(subLane, 0.0);

    float hKeep = weatherHash12(laneKey + vec2(17.3, 41.9));
    float keepThreshold = mix(0.62, 0.48, stormBoost);
    if (hKeep < keepThreshold) discard;

    float hX     = weatherHash12(laneKey + vec2(53.1, 11.7));
    float hPhase = weatherHash12(laneKey + vec2(29.7, 83.3));
    float hSpeed = weatherHash12(laneKey + vec2(71.3, 37.1));

    float centerU = 0.18 + 0.64 * hX;
    float distU   = abs(laneU - centerU);
    float needleWidth = mix(0.026, 0.036, stormBoost);
    float crossProfile = exp(-pow(distU / needleWidth, 2.0));
    if (crossProfile < 0.02) discard;

    float fallSpeed = (13.0 + 5.5 * hSpeed) * max(WIND_SPEED, 0.35);
    float cycleLen  = 9.5 + 4.5 * hPhase;
    float streakLen = 2.1 + 1.4 * hSpeed;
    float yLocal    = mod(vWorldPos.y + frameTimeCounter * fallSpeed + hPhase * 32.0, cycleLen);
    if (yLocal > streakLen) discard;

    // Smooth needle taper: crisp bright droplet tip (yLocal -> 0), delicate vanishing tail (yLocal -> streakLen)
    float alongT = yLocal / streakLen;
    float taper  = smoothstep(0.0, 0.14, alongT) * pow(1.0 - alongT, 1.35);
    dropMask = crossProfile * taper;
    streakIntensity = 0.62 + 0.36 * (1.0 - alongT);
    #endif

    // Preserve outer-ring cylinder visibility (4-10m) so zooming in still reads continuous rain
    float mistDamp = mix(1.0, 0.82, smoothstep(5.5, 9.8, horizDist));
    float baseAlpha = (SKY_STYLE == 1)
        ? (0.22 + 0.10 * rainWeight + 0.06 * stormBoost)
        : (0.24 + 0.10 * rainWeight + 0.06 * stormBoost);
    float finalAlpha = clamp(dropMask * baseAlpha * mistDamp * boundsWeight, 0.0, 0.54);
    if (finalAlpha <= 0.003) discard;

    outWeather = vec4(streakIntensity, vLmCoord.x, 0.0, finalAlpha);
}
