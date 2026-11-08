#version 330 compatibility
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform float near;
uniform float far;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;

noperspective out vec2 vTexCoord;
flat out vec3 vLightViewDir;
flat out vec3 vSunViewDir;
flat out vec3 vMoonViewDir;
flat out vec3 vSunWorldDir;
flat out vec3 vMoonWorldDir;
flat out vec3 vUpViewDir;
flat out vec3 vHandPlayerOrigin;
flat out float vDaylightFactor;
flat out float vTwilightFactor;
flat out float vNightFactor;

float linearizeDepthVsh(float d) {
    return (2.0 * near * far) / max(far + near - (d * 2.0 - 1.0) * (far - near), 1e-5);
}

void main() {
    gl_Position = ftransform();
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    vUpViewDir = normalize(gbufferModelView[1].xyz);
    vec3 sunDir = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);

    float sunElevation = dot(sunDir, vUpViewDir);
    vDaylightFactor = smoothstep(-0.12, 0.14, sunElevation);
    vTwilightFactor = pow(clamp(1.0 - abs(sunElevation - 0.03) * 3.6, 0.0, 1.0), 1.4);
    vNightFactor    = 1.0 - vDaylightFactor;

    mat3 viewToWorld = mat3(gbufferModelViewInverse);
    vSunViewDir     = sunDir;
    vMoonViewDir    = moonDir;
    vSunWorldDir    = normalize(viewToWorld * sunDir);
    vMoonWorldDir   = normalize(viewToWorld * moonDir);
    // Use the same source as the engine's shadow map. Opposing sun/moon vectors
    // must not be interpolated: they would collapse to zero at the handoff.
    float shadowLength2 = dot(shadowLightPosition, shadowLightPosition);
    vLightViewDir = (shadowLength2 > 1e-6)
        ? shadowLightPosition * inversesqrt(shadowLength2)
        : ((sunElevation >= 0.0) ? sunDir : moonDir);

    // Detect 1st-person hand geometry (tag 0.12) across both right- and left-handed viewmodel zones,
    // including low-profile held blocks (such as End Portal Frames) at the bottom edge of the screen.
    bool hasFirstPersonHand = false;
    for (int y = 0; y < 5; ++y) {
        float py = 0.03 + float(y) * 0.08;
        for (int x = 0; x < 5; ++x) {
            float pxR = 0.56 + float(x) * 0.095;
            float pxL = 0.06 + float(x) * 0.095;
            if (abs(textureLod(colortex1, vec2(pxR, py), 0.0).a - 0.12) < 0.01 ||
                abs(textureLod(colortex1, vec2(pxL, py), 0.0).a - 0.12) < 0.01) {
                hasFirstPersonHand = true;
            }
        }
    }

    float minEntityDist = 100.0;
    int centerEntityHits = 0;
    if (!hasFirstPersonHand) {
        // In 3rd person (F5), Camera.move(-getMaxZoom(4.0), 0, 0) places the player's head/torso
        // directly on the center view axis (uv = 0.5, 0.5). Require multiple vertical spine hits
        // on true entity geometry (tag 0.10) so small crosshair targets never false-trigger F5 mode.
        const vec2 CENTER_TAPS[9] = vec2[9](
            vec2(0.50, 0.50),
            vec2(0.50, 0.45),
            vec2(0.50, 0.40),
            vec2(0.50, 0.54),
            vec2(0.50, 0.35),
            vec2(0.48, 0.48),
            vec2(0.52, 0.48),
            vec2(0.48, 0.42),
            vec2(0.52, 0.42)
        );
        for (int i = 0; i < 9; ++i) {
            float tag = textureLod(colortex1, CENTER_TAPS[i], 0.0).a;
            if (abs(tag - 0.10) < 0.015) {
                float d = linearizeDepthVsh(textureLod(depthtex0, CENTER_TAPS[i], 0.0).r);
                if (d > 0.65 && d < 4.65) {
                    centerEntityHits += 1;
                    minEntityDist = min(minEntityDist, d);
                }
            }
        }
    }

    if (centerEntityHits >= 2) {
        // Lock to Minecraft's exact 4.0m 3rd-person pivot distance when unoccluded so walking
        // limb animations never jitter the light origin between frames.
        float pivotDist = (minEntityDist > 2.60) ? 4.00 : clamp(minEntityDist + 0.25, 1.00, 4.00);
        vec3 pivotPlayerPos = (gbufferModelViewInverse * vec4(0.0, 0.0, -pivotDist, 1.0)).xyz;
        vHandPlayerOrigin = pivotPlayerPos + vec3(0.0, -0.35, 0.0);
    } else {
        vHandPlayerOrigin = vec3(0.0, -0.35, 0.0);
    }
}
