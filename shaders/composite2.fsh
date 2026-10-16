#version 330 compatibility
#include "/lib/camera_options.glsl"
noperspective in vec2 vTexCoord;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float frameTime;
uniform int frameCounter;
uniform float near;
uniform float far;
/* RENDERTARGETS: 4 */
#if MOTION_BLUR > 0
/*
const int colortex4Format = RGBA16F;
*/
#endif
layout(location = 0) out vec4 outColor;
float linearDepth(float d) { return (2.0*near*far)/max(far+near-(2.0*d-1.0)*(far-near),0.00001); }
bool handPixel(ivec2 p) { return abs(texelFetch(colortex1,p,0).a-0.12)<0.007; }
// Each bilinear contributor is checked: foreground/hand pixels cannot bleed in
// through a color filter even when the requested UV itself lies on background.
void gatherBlur(vec2 uv, float centerDepth, bool sky, bool water, float weight, inout vec3 sum, inout float total) {
    ivec2 size = textureSize(colortex0,0);
    vec2 q = uv*vec2(size)-0.5;
    ivec2 base = ivec2(floor(q));
    vec2 fraction = fract(q);
    for (int y=0;y<2;y++) for (int x=0;x<2;x++) {
        ivec2 p = base+ivec2(x,y);
        if (any(lessThan(p,ivec2(0))) || any(greaterThanEqual(p,size))) continue;
        float d = texelFetch(depthtex0,p,0).r;
        bool sampleSky = d>=0.999999;
        if (sky!=sampleSky || handPixel(p)) continue;
        if (!sky) {
            bool sampleWater = abs(texelFetch(colortex1,p,0).a-0.90)<0.05;
            if (water!=sampleWater) continue;
            float delta = abs(linearDepth(d)-centerDepth);
            if (delta>max(0.10,centerDepth*0.03)) continue;
        }
        vec2 w = mix(vec2(1.0)-fraction,fraction,vec2(x,y));
        float contribution = w.x*w.y*weight;
        sum += texelFetch(colortex0,p,0).rgb*contribution;
        total += contribution;
    }
}
vec3 cameraBlur(vec2 uv) {
    vec3 center = texture(colortex0,uv).rgb;
#if MOTION_BLUR == 0
    return center;
#else
    ivec2 size = textureSize(colortex0,0);
    ivec2 p = clamp(ivec2(uv*vec2(size)),ivec2(0),size-1);
    if (handPixel(p) || MOTION_BLUR_STRENGTH<=0.0 || frameCounter<2 || frameTime<=0.0 || frameTime>0.10) return center;
    vec3 translation = cameraPosition-previousCameraPosition;
    if (length(translation)>4.0) return center;
    float projectionDelta = 0.0;
    for (int i=0;i<4;i++) for (int j=0;j<4;j++)
        projectionDelta = max(projectionDelta,abs(gbufferProjection[i][j]-gbufferPreviousProjection[i][j]));
    if (projectionDelta>0.001) return center;
    // Reject large view cuts; no frame history is retained.
    vec3 previousForward = mat3(gbufferPreviousModelView)*mat3(gbufferModelViewInverse)*vec3(0,0,-1);
    if (dot(previousForward,vec3(0,0,-1))<0.866) return center;
    float d = texelFetch(depthtex0,p,0).r;
    bool sky = d>=0.999999;
    vec4 view = gbufferProjectionInverse*vec4(uv*2.0-1.0,d*2.0-1.0,1.0);
    if (abs(view.w)<1e-7) return center;
    view.xyz /= view.w;
    vec4 previousView;
    if (sky) {
        // Infinite sky responds to camera rotation, not translation.
        vec3 worldRay = mat3(gbufferModelViewInverse)*normalize(view.xyz);
        previousView = vec4(mat3(gbufferPreviousModelView)*worldRay,0.0);
    } else {
        vec3 previousPlayer = (gbufferModelViewInverse*vec4(view.xyz,1.0)).xyz+translation;
        previousView = gbufferPreviousModelView*vec4(previousPlayer,1.0);
    }
    vec4 previousClip = gbufferPreviousProjection*previousView;
    if (previousClip.w<=1e-5) return center;
    vec2 previousUV = previousClip.xy/previousClip.w*0.5+0.5;
    vec2 velocity = (previousUV-uv)*vec2(size);
    // Fixed shutter duration relative to 60 FPS, rather than FPS-dependent strength.
    velocity *= MOTION_BLUR_STRENGTH*min(4.0,(1.0/60.0)/max(frameTime,0.001));
    if (any(isnan(velocity)) || any(isinf(velocity))) return center;
    float speed = length(velocity);
    if (speed<0.15) return center;
    float maxTrail = max(2.0,min(24.0,16.0*float(size.y)/1080.0));
    velocity *= min(1.0,maxTrail/max(speed,0.001));
    vec2 trail = velocity/vec2(size);
    vec3 sum = center;
    float total = 1.0;
    bool water = abs(texelFetch(colortex1,p,0).a-0.90)<0.05;
    const int TAPS = (MOTION_BLUR==1) ? 6 : 10;
    for (int i=0;i<TAPS;i++) {
        float t = (float(i)+0.5)/float(TAPS)-0.5;
        gatherBlur(uv+trail*t,linearDepth(d),sky,water,1.0-abs(t),sum,total);
    }
    return sum/total;
#endif
}
void main() { outColor=vec4(cameraBlur(vTexCoord),1.0); }
