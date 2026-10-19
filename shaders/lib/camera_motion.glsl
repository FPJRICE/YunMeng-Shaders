#ifndef YUNMENG_CAMERA_MOTION
#define YUNMENG_CAMERA_MOTION
#include "/lib/temporal_jitter.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
uniform sampler2D colortex5;
#endif
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float frameTime;
uniform int frameCounter;
uniform int isEyeInWater;
uniform float near;
uniform float far;
float linearDepth(float d) {
    return (2.0 * near * far) / max(far + near - (2.0 * d - 1.0) * (far - near), 0.00001);
}
bool handPixel(ivec2 p) { return abs(texelFetch(colortex1, p, 0).a - 0.12) < 0.007; }
bool entityPixel(ivec2 p) { return abs(texelFetch(colortex1, p, 0).a - 0.10) < 0.007; }
bool cameraHistoryUsable() {
    if (frameCounter < 2 || frameTime <= 0.0 || frameTime > 0.10) return false;
    if (length(cameraPosition - previousCameraPosition) > 4.0) return false;
    float projectionDelta = 0.0;
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++)
        projectionDelta = max(projectionDelta, abs(gbufferProjection[i][j] - gbufferPreviousProjection[i][j]));
    if (projectionDelta > 0.001) return false;
    vec3 previousForward = mat3(gbufferPreviousModelView) * mat3(gbufferModelViewInverse) * vec3(0.0, 0.0, -1.0);
    return dot(previousForward, vec3(0.0, 0.0, -1.0)) >= 0.866;
}
vec2 previousSampleUV(vec2 uv, float depth, out float previousDepth) {
    ivec2 size = textureSize(colortex0, 0);
    vec2 jitter = cameraJitter(frameCounter, vec2(size));
    vec4 view = gbufferProjectionInverse * vec4((uv - jitter) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    previousDepth = 0.0;
    if (abs(view.w) < 1e-7) return vec2(-1.0);
    view.xyz /= view.w;
    vec4 previousView;
    if (depth >= 0.999999) {
        vec3 worldRay = mat3(gbufferModelViewInverse) * normalize(view.xyz);
        previousView = vec4(mat3(gbufferPreviousModelView) * worldRay, 0.0);
    } else {
        vec3 previousPlayer = (gbufferModelViewInverse * vec4(view.xyz, 1.0)).xyz + cameraPosition - previousCameraPosition;
#if MOTION_BLUR > 0 || ANTI_ALIASING == 3
        ivec2 p = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
        vec4 motion = texelFetch(colortex5, p, 0);
        if (motion.a > 0.5) previousPlayer -= motion.xyz;
#endif
        previousView = gbufferPreviousModelView * vec4(previousPlayer, 1.0);
        previousDepth = -previousView.z;
    }
    vec4 previousClip = gbufferPreviousProjection * previousView;
    if (previousClip.w <= 1e-5) return vec2(-1.0);
    // History uses the output pixel grid; raster jitter is excluded from motion.
    return previousClip.xy / previousClip.w * 0.5 + 0.5 + jitter;
}
#endif
