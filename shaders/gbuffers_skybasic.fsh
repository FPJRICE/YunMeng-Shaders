#version 330 compatibility
in vec4 vStarData;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

void main() {
    if (vStarData.a > 0.5) {
        outColor0 = vec4(vStarData.rgb * 1.25, 1.0);
    } else {
        outColor0 = vec4(0.0, 0.0, 0.0, 0.0);
    }
}
