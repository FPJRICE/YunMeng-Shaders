#version 330 compatibility
in vec4 vStarData;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

void main() {
    if (vStarData.a > 0.5) {
        vec3 starCol = max(vStarData.rgb * 1.85, vec3(0.62, 0.68, 0.80) * smoothstep(0.02, 0.28, vStarData.r));
        outColor0 = vec4(starCol, 1.0);
    } else {
        outColor0 = vec4(0.0, 0.0, 0.0, 0.0);
    }
}
