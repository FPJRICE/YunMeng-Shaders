#version 330 compatibility
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform int worldTime;

noperspective out vec2 vTexCoord;
flat out vec3 vLightViewDir;
flat out vec3 vSunViewDir;
flat out vec3 vMoonViewDir;
flat out vec3 vSunWorldDir;
flat out vec3 vMoonWorldDir;
flat out vec3 vUpViewDir;
flat out float vDaylightFactor;
flat out float vTwilightFactor;
flat out float vNightFactor;

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
}
