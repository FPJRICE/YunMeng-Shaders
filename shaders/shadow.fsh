#version 330 compatibility
in vec2 vTexCoord;
in vec4 vVertexColor;
uniform sampler2D gtexture;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outShadowColor0;

void main() {
    vec4 texSample = texture(gtexture, vTexCoord);
    if (texSample.a < 0.15) {
        discard;
    }
    outShadowColor0 = vec4(texSample.rgb * vVertexColor.rgb, texSample.a);
}
