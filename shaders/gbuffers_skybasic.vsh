#version 330 compatibility
#include "/lib/camera_vertex.glsl"
out vec4 vStarData;
void main() {
    gl_Position = ftransform();
    bool isVanillaStar = (gl_Color.r > 0.0 && abs(gl_Color.r - gl_Color.g) < 0.002 && abs(gl_Color.g - gl_Color.b) < 0.002);
    vStarData = vec4(gl_Color.rgb, float(isVanillaStar));
    applyCameraJitter(gl_Position);
}
