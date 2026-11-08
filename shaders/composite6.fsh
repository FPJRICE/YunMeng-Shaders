#version 330 compatibility
#include "/lib/camera_options.glsl"
noperspective in vec2 vTexCoord;
#include "/lib/camera_motion.glsl"
#if MOTION_BLUR == 2
uniform sampler2D colortex7;
#endif
/* RENDERTARGETS: 4 */
#if MOTION_BLUR > 0
/*
const int colortex4Format = RGBA16F;
*/
#endif
layout(location = 0) out vec4 outColor;

// Interleaved Gradient Noise for jittering motion blur taps into a continuous shutter integration
float motionBlurIGN(vec2 pixelCoord) {
    vec2 temporal = vec2(float(frameCounter % 64) * 5.588238);
    return fract(52.9829189 * fract(dot(pixelCoord + temporal, vec2(0.06711056, 0.00583715))));
}

void gatherBlur(vec2 uv, float centerDepth, bool sky, float weight, inout vec3 sum, inout float total) {
    ivec2 size = textureSize(colortex0, 0);
    vec2 q = uv * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(q));
    vec2 fraction = fract(q);
    for (int y = 0; y < 2; y++) for (int x = 0; x < 2; x++) {
        ivec2 p = base + ivec2(x, y);
        if (any(lessThan(p, ivec2(0))) || any(greaterThanEqual(p, size))) continue;
        if (handPixel(p)) continue;

        float d = texelFetch(depthtex0, p, 0).r;
        bool sampleSky = d >= 0.999999;

        // Smooth depth-similarity weight prevents foreground silhouettes from bleeding onto background
        // while avoiding harsh unblurred seams along terrain and water edges during camera pans.
        float depthWeight = 1.0;
        if (sky != sampleSky) {
            // Allow background sky to blend softly if sample is far, but never bleed close foreground onto sky
            float sampleLin = sampleSky ? 1000.0 : linearDepth(d);
            depthWeight = smoothstep(12.0, 48.0, min(centerDepth, sampleLin)) * 0.35;
        } else if (!sky) {
            float sampleLin = linearDepth(d);
            float delta = abs(sampleLin - centerDepth);
            float tolerance = max(0.35, centerDepth * 0.08);
            depthWeight = exp(-delta / tolerance);
        }
        if (depthWeight <= 0.01) continue;

        vec2 w = mix(vec2(1.0) - fraction, fraction, vec2(x, y));
        float contribution = w.x * w.y * weight * depthWeight;
        sum += texelFetch(colortex0, p, 0).rgb * contribution;
        total += contribution;
    }
}

vec3 motionBlur(vec2 uv) {
    vec3 center = texture(colortex0, uv).rgb;
#if MOTION_BLUR == 0
    return center;
#else
    ivec2 size = textureSize(colortex0, 0);
    ivec2 p = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    if (handPixel(p) || MOTION_BLUR_STRENGTH <= 0.0 || !cameraHistoryUsable()) return center;

    float d = texelFetch(depthtex0, p, 0).r;
    bool sky = d >= 0.999999;
    float centerDepth = sky ? 1000.0 : linearDepth(d);

    float previousDepth;
    vec2 previousUV = previousSampleUV(uv, d, previousDepth);
    if (any(lessThan(previousUV, vec2(0.0))) || any(greaterThan(previousUV, vec2(1.0)))) return center;

    vec2 velocity = (previousUV - uv) * vec2(size);
#if MOTION_BLUR == 2
    vec4 trackedMotion = texelFetch(colortex7, p, 0);
    if (trackedMotion.w > 0.5) velocity = trackedMotion.xy * vec2(size);
#endif

    // Frame-rate independent shutter scale normalized to 60 Hz with smooth micro-motion deadzone
    float fpsScale = clamp((1.0 / 60.0) / max(frameTime, 0.001), 0.25, 3.5);
    velocity *= MOTION_BLUR_STRENGTH * fpsScale * 0.85;
    if (any(isnan(velocity)) || any(isinf(velocity))) return center;

    float speed = length(velocity);
    if (speed < 0.35) return center;

    // Soft-knee velocity clamp prevents extreme wide-angle turns from over-stretching
    float maxTrail = max(3.0, min(28.0, 18.0 * float(size.y) / 1080.0));
    float clampedSpeed = maxTrail * (1.0 - exp(-speed / maxTrail));
    velocity *= (clampedSpeed / max(speed, 1e-4)) * smoothstep(0.35, 1.15, speed);

    vec2 trail = velocity / vec2(size);
    float jitter = motionBlurIGN(gl_FragCoord.xy) - 0.5;

    const int TAPS = (MOTION_BLUR == 1) ? 8 : 12;
    // Preserve the center's relative weight when reducing shutter samples.
    float centerWeight = 1.25 * float(TAPS) / float(MOTION_BLUR == 1 ? 10 : 16);
    vec3 sum = center * centerWeight;
    float total = centerWeight;
    for (int i = 0; i < TAPS; i++) {
        float t = ((float(i) + 0.5 + jitter * 0.85) / float(TAPS)) - 0.5;
        // Smooth Gaussian shutter window weights center taps higher than trail tips
        float windowWeight = exp(-t * t * 4.5);
        vec2 sampleUV = clamp(uv + trail * t, vec2(0.001), vec2(0.999));
        gatherBlur(sampleUV, centerDepth, sky, windowWeight, sum, total);
    }
    return sum / max(total, 1e-4);
#endif
}

void main() {
    outColor = vec4(motionBlur(vTexCoord), 1.0);
}
